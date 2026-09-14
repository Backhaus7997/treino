/**
 * athlete-paywall-enforced.ts — el unico escritor de
 * `users/{uid}.athletePaywallEnforced`.
 *
 * ─── Por que existe este campo ──────────────────────────────────────────────
 *
 * `firestore.rules` tiene que saber si a un alumno le muerde el plan free para
 * poder rebotarle una rutina de 3 dias. Pero el derecho del alumno sale de DOS
 * fuentes y las reglas solo pueden resolver una:
 *
 *   1. Su propia suscripcion — `users/{uid}.athleteSubscription`. Esa SI: es un
 *      campo del mismo doc, un `get()` la trae.
 *   2. Estar vinculado a un PF activo — su PF ya paga por el cupo, asi que el
 *      alumno vinculado no paga NUNCA (`docs/paywall-alumno-suelto.md` §2).
 *      Esa NO: vive en `trainer_links`, con ids AUTOGENERADOS, y las reglas no
 *      hacen queries — solo `get()` sobre un path que ya conoces. No hay forma
 *      de escribir "existe un link activo cuyo athleteId sea este".
 *
 * De ahi el campo denormalizado: esta CF cruza las dos fuentes y deja el
 * resultado como un booleano que la regla lee con un solo `get()`. El campo es
 * CF-write-only — lo pinea `firestore.rules` en el create y en el update de
 * `users/{uid}`, porque si no el alumno se auto-exime escribiendose `false`.
 *
 * ─── El interruptor, y por que arranca APAGADO ──────────────────────────────
 *
 * [ATHLETE_PAYWALL_ENFORCEMENT_ENABLED] arranca en `false`, espejando
 * `kAthletePaywallEnabled` del cliente. Con el interruptor apagado esta CF
 * igual corre y escribe `false` en todos lados: la plomeria queda ejercitada y
 * OBSERVABLE en produccion antes de que cobre importancia, y prender el paywall
 * pasa a ser un cambio de valor y nada mas. Apagarlo vuelve a limpiar el campo,
 * o sea que el rollback es real y no un deploy de emergencia.
 *
 * ─── ANTES DE PRENDERLO: el grandfathering ────────────────────────────────
 *
 * ✅ **RESUELTO el 2026-09-11**, en `firestore.rules`: `noCreceLaForma`.
 *
 * Lo que decia este parrafo, y que conviene dejar escrito porque era FALSO en
 * un punto que importaba:
 *
 *   > "esas rutinas dejan de poder editarse — el alumno no puede ni cargar una
 *   > serie sobre lo que ya tenia"
 *
 * La primera mitad era cierta. **La segunda no.** Cargar una serie escribe en
 * `sessions`, no en `routines`, y esa regla gatea por otra cosa
 * (`sesionSobreRutinaLibre`: si la rutina es una plantilla PAGA del catalogo).
 * El alumno con una rutina propia fuera de tope siempre pudo entrenarla entera.
 *
 * El dano real era mas chico y mas raro: podia usarla pero no renombrarla.
 *
 * Y el eje tampoco era el que decia. Medido sobre produccion el 2026-09-11: de
 * 18 alumnos con rutina propia, 5 quedaban congelados — pero solo 2 por DIAS.
 * Los otros 4 excedian el tope de SEMANAS (`kFreeMaxRoutineWeeks = 1`), y tres
 * de ellos estaban apenas en 2. Este comentario hablaba de dias, y el que
 * mordia era el otro.
 *
 * La solucion no necesito ni campo, ni fecha de corte, ni migracion: el UPDATE
 * ahora deja pasar si la rutina resultante NO ES MAS GRANDE que la que ya
 * habia. Ver el comentario de `noCreceLaForma` en `firestore.rules`.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  QueryDocumentSnapshot,
  getFirestore,
} from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** El interruptor. Ver el encabezado antes de tocarlo. */
export const ATHLETE_PAYWALL_ENFORCEMENT_ENABLED = false;

