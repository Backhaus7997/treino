/**
 * cascade/subscriptions.ts — dar de baja las suscripciones de Mercado Pago
 * ANTES de borrar la cuenta.
 *
 * ── Por que esto NO es un paso mas de la cascada ──
 *
 * Todos los demas pasos de `delete-account.ts` van en un try/catch que acumula
 * el error y sigue: borrar de mas es recuperable, borrar de menos se reintenta.
 * Este paso es al reves, y por eso corre ANTES de tocar nada y **corta todo si
 * falla**.
 *
 * Sin el, eliminar la cuenta de alguien con una suscripcion viva dejaba el
 * preapproval vivo en Mercado Pago: seguia cobrando, y la persona ya no podia
 * darse de baja sola —la baja por mail busca la cuenta por el correo de Auth, y
 * esa cuenta ya no existe—. Cobrarle a alguien que pidio irse, y sin ninguna
 * puerta para frenarlo, es lo peor que puede hacer esta funcion.
 *
 * Por eso, si Mercado Pago no contesta, **la cuenta no se toca**: se le dice al
 * usuario que reintente. Que no pueda borrarse un rato es un fastidio; borrarse
 * con el cobro vivo es un problema legal.
 *
 * ── Esto da de baja, NO devuelve plata ──
 *
 * Es la baja de los Terminos §7: no se cobra mas y no se reembolsa el periodo en
 * curso. El arrepentimiento (§6, 10 dias y con devolucion) es otro derecho y va
 * por su propio camino. Borrar la cuenta no lo ejerce.
 *
 * ── El marcador evita el usuario fantasma ──
 *
 * Cancelar en MP dispara un webhook `cancelled` a los pocos segundos, y el
 * barrido de las 03:00 sigue recorriendo los planes. El reconciliador escribe
 * con `set` y `merge` sobre `users/{uid}`: lo que llegue DESPUES de la cascada
 * recrearia un documento vacio de un usuario que ya no existe. Por eso los
 * planes se marcan con `cuentaEliminadaAtMs` y `reconcileSubscription` los
 * saltea (ver `CAMPO_CUENTA_ELIMINADA`).
 *
 * El marcador se pone ANTES de cancelar, y se saca si la baja no se pudo: dejarlo
 * puesto sobre una cuenta que sigue viva haria que el reconciliador dejara de
 * mirar una suscripcion que todavia cobra.
 */

import { App } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { MpClient } from "../subscriptions/mp/client";
import { runCancelMySubscription } from "../subscriptions/mp/cancel-my-subscription";
import { CAMPO_CUENTA_ELIMINADA } from "../subscriptions/mp/reconcile";
import { MP_PLANS_COLLECTION } from "../subscriptions/mp/tier-mapping";

export interface CancelarAlEliminarDeps {
  /**
   * Un constructor y no el cliente: `createMpClient` tira con el token vacio, y
   * casi ninguna cuenta tiene planes. Solo se arma cuando hay algo que cancelar.
   */
  getMpClient: () => MpClient;
  /** Reloj inyectable, igual que en `cancel-my-subscription.ts`. */
  nowMs: number;
}

/** Lo que ve el usuario si no se pudo. Reintentar es exactamente lo que hay que hacer. */
export const MENSAJE_NO_SE_PUDO_CANCELAR =
  "No pudimos cancelar tu suscripción, así que no eliminamos tu cuenta. " +
  "Probá de nuevo en unos minutos.";

/**
 * Cancela en Mercado Pago lo que la cuenta tenga vivo y marca sus planes.
 *
 * @returns cuantas suscripciones se cancelaron (0 si no tenia ninguna viva).
 * @throws HttpsError `unavailable` si no se pudo — y en ese caso NO queda ningun
 *   marcador: la cuenta sigue exactamente como estaba.
 */
export async function cancelarSuscripcionesAntesDeEliminar(
  app: App,
  uid: string,
  deps: CancelarAlEliminarDeps,
): Promise<number> {
  // TODOS los planes de la cuenta, no solo los que cobran: uno cancelado pero
  // dentro del periodo pagado no es terminal, el barrido lo sigue visitando, y
  // seria el que recree el usuario fantasma.
  const planes = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();
  if (planes.empty) return 0;

  const refs = planes.docs.map((d) => d.ref);
  await Promise.all(
    refs.map((ref) => ref.set({ [CAMPO_CUENTA_ELIMINADA]: deps.nowMs }, { merge: true })),
  );

  let resultado;
  try {
    resultado = await runCancelMySubscription(app, uid, {
      mpClient: deps.getMpClient(),
      nowMs: deps.nowMs,
    });
  } catch (error) {
    await quitarMarcador(refs, uid);
    logger.error("deleteAccount: no se pudo cancelar la suscripcion", {
      uid,
      error: String(error),
    });
    throw new HttpsError("unavailable", MENSAJE_NO_SE_PUDO_CANCELAR);
  }

  // `enfriando` cuenta como falla, y no es un detalle: la baja tiene un cooldown
  // de 10 s que se marca ANTES de salir a MP. Si un intento anterior fallo a
  // medias y el usuario toca ELIMINAR de nuevo enseguida, el cooldown contesta
  // «sin suscripcion» sin haber cancelado nada, y la cuenta se borraria con el
  // cobro vivo.
  if (resultado.estado === "no-disponible" || resultado.enfriando === true) {
    await quitarMarcador(refs, uid);
    logger.warn("deleteAccount: la baja no se confirmo — no se elimina la cuenta", {
      uid,
      estado: resultado.estado,
      enfriando: resultado.enfriando === true,
    });
    throw new HttpsError("unavailable", MENSAJE_NO_SE_PUDO_CANCELAR);
  }

  return resultado.canceladas ?? 0;
}

/**
 * Saca el marcador de los planes. Si esto mismo falla no se puede hacer mas que
 * avisar fuerte: el error que sube al usuario sigue siendo el original.
 */
async function quitarMarcador(
  refs: { set: (data: Record<string, unknown>, opts: { merge: boolean }) => Promise<unknown> }[],
  uid: string,
): Promise<void> {
  try {
    await Promise.all(
      refs.map((ref) =>
        ref.set({ [CAMPO_CUENTA_ELIMINADA]: FieldValue.delete() }, { merge: true })),
    );
  } catch (error) {
    logger.error("deleteAccount: no se pudo sacar el marcador de cuenta eliminada", {
      uid,
      error: String(error),
    });
  }
}
