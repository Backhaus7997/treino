/**
 * reconcile.ts — el unico lugar que escribe `users/{uid}.subscription` a partir
 * de Mercado Pago. Es lo que hace que pagar SIGNIFIQUE algo.
 *
 * Sin esto, `createPreapproval` abre un cobro y nadie se entera: el PF paga y
 * su limite no se mueve.
 *
 * ── EL PRINCIPIO, otra vez porque acá se aplica ──
 *
 * La verdad se le PREGUNTA a MP con un GET usando nuestro token. Nunca se
 * asume, nunca se lee de un body entrante. Ver el encabezado de `client.ts`.
 *
 * Consecuencia practica: esta funcion recibe UN id de PLAN y nada mas, y le
 * pregunta a MP que suscripciones existen contra el.
 *
 * Se busca por plan y no por id de suscripcion porque el plan lo creamos
 * NOSOTROS —su id ya esta en `mp_plans` desde que el PF toco comprar— mientras
 * que de la suscripcion no sabemos nada hasta que alguien paga. Ademas no esta
 * verificado que la suscripcion herede el `external_reference` del plan, asi
 * que buscarla por ahi seria apostar a lo que no sabemos.
 *
 * El webhook —cuando exista— trae un id de SUSCRIPCION, no de plan. Va a tener
 * que resolver el plan primero (el preapproval trae `preapproval_plan_id`) y
 * despues llamar acá. El barrido agendado la llama con los planes que ya
 * conocemos. Por eso el producto anda aunque el webhook no llegue nunca: se
 * pierde latencia, no correccion.
 *
 * ── CUANDO NO ESCRIBE, que es la parte que importa ──
 *
 * `subscription-state.ts` dejo escrita la politica, y no se reinventa acá:
 *
 *   La degradacion de datos frena TRABAJO NUEVO, pero NUNCA revoca relaciones
 *   existentes.
 *
 * Escribir un estado que no entendimos NO es neutral: bajaria al PF al limite
 * Free y el barrido de las 04:00 le bloquearia alumnos. O sea que un dato raro
 * de MP terminaria cortandole el servicio a alumnos que no tienen nada que ver.
 *
 * Por eso hay cuatro casos donde esta funcion NO toca el documento:
 *
 *   1. El estado de MP no se entiende (`degraded`).
 *   2. No sabemos de que plan es la suscripcion.
 *   3. El uid del mapeo no coincide con el `external_reference` de MP.
 *   4. Lo que ibamos a escribir es identico a lo que ya esta.
 *
 * El (4) no es una optimizacion: cada escritura de `users/{uid}` dispara
 * `syncEntitlementsOnSubscription`, que decide MAIL por transicion. Reescribir
 * el mismo valor gasta invocaciones al pedo, y una regresion futura en la
 * deteccion de transiciones se convertiria en una tormenta de mails.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

import { SubscriptionStatus } from "../effective-limit";
import { SubscriptionTier } from "../tier-config";
import { MpApiError, MpClient, createMpClient } from "./client";
import { hayCobroPendiente, mapMpStatus } from "./map-status";
import {
  MP_PLANS_COLLECTION,
  lookupPlan,
} from "./tier-mapping";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

export type ReconcileOutcome =
  | "written"
  | "unchanged"
  | "skipped-degraded"
  | "skipped-sin-plan"
  | "skipped-uid-no-coincide"
  | "sin-suscripcion"
  | "error-mp";

export interface ReconcileResult {
  planId: string;
  outcome: ReconcileOutcome;
  uid?: string;
  tier?: SubscriptionTier;
  status?: SubscriptionStatus;
}

export interface ReconcileDeps {
  mpClient: MpClient;
}

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * `next_payment_date` de MP → Timestamp, o `null`.
 *
 * MP lo manda como ISO 8601. Cualquier otra cosa se trata como ausente y se
 * reporta: preferimos perder el dato a escribir una fecha inventada, porque
 * `currentPeriodEnd` es lo que decide cuanto le dura el plan a un PF que se
 * dio de baja.
 */
export function parsePeriodEnd(
  raw: unknown,
  planId: string,
): admin.firestore.Timestamp | null {
  if (raw == null) return null;
  if (typeof raw !== "string") {
    logger.warn("mp/reconcile: next_payment_date no es un string — se ignora", {
      planId,
      received: typeof raw,
    });
    return null;
  }
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    logger.warn("mp/reconcile: next_payment_date no es una fecha ISO valida", {
      planId,
      received: raw.slice(0, 40),
    });
    return null;
  }
  return admin.firestore.Timestamp.fromMillis(ms);
}