/** El campo que escribe este modulo, y nadie mas. */
export const ENFORCED_FIELD = "athletePaywallEnforced";

/**
 * Los `status` de `athleteSubscription` que OTORGAN derecho.
 *
 * Tiene que ser la misma lista que `kEntitlingSubscriptionStatuses` del cliente
 * (`lib/features/paywall/application/athlete_entitlement_provider.dart`). Si el
 * servidor fuera mas estricto que el cliente, el alumno veria el boton
 * habilitado y se comeria una denegacion — la peor falla posible de un gate.
 *
 * `grace` entra a proposito: es la ventana en que el cobro fallo pero todavia
 * se reintenta la tarjeta. Cortarle las funciones ahi es la peor forma de
 * pedirle que actualice el medio de pago.
 */
export const ENTITLING_SUBSCRIPTION_STATUSES = ["active", "grace"];

/** Cuantos alumnos trae por pagina el barrido. */
const SWEEP_PAGE_SIZE = 300;

/** Si el mapa `athleteSubscription` de este doc otorga derecho. */
export function hasEntitlingSubscription(
  userData: DocumentData | undefined,
): boolean {
  const sub = userData?.athleteSubscription;
  if (typeof sub !== "object" || sub === null) return false;
  const status = (sub as DocumentData).status;
  return typeof status === "string"
    && ENTITLING_SUBSCRIPTION_STATUSES.includes(status);
}

/**
 * Si cambio alguna de las ENTRADAS de la decision entre before y after.
 *
 * GUARDA ANTI-LOOP, load-bearing: esta CF ESCRIBE `athletePaywallEnforced` en
 * `users/{uid}`, que es el mismo documento que dispara su propio trigger. Sin
 * este chequeo cada corrida se auto-dispara y el bucle no termina nunca (y
 * factura sin parar). Mismo motivo y misma forma que `subscriptionChanged` en
 * `entitlement-triggers.ts`.
 *
 * Compara SOLO las entradas —`athleteSubscription` y `role`— y jamas la salida.
 * Por eso una escritura que toca unicamente el campo de salida da `false` y el
 * ciclo muere en la primera vuelta.
 *
 * El create cuenta siempre: un alumno recien registrado no tiene el campo, y
 * "ausente" para la regla significa NO enforced. Sin esta rama, un alumno nuevo
 * se saltearia el paywall hasta que tocara un vinculo o una suscripcion.
 */
export function athletePaywallInputChanged(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): boolean {
  if (after === undefined) return false; // doc borrado: no hay donde escribir
  if (before === undefined) return true; // create
  return JSON.stringify(before.athleteSubscription ?? null)
      !== JSON.stringify(after.athleteSubscription ?? null)
    || before.role !== after.role;
}

/**
 * Si este link cruzo la frontera de `active` en esta escritura.
 *
 * Segunda guarda anti-loop, contra un ciclo AJENO: `linkLoadReconcile` escribe
 * `entitlement` en `trainer_links` cada vez que se mueve la carga de un PF. Sin
 * este filtro, cada una de esas escrituras dispararia un recalculo de este
 * campo para un alumno cuya situacion no cambio.
 *
 * Solo importa `active`, que es exactamente lo que mira el cliente
 * (`currentAthleteLinkProvider`, statuses: {active}). Un `pending` o un
 * `paused` no otorgan derecho ni alla ni aca.
 */
export function linkActivityChanged(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): boolean {
  return (before?.status === "active") !== (after?.status === "active");
}

/** Si el alumno tiene algun vinculo ACTIVO con un PF. */
async function hasActiveTrainerLink(app: App, uid: string): Promise<boolean> {
  const snap = await getFirestore(app)
    .collection("trainer_links")
    .where("athleteId", "==", uid)
    .where("status", "==", "active")
    .limit(1)
    .get();
  return !snap.empty;
}

