/**
 * cancel-my-subscription.ts — dar de baja la suscripcion propia.
 *
 * Sirve a los DOS productos: al entrenador y al alumno. El mecanismo no conoce
 * el producto —es `mp_plans where uid ==` mas `cancelPreapproval`— y quien
 * escribe el derecho sigue siendo `reconcile.ts`, que ya sabe distinguirlos.
 *
 * ── Por que esto no existia, y por que es un problema ──
 *
 * **Hasta hoy no habia ningun control de baja en todo el repo.** Lo documenta
 * `pricing_screen.dart:87-96`: el pie legal llego a prometer «podés cancelar
 * cuando quieras desde Facturación» y era FALSO en las dos superficies. Se
 * recorto el texto en vez de construir el control.
 *
 * Y `docs/legal/terminos-suscripcion.md` §7 sigue prometiendo, publicado, que
 * «pasado el plazo de arrepentimiento podés dar de baja cuando quieras, **en
 * línea, sin llamar ni escribir a nadie**». La Resolucion 424/2020 obliga a que se pueda dar de
 * baja por el mismo medio por el que se contrato. El PF contrata en la web y
 * hoy no puede darse de baja en la web.
 *
 * O sea que esto no es scope del checkout del alumno: es una no-conformidad
 * vigente del producto que YA factura.
 *
 * ── ⚠️ Tres cosas que hay que saber antes de tocar este archivo ──
 *
 * **1. Cancelar es TERMINAL en Mercado Pago.** Un preapproval cancelado no se
 * reactiva: para volver atras hay que crear uno nuevo, con otro id (ver el
 * dartdoc de `cancelPreapproval` en `client.ts`). Un disparo equivocado no
 * tiene vuelta atras, y por eso el callable no acepta ningun parametro que
 * pueda apuntar a la suscripcion de otro.
 *
 * **2. Esto NO es el boton de arrepentimiento.** Los 10 dias con reembolso
 * (`terminos-suscripcion.md` §6) van por `gettreino.com/es/arrepentimiento`,
 * **sin login** —la norma prohibe expresamente pedir registracion previa— y el
 * reembolso se opera a mano. El vocabulario de respuesta de este callable no
 * puede contener la palabra «reembolso»: acá no se devuelve plata.
 *
 * **3. No escribe el derecho.** Le pide la baja a MP y despues llama a
 * `reconcileSubscription`, que sigue siendo el unico escritor. Asi se hereda
 * gratis la cascada de `resolverFinDePeriodo` —incluido el paso que deriva la
 * fecha del alta, que es el caso «me suscribi a la mañana y cancelo a la
 * tarde»— y la garantia de que el usuario conserva el acceso hasta el fin del
 * periodo que ya pago.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { MpClient, createMpClient } from "./client";
import { MP_PLANS_COLLECTION } from "./tier-mapping";
import {
  ReconcileResult,
  puedeSeguirCobrando,
  reconcileSubscription,
  sigueViva,
} from "./reconcile";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/**
 * Cuanto hay que esperar entre dos bajas del mismo usuario.
 *
 * Mismo motivo que el de `reconcileMyCheckout`: un F5 en un SPA son N requests
 * con nuestro token, y MP contesta 429. Acá pesa menos —nadie se da de baja dos
 * veces— pero el costo de ponerlo es cero y el de no ponerlo es que un bucle de
 * reintentos del cliente nos queme la cuota.
 */
export const CANCEL_COOLDOWN_MS = 10_000;

export type EstadoDeBaja =
  /** Se le pidio la baja a MP y MP la acepto. */
  | "dada-de-baja"
  /** No habia ninguna suscripcion que dar de baja. No es un error. */
  | "sin-suscripcion"
  /** MP no contesto. NO se escribio nada: se puede reintentar. */
  | "no-disponible";

export interface CancelMySubscriptionResult {
  estado: EstadoDeBaja;
  /**
   * Hasta cuando conserva el acceso, en ISO 8601. Es lo que la pantalla tiene
   * que decirle al usuario, y lo que hace verdadera la promesa del §7 de los
   * terminos.
   *
   * Sale del resultado del reconciliador, no de un campo nuevo: asi no hay nada
   * que persistir en `users/{uid}` y `firestore.rules` no cambia.
   *
   * Ausente cuando no se pudo determinar — que es posible: un plan recien
   * creado cuyo `auto_recurring` MP todavia no completo no tiene de donde
   * derivarla. La pantalla tiene que poder decir «se dio de baja» sin la fecha.
   */
  accesoHastaIso?: string;
  /** Cuantas suscripciones se cancelaron en MP. Normalmente 1. */
  canceladas?: number;
  /** `true` cuando se corto por el cooldown y no se llamo a MP. */
  enfriando?: boolean;
}

export interface CancelMySubscriptionDeps {
  mpClient: MpClient;
  /** Reloj inyectable: el cooldown se testea sin esperar diez segundos. */
  nowMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** Los planes del usuario que todavia pueden estar cobrando. */
async function planesQueCobran(
  app: App,
  uid: string,
): Promise<{ planId: string }[]> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  // El filtro va EN MEMORIA y no en la query, por el mismo motivo que lo
  // documenta `tier-mapping.ts`: un segundo `where` convierte esto en una
  // consulta compuesta y exige desplegar un indice. Con uno o dos documentos
  // por usuario, filtrar despues no cuesta nada.
  //
  // `puedeSeguirCobrando` y no `terminal !== true` pelado: el `terminal` por
  // ABANDONO puede tener una suscripcion viva detras, porque un `init_point`
  // no vence. Ese plan hay que cancelarlo igual.
  return snap.docs
    .filter((d) => puedeSeguirCobrando(d.data()))
    .map((d) => ({ planId: d.id }));
}