/** Los dos Timestamp son el mismo instante. Tolera nulls de los dos lados. */
function mismaFecha(
  a: admin.firestore.Timestamp | null,
  b: unknown,
): boolean {
  const bMs =
    b != null && typeof (b as { toMillis?: unknown }).toMillis === "function"
      ? (b as { toMillis: () => number }).toMillis()
      : null;
  return (a?.toMillis() ?? null) === bMs;
}

/**
 * Reconcilia UNA suscripcion contra MP.
 *
 * Total: nunca tira. Cualquier fallo se reporta en el `outcome` — un barrido
 * que se cae por un PF deja a todos los demas sin reconciliar.
 */
export async function reconcileSubscription(
  app: admin.app.App,
  planId: string,
  deps: ReconcileDeps,
): Promise<ReconcileResult> {
  // Se busca POR PLAN y no por id de suscripcion, y esa es la diferencia con la
  // version anterior: el plan lo creamos NOSOTROS y su id ya esta guardado en
  // `mp_plans`. De la suscripcion no sabemos nada hasta que alguien paga — y no
  // esta verificado que herede el `external_reference` del plan, asi que
  // buscarla por ahi seria apostar a lo que no sabemos.
  let subs;
  try {
    subs = await deps.mpClient.searchPreapprovalsByPlan(planId);
  } catch (e) {
    const err = e as MpApiError;
    logger.error("mp/reconcile: no se pudieron buscar las suscripciones del plan", {
      planId: planId,
      status: err.status,
      retryable: err.retryable,
    });
    return { planId, outcome: "error-mp" };
  }

  // Cero suscripciones es el estado NORMAL de un plan recien creado: el PF
  // abrio el checkout y todavia no pago, o lo abandono. No es un error y no se
  // logea — con un plan por checkout, la mayoria de los planes viejos van a
  // estar asi para siempre.
  if (subs.length === 0) {
    return { planId, outcome: "sin-suscripcion" };
  }
  // Mas de una sobre el mismo plan no deberia pasar —cada checkout crea el
  // suyo— pero si pasa se toma la primera y se avisa, en vez de elegir en
  // silencio.
  if (subs.length > 1) {
    logger.warn("mp/reconcile: el plan tiene mas de una suscripcion", {
      planId: planId,
      cuantas: subs.length,
    });
  }
  const mp = subs[0];

  const monto = (mp.auto_recurring as { transaction_amount?: unknown } | undefined)
    ?.transaction_amount;
  const mapping = await lookupPlan(app, planId, monto);

  if (!mapping) {
    // Ni el documento ni el monto nos dicen de que plan es. Escribir un tier
    // adivinado seria regalar o robar cupo; no escribir deja el estado anterior,
    // que es el ultimo que SI entendimos.
    logger.error("mp/reconcile: no se pudo determinar el plan — no se escribe", {
      planId,
      monto,
    });
    return { planId, outcome: "skipped-sin-plan" };
  }

  // El uid sale del mapeo; si el mapeo cayo al fallback por monto no lo trae, y
  // ahi lo pone MP en `external_reference` — que lo mandamos nosotros al crear.
  const externo = mp.external_reference;
  const uid = mapping.uid || (typeof externo === "string" ? externo : "");
  if (!uid) {
    logger.error("mp/reconcile: sin uid ni en el mapeo ni en external_reference", {
      planId,
    });
    return { planId, outcome: "skipped-sin-plan" };
  }

  // Los dos existen y NO coinciden: o alguien toco el documento de mapeo, o MP
  // nos esta contestando por otro recurso. En cualquiera de los dos casos
  // escribir le daria el plan de una persona a otra.
  if (
    mapping.uid &&
    typeof externo === "string" &&
    externo !== "" &&
    externo !== mapping.uid
  ) {
    logger.error(
      "mp/reconcile: el uid del mapeo no coincide con external_reference",
      { planId, mapeo: mapping.uid, externalReference: externo },
    );
    return { planId, outcome: "skipped-uid-no-coincide" };
  }

  const { status, degraded } = mapMpStatus({
    raw: mp.status,
    cobroPendiente: hayCobroPendiente(mp.summarized),
    trainerId: uid,
  });

  if (degraded) {
    // Ver el encabezado: escribir el fallback bajaria al PF a Free y el barrido
    // de las 04:00 le bloquearia alumnos por un dato que no entendimos.
    logger.error("mp/reconcile: estado de MP ininteligible — NO se escribe", {
      planId,
      uid,
      recibido: mp.status,
    });
    return { planId, outcome: "skipped-degraded", uid, tier: mapping.tier };
  }

  const userRef = app.firestore().collection("users").doc(uid);
  const actual = (await userRef.get()).data()?.subscription as
    | Record<string, unknown>
    | undefined;

  let periodEnd = parsePeriodEnd(mp.next_payment_date, planId);
  if (periodEnd === null && status === "cancelled") {
    // Una baja normalmente deja de tener proximo cobro. Si nos quedamos sin
    // fecha, `effective-limit` le saca el plan pago EN EL ACTO a alguien que
    // pago el periodo entero. Se conserva la que ya teniamos: la baja es
    // efectiva igual cuando esa fecha vence.
    const previa = actual?.currentPeriodEnd;
    if (
      previa != null &&
      typeof (previa as { toMillis?: unknown }).toMillis === "function"
    ) {
      periodEnd = previa as admin.firestore.Timestamp;
    }
  }

  const sinCambios =
    actual != null &&
    actual.tier === mapping.tier &&
    actual.status === status &&
    mismaFecha(periodEnd, actual.currentPeriodEnd);

  if (sinCambios) {
    return {
      planId,
      outcome: "unchanged",
      uid,
      tier: mapping.tier,
      status,
    };
  }

  await userRef.set(
    {
      subscription: {
        tier: mapping.tier,
        status,
        currentPeriodEnd: periodEnd,
      },
    },
    // `merge` y no `set` pelado: el documento de usuario tiene el perfil
    // entero. Sin merge, reconciliar una suscripcion borraria la cuenta.
    { merge: true },
  );

  // La baja es terminal en MP: no se reactiva un preapproval cancelado, se crea
  // uno nuevo con otro id. Marcarlo saca este id del barrido y le ahorra una
  // llamada diaria a MP para siempre.
  if (status === "cancelled") {
    await app
      .firestore()
      .collection(MP_PLANS_COLLECTION)
      .doc(planId)
      .set({ terminal: true }, { merge: true });
  }

  logger.info("mp/reconcile: suscripcion actualizada", {
    planId,
    uid,
    tier: mapping.tier,
    status,
  });

  return { planId, outcome: "written", uid, tier: mapping.tier, status };
}

