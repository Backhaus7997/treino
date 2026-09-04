/**
 * tier-mapping.ts — como recuperamos DE QUE PLAN es una suscripcion de MP.
 *
 * ── El problema que este archivo existe para resolver ──
 *
 * **Mercado Pago no devuelve `preapproval_plan_id` en la respuesta de un
 * preapproval.** Solo lo acepta en el request. Verificado contra los tipos del
 * SDK oficial (`sdk-nodejs/src/clients/preApproval/commonTypes.ts`, 2026-09-02),
 * porque la pagina de referencia de ese endpoint esta caida.
 *
 * O sea: cuando llega un webhook con un id, o cuando el reconciliador barre,
 * podemos preguntarle a MP el ESTADO de la suscripcion pero no de que plan es.
 * Y sin el tier no hay limite que escribir — `subscription` necesita los dos.
 *
 * ── Las dos fuentes, en orden ──
 *
 * 1. **`mp_preapprovals/{preapprovalId}`**, que escribimos nosotros al crear.
 *    Es la fuente primaria y es un lookup directo por id de documento: sin
 *    query, sin indice, sin collection group.
 *
 * 2. **El MONTO**, como red de seguridad. Los seis precios de `tier-config.ts`
 *    son distintos entre si, asi que el monto identifica univocamente el par
 *    (tier, ciclo). Existe porque hay una ventana real donde la fuente 1 falta:
 *    MP crea la suscripcion y nuestra escritura del mapeo falla despues. Sin
 *    esta red, ese PF paga y no recibe nada, y el unico arreglo es a mano.
 *
 * La 2 NO reemplaza a la 1: si manana suben los precios, una suscripcion vieja
 * de $12.000 deja de matchear. Por eso el fallback logea WARN — es un parche
 * que grita, no un camino normal.
 *
 * ── Lo que NO se hace, y es deliberado ──
 *
 * No se usa `preapproval_plan_id` creando planes en el panel de MP. Eso pondria
 * la tabla de precios en DOS lugares (el panel y `tier-config.ts`) y el dia que
 * se desincronicen le cobramos a alguien un precio que nuestro sistema no
 * conoce. La tabla vive en un solo lado: el servidor.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import {
  SubscriptionCycle,
  SubscriptionTier,
  TIER_PRICES_ARS,
} from "../tier-config";

/** Coleccion del mapeo. Un doc por suscripcion de MP, id = el preapprovalId. */
export const MP_PREAPPROVALS_COLLECTION = "mp_preapprovals";

/** Los tiers que se pueden comprar. `free` no se cobra, no tiene preapproval. */
export const PAID_TIERS: readonly SubscriptionTier[] = [
  "plan1",
  "plan2",
  "plan3",
] as const;

export const CYCLES: readonly SubscriptionCycle[] = [
  "monthly",
  "annual",
] as const;

export interface PreapprovalMapping {
  uid: string;
  tier: SubscriptionTier;
  cycle: SubscriptionCycle;
}

/**
 * Cada cuantos MESES cobra MP para este ciclo.
 *
 * El anual son 12 meses y no `frequency_type: "years"`: "months" esta en los
 * tipos del SDK y "years" no aparece. Doce meses es lo mismo y no depende de un
 * valor que no pudimos verificar.
 */
export function frequencyMonthsFor(cycle: SubscriptionCycle): number {
  return cycle === "annual" ? 12 : 1;
}

/**
 * El monto en ARS que le corresponde a este par. SERVER-AUTHORITATIVE: es la
 * unica fuente del precio, y nunca se acepta un monto que venga del cliente.
 */
export function amountFor(
  tier: SubscriptionTier,
  cycle: SubscriptionCycle,
): number | null {
  if (tier === "free") return null;
  return TIER_PRICES_ARS[tier][cycle];
}

/**
 * El indice inverso monto → (tier, ciclo), construido al importar el modulo.
 *
 * Se construye en runtime desde `TIER_PRICES_ARS` y no se escribe a mano a
 * proposito: una tabla escrita a mano se desincroniza del precio real, que es
 * justo el fallo que este archivo tiene que evitar.
 *
 * **Y si dos precios colisionan, el modulo NO CARGA.** Es deliberado: con dos
 * pares compartiendo monto, el fallback le asignaria a alguien un tier que no
 * compro. Un throw al importar rompe el deploy y el arranque de los tests —
 * ruidoso y temprano. Devolver `null` en silencio dejaria el bug esperando a
 * que alguien pague.
 */