/**
 * El handler. Recibe el `uid` YA extraido del token. **No hay body**, igual que
 * en `reconcileMyCheckout`, y acá el motivo es mas fuerte: si un `planId`
 * viajara en el request, cualquiera podria darle de baja la suscripcion a otro,
 * y en MP eso no se deshace.
 */
export async function runCancelMySubscription(
  app: App,
  uid: string,
  deps: CancelMySubscriptionDeps,
): Promise<CancelMySubscriptionResult> {
  const db = getFirestore(app);
  const cancelRef = db.collection("mp_cancelaciones").doc(uid);

  // ── El cooldown, ANTES de cualquier llamada a MP ──
  const ultima = (await cancelRef.get()).data()?.lastCancelMs;
  if (typeof ultima === "number" && deps.nowMs - ultima < CANCEL_COOLDOWN_MS) {
    return { estado: "sin-suscripcion", enfriando: true };
  }

  const planes = await planesQueCobran(app, uid);
  if (planes.length === 0) {
    // Nunca contrato, o ya se dio de baja. No es un error y no se toca el
    // cooldown: no hubo ninguna llamada a MP que valga la pena frenar.
    return { estado: "sin-suscripcion" };
  }

  // Se marca ANTES de salir a MP, no despues: si se marcara al final, una
  // funcion que tarda o revienta dejaria la puerta abierta para el proximo
  // click — y el caso en el que mas se clickea es justo ese.
  await cancelRef.set({ lastCancelMs: deps.nowMs }, { merge: true });

  let canceladas = 0;
  // SECUENCIAL, por el mismo motivo que el barrido: en paralelo son N requests
  // simultaneos a MP, que contesta 429. Son uno o dos planes.
  for (const { planId } of planes) {
    let subs;
    try {
      subs = await deps.mpClient.searchPreapprovalsByPlan(planId);
    } catch (e) {
      logger.error("mp/cancel: no se pudo consultar el plan en MP", {
        uid,
        planId,
        error: String(e),
      });
      // Se corta ACA y no se sigue con los otros planes: dejar unos cancelados
      // y otros no es el peor estado posible — el usuario cree que se dio de
      // baja y le sigue llegando un cobro. Que reintente entero.
      return { estado: "no-disponible" };
    }

    for (const sub of subs) {
      if (!sigueViva(sub.status)) continue;
      const id = sub.id;
      if (typeof id !== "string" || id === "") continue;
      try {
        await deps.mpClient.cancelPreapproval(id);
        canceladas += 1;
      } catch (e) {
        logger.error("mp/cancel: MP rechazo la baja", {
          uid,
          planId,
          preapprovalId: id,
          error: String(e),
        });
        return { estado: "no-disponible" };
      }
    }
  }

  if (canceladas === 0) {
    // Habia planes pero ninguna suscripcion viva detras. Pasa cuando el usuario
    // abrio un checkout y nunca lo completo: el plan existe, la suscripcion no.
    logger.info("mp/cancel: planes sin suscripcion viva", { uid, planes: planes.length });
    return { estado: "sin-suscripcion", canceladas: 0 };
  }

  // ── El derecho lo escribe el reconciliador, no este archivo ──
  //
  // Asi se hereda la cascada entera de `resolverFinDePeriodo` sin duplicarla,
  // incluido el paso que deriva la fecha del alta — el caso «me suscribi a la
  // mañana y cancelo a la tarde», que si no daria una baja sin fecha de fin.
  const resultados: ReconcileResult[] = [];
  for (const { planId } of planes) {
    resultados.push(await reconcileSubscription(app, planId, deps));
  }

  logger.info("mp/cancel: baja confirmada", {
    uid,
    canceladas,
    outcomes: resultados.map((r) => r.outcome),
  });

  return {
    estado: "dada-de-baja",
    canceladas,
    ...(accesoHastaDe(resultados) ?? {}),
  };
}

/**
 * La fecha hasta la que conserva el acceso, sacada del reconciliador.
 *
 * Se lee del documento de plan que el reconciliador acaba de escribir, y no de
 * un campo nuevo: ver el dartdoc de [CancelMySubscriptionResult.accesoHastaIso].
 * Devuelve `undefined` —y no una fecha inventada— cuando no se pudo determinar.
 */
function accesoHastaDe(
  resultados: ReconcileResult[],
): { accesoHastaIso: string } | undefined {
  for (const r of resultados) {
    const ms = r.accesoHastaMs;
    if (typeof ms === "number" && Number.isFinite(ms)) {
      return { accesoHastaIso: new Date(ms).toISOString() };
    }
  }
  return undefined;
}

export const cancelMySubscription = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo que `reconcileMyCheckout`: lo
  // llaman el Coach Hub web y la landing, que no activan App Check. La cerradura
  // es que NO HAY BODY — la entrada es el uid del token y nada mas.
  { region: "southamerica-east1", secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<CancelMySubscriptionResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    return runCancelMySubscription(ensureApp(), request.auth.uid, {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
      nowMs: Date.now(),
    });
  },
);