/**
 * El valor que le corresponde HOY a este alumno.
 *
 * Las salidas tempranas estan ordenadas por costo a proposito: con el
 * interruptor apagado —o sea, hoy— no se consulta `trainer_links` ni una sola
 * vez, asi que el barrido diario cuesta una lectura por alumno y nada mas. La
 * query de vinculos solo aparece para alumnos sin suscripcion que otorgue.
 *
 * `enabled` es parametro y no la constante leida directo por el mismo motivo
 * que `athletePaywallEnabledProvider` existe del lado del cliente: si no, el
 * camino PRENDIDO se shipearia sin un solo test encima.
 */
export async function resolveAthletePaywallEnforced(
  app: App,
  uid: string,
  userData: DocumentData | undefined,
  enabled: boolean = ATHLETE_PAYWALL_ENFORCEMENT_ENABLED,
): Promise<boolean> {
  if (!enabled) return false;
  // Un doc sin `role` (legacy) no se enforcea: ante la duda, se falla ABIERTO.
  // El gate del cliente sigue estando; esto es solo el piso del servidor.
  if (userData?.role !== "athlete") return false;
  if (hasEntitlingSubscription(userData)) return false;
  return !(await hasActiveTrainerLink(app, uid));
}

export interface SyncResult {
  uid: string;
  value: boolean;
  changed: boolean;
}

/**
 * Reconcilia el campo de UN alumno. Escribe solo si el valor cambia.
 *
 * Ese "solo si cambia" es la SEGUNDA red contra el loop, independiente de
 * `athletePaywallInputChanged`: aun si una escritura futura se colara por la
 * guarda, la segunda vuelta calcularia el mismo valor, no escribiria, y el
 * ciclo moriria igual. Dos redes porque una sola falla en silencio y lo que
 * factura es el bucle.
 *
 * Tambien es lo que hace barato al barrido en regimen: la primera corrida
 * escribe una vez por alumno, las siguientes no escriben nada.
 */
export async function syncAthletePaywallEnforced(
  app: App,
  uid: string,
  userData?: DocumentData,
  enabled: boolean = ATHLETE_PAYWALL_ENFORCEMENT_ENABLED,
): Promise<SyncResult> {
  const db = getFirestore(app);
  const ref = db.collection("users").doc(uid);

  let data = userData;
  if (data === undefined) {
    const snap = await ref.get();
    if (!snap.exists) return { uid, value: false, changed: false };
    data = snap.data();
  }

  const value = await resolveAthletePaywallEnforced(app, uid, data, enabled);
  if (data?.[ENFORCED_FIELD] === value) {
    return { uid, value, changed: false };
  }

  await ref.update({ [ENFORCED_FIELD]: value });
  return { uid, value, changed: true };
}

/**
 * Trigger 1 — la suscripcion del alumno, y su alta.
 *
 * Corre en `southamerica-east1` como el resto de los triggers de este modulo.
 */
export const syncAthletePaywallOnUser = onDocumentWritten(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!athletePaywallInputChanged(before, after)) return;

    // NO se sale temprano si el doc no es de un alumno, y es load-bearing: los
    // PF se aprovisionan con un `update({role:'trainer'})` SOBRE un doc que
    // nacio athlete. Si esa transicion se ignorara, el campo quedaria pegado en
    // `true` — y un PF que se entrena a si mismo escribe su rutina por el mismo
    // path de rutina propia que la regla gatea. `resolve` ya devuelve `false`
    // para todo lo que no sea un alumno, asi que dejarlo pasar LIMPIA el campo.
    const uid = event.params.uid;
    try {
      const r = await syncAthletePaywallEnforced(ensureApp(), uid, after);
      if (r.changed) {
        logger.info("syncAthletePaywallOnUser: reconciliado", {
          uid,
          enforced: r.value,
        });
      }
    } catch (err) {
      // Catch-and-log sin relanzar, igual que el resto de los triggers de
      // subscriptions: un doc malformado no debe provocar una tormenta de
      // reintentos.
      logger.error("syncAthletePaywallOnUser: error", { uid, err });
    }
  },
);