export interface SweepResult {
  total: number;
  written: number;
  unchanged: number;
  skipped: number;
  errors: number;
}

/**
 * Reconcilia todo lo que conocemos. Handler puro para poder testearlo sin el
 * arnes de `onSchedule`.
 *
 * Recorre `mp_preapprovals` salteando los terminales. Es un scan de coleccion:
 * a la escala de hoy —decenas de entrenadores— es trivial, y cada documento
 * salteado es una llamada menos a MP. Cuando el volumen lo justifique, el filtro
 * natural es un `where('terminal', '!=', true)` con su indice; hoy seria
 * infraestructura para un problema que no existe.
 *
 * SECUENCIAL a proposito. En paralelo son N requests simultaneos a MP, que
 * responde 429 y nos deja sin reconciliar a la mitad de los PF. El barrido tiene
 * toda la madrugada.
 */
export async function reconcileAllSubscriptions(
  app: admin.app.App,
  deps: ReconcileDeps,
): Promise<SweepResult> {
  const snap = await app
    .firestore()
    .collection(MP_PLANS_COLLECTION)
    .get();

  const r: SweepResult = {
    total: 0,
    written: 0,
    unchanged: 0,
    skipped: 0,
    errors: 0,
  };

  for (const doc of snap.docs) {
    if (doc.data()?.terminal === true) continue;
    r.total += 1;

    // El try es por-PF, igual que en `entitlement-triggers`: un documento roto
    // no puede frenar el barrido de todos los demas.
    try {
      const res = await reconcileSubscription(app, doc.id, deps);
      if (res.outcome === "written") r.written += 1;
      else if (res.outcome === "unchanged") r.unchanged += 1;
      else if (res.outcome === "error-mp") r.errors += 1;
      else r.skipped += 1;
    } catch (err) {
      logger.error("mp/reconcile: error inesperado en un preapproval", {
        planId: doc.id,
        err,
      });
      r.errors += 1;
    }
  }

  return r;
}

export const reconcileMpSubscriptions = onSchedule(
  {
    // 03:00 ART, y la hora NO es arbitraria: `sweepEntitlements` corre a las
    // 04:00 y decide bloqueos leyendo `subscription`. Reconciliar despues
    // dejaria al barrido trabajando sobre el estado de ayer — un PF que pago
    // anoche seguiria con alumnos bloqueados un dia entero.
    schedule: "0 3 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN],
  },
  async () => {
    const r = await reconcileAllSubscriptions(getApp(), {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
    });
    logger.info("reconcileMpSubscriptions: corrida diaria", r);
  },
);