const BY_AMOUNT: ReadonlyMap<number, PreapprovalMapping> = (() => {
  const m = new Map<number, PreapprovalMapping>();
  for (const tier of PAID_TIERS) {
    for (const cycle of CYCLES) {
      const amount = amountFor(tier, cycle);
      if (amount === null) continue;
      const previo = m.get(amount);
      if (previo) {
        throw new Error(
          "mp/tier-mapping: dos planes comparten el monto " +
            `${amount} (${previo.tier}/${previo.cycle} y ${tier}/${cycle}). ` +
            "El monto dejo de identificar el plan — revisar TIER_PRICES_ARS.",
        );
      }
      m.set(amount, { uid: "", tier, cycle });
    }
  }
  return m;
})();

/**
 * Deriva el par (tier, ciclo) desde el monto cobrado. `null` si ningun plan
 * vale eso.
 *
 * Es la red de seguridad, no el camino normal — ver el encabezado. Devuelve
 * `null` y no un tier por defecto: adivinar un plan a partir de un monto que no
 * reconocemos seria regalar entitlement.
 */
export function tierFromAmount(
  amount: unknown,
): { tier: SubscriptionTier; cycle: SubscriptionCycle } | null {
  if (typeof amount !== "number" || !Number.isFinite(amount)) return null;
  const hit = BY_AMOUNT.get(amount);
  return hit ? { tier: hit.tier, cycle: hit.cycle } : null;
}

/**
 * Guarda el mapeo preapproval → (PF, plan). Se llama INMEDIATAMENTE despues de
 * que MP devuelve el id.
 *
 * `set` sin merge: el documento es inmutable por diseño. Un cambio de plan crea
 * un preapproval NUEVO en MP, con su propio id — nunca se reescribe el viejo,
 * asi que el historial de que compro cada PF queda entero.
 */
export async function recordPreapproval(
  app: admin.app.App,
  preapprovalId: string,
  mapping: PreapprovalMapping,
): Promise<void> {
  await app
    .firestore()
    .collection(MP_PREAPPROVALS_COLLECTION)
    .doc(preapprovalId)
    .set({
      ...mapping,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/**
 * Recupera el mapeo. Primero el documento; si falta, el monto.
 *
 * [summarizedAmount] es el `auto_recurring.transaction_amount` que vino de MP.
 * Se pasa por parametro y no se lee acá para que la funcion no dependa del
 * cliente HTTP y se pueda testear sin red.
 *
 * Cuando cae al fallback devuelve `uid: ""`: el monto sabe el PLAN pero no la
 * PERSONA. El uid en ese caso sale del `external_reference` del propio
 * preapproval, que es de donde tiene que salir — quien llame resuelve eso.
 */
export async function lookupPreapproval(
  app: admin.app.App,
  preapprovalId: string,
  summarizedAmount?: unknown,
): Promise<PreapprovalMapping | null> {
  const snap = await app
    .firestore()
    .collection(MP_PREAPPROVALS_COLLECTION)
    .doc(preapprovalId)
    .get();

  const data = snap.data();
  if (snap.exists && data) {
    const tier = data.tier;
    const cycle = data.cycle;
    const uid = data.uid;
    // Se valida aunque lo hayamos escrito nosotros: es un documento de
    // Firestore, y "lo escribimos nosotros" no es una garantia de runtime. Es
    // la misma leccion que documenta `subscription-state.ts`.
    if (
      typeof uid === "string" && uid !== "" &&
      typeof tier === "string" && (PAID_TIERS as readonly string[]).includes(tier) &&
      typeof cycle === "string" && (CYCLES as readonly string[]).includes(cycle)
    ) {
      return {
        uid,
        tier: tier as SubscriptionTier,
        cycle: cycle as SubscriptionCycle,
      };
    }
    logger.warn("mp/tier-mapping: documento de mapeo ilegible — se usa el monto", {
      preapprovalId,
      tier,
      cycle,
    });
  }

  const porMonto = tierFromAmount(summarizedAmount);
  if (!porMonto) return null;

  logger.warn(
    "mp/tier-mapping: sin documento de mapeo — plan derivado del monto",
    { preapprovalId, amount: summarizedAmount, ...porMonto },
  );
  return { uid: "", ...porMonto };
}