/**
 * Trigger 2 — el vinculo con el PF.
 *
 * Se recalcula contra la COLECCION, no contra el link que disparo: si el
 * alumno tuviera dos vinculos y se terminara uno, mirar solo ese diria
 * "sin PF" cuando todavia tiene el otro.
 */
export const syncAthletePaywallOnTrainerLink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!linkActivityChanged(before, after)) return;

    const uid = (after?.athleteId ?? before?.athleteId) as string | undefined;
    if (!uid) return;

    try {
      const r = await syncAthletePaywallEnforced(ensureApp(), uid);
      if (r.changed) {
        logger.info("syncAthletePaywallOnTrainerLink: reconciliado", {
          uid,
          enforced: r.value,
        });
      }
    } catch (err) {
      logger.error("syncAthletePaywallOnTrainerLink: error", { uid, err });
    }
  },
);

export interface SweepResult {
  scanned: number;
  changed: number;
}

/**
 * Barrido: reconcilia a TODO alumno.
 *
 * Hace dos trabajos que los triggers no pueden:
 *
 * 1. El BACKFILL. Los alumnos que ya existen cuando esto se despliega no
 *    escriben nada, asi que ningun trigger los ve. Sin el barrido, el campo
 *    llegaria goteando —solo a quien tocara un vinculo o una suscripcion— y
 *    prender el interruptor dejaria enforcement parcial y arbitrario.
 * 2. La deriva. Un trigger que fallo, un deploy en el medio de una escritura,
 *    un doc migrado a mano. Al dia siguiente queda reconciliado solo.
 *
 * Pagina en vez de traer la coleccion entera: `users` crece con el producto, y
 * el `.get()` sin limite del barrido de PF alcanza porque los PF son POCOS y se
 * crean a mano. Los alumnos no.
 */
export async function sweepAthletePaywallHandler(
  app: App,
  enabled: boolean = ATHLETE_PAYWALL_ENFORCEMENT_ENABLED,
): Promise<SweepResult> {
  const db = getFirestore(app);
  const base = db
    .collection("users")
    .where("role", "==", "athlete")
    .limit(SWEEP_PAGE_SIZE);

  let cursor: QueryDocumentSnapshot | undefined;
  let scanned = 0;
  let changed = 0;

  for (;;) {
    const page = cursor ? base.startAfter(cursor) : base;
    const snap = await page.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      scanned++;
      try {
        const r = await syncAthletePaywallEnforced(
          app,
          doc.id,
          doc.data(),
          enabled,
        );
        if (r.changed) changed++;
        // A proposito NO se loguea por alumno, a diferencia del barrido de PF.
        // Mismo motivo que la paginacion: los PF son POCOS, los alumnos no, y
        // la PRIMERA corrida cambia a todos — seria una linea de log por cada
        // usuario de la base. Los cambios individuales ya los loguean los dos
        // triggers, que son los que corren en regimen.
      } catch (err) {
        // Un alumno con datos raros no puede frenar el barrido de los demas.
        logger.error("sweepAthletePaywall: error en un alumno", {
          uid: doc.id,
          err,
        });
      }
    }

    if (snap.size < SWEEP_PAGE_SIZE) break;
    cursor = snap.docs[snap.docs.length - 1];
  }

  return { scanned, changed };
}

export const sweepAthletePaywall = onSchedule(
  {
    // 04:30 ART: media hora despues del barrido de entitlements del PF, que
    // escribe `weightedLoad` en docs de `users`. Separarlos no es correctitud
    // —la guarda de entrada ignora ese campo— sino poder leer los logs de cada
    // barrido sin que se pisen.
    schedule: "30 4 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const r = await sweepAthletePaywallHandler(ensureApp());
    logger.info("sweepAthletePaywall: corrida diaria", r);
  },
);
