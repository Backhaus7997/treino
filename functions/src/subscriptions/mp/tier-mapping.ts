/**
 * tier-mapping.ts — como recuperamos DE QUE PLAN es una suscripcion de MP.
 *
 * ── El problema que este archivo existe para resolver ──
 *
 * MP no nos dice de que plan de TREINO es una suscripcion. El checkout va
 * contra un PLAN que creamos nosotros (ver `client.ts` para por que planes y no
 * `/preapproval` directo), y el plan es lo unico cuyo id conocemos en el
 * momento de abrirlo — de la suscripcion no sabemos nada hasta que alguien
 * paga. Sin el tier no hay limite que escribir: `subscription` necesita los dos.
 *
 * ── Las dos fuentes, en orden ──
 *
 * 1. **`mp_plans/{preapprovalPlanId}`**, que escribimos al crear el plan. Es la
 *    fuente primaria y es un lookup directo por id de documento: sin query, sin
 *    indice, sin collection group.
 *
 * 2. **El MONTO**, como red de seguridad. Los seis precios de `tier-config.ts`
 *    son distintos entre si, asi que el monto identifica univocamente el par
 *    (tier, ciclo). Existe porque hay una ventana real donde la fuente 1 falta:
 *    MP crea el plan y nuestra escritura del mapeo falla despues. Sin esta red,
 *    ese PF paga y no recibe nada, y el unico arreglo es a mano.
 *
 * La 2 NO reemplaza a la 1: si manana suben los precios, un plan viejo de
 * $12.000 deja de matchear. Por eso el fallback logea WARN — es un parche que
 * grita, no un camino normal.
 *
 * ── Lo que NO se hace, y es deliberado ──
 *
 * No se crean los planes a mano en el panel de MP. Eso pondria la tabla de
 * precios en DOS lugares (el panel y `tier-config.ts`) y el dia que se
 * desincronicen le cobramos a alguien un precio que nuestro sistema no conoce.
 * Los planes se crean por API, con el monto que dice el servidor.
 */

import { App } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { athleteAmountFor } from "../athlete-plan-config";
import {
  SubscriptionCycle,
  SubscriptionTier,
  TIER_PRICES_ARS,
} from "../tier-config";

/**
 * Coleccion del mapeo. Un doc por PLAN de MP, id = el preapprovalPlanId.
 *
 * Se keyea por plan y no por suscripcion porque el plan es lo que creamos
 * NOSOTROS: sabemos su id en el momento de abrirlo, y de la suscripcion no
 * sabemos nada hasta que alguien paga. Ver el encabezado de `client.ts`.
 */
export const MP_PLANS_COLLECTION = "mp_plans";

/**
 * La coleccion del flujo viejo, sin plan asociado. Ya no se escribe.
 *
 * La constante se conserva porque `firestore.rules` la cierra explicitamente y
 * hay documentos de las pruebas manuales: borrar el nombre de acá dejaria esa
 * regla hablando de algo que el codigo ya no menciona, y en seis meses nadie
 * sabria si se puede sacar.
 */
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

/**
 * Cual de los DOS productos de TREINO se cobro con este plan de Mercado Pago.
 *
 * `mp_plans` es una sola coleccion para los dos, y sin este campo no hay forma
 * de distinguirlos: los documentos tienen la misma forma y estan keyeados por
 * el id que devuelve MP. Antes de que existiera el alumno eso no importaba
 * porque todo plan era de un PF; hoy importa, y el modo de falla es feo —
 * `reconcile-my-checkout` consulta `mp_plans where uid == uid` SIN filtro de
 * tipo, asi que un plan de alumno pasado por el escritor del PF le escribiria
 * al alumno un `subscription` de entrenador.
 */
export type ProductoMp = "trainer" | "athlete";

/**
 * Lo que sabemos de un plan de MP: de quien es, que producto cobra, y cada
 * cuanto.
 *
 * Es una union discriminada y no un objeto con `tier` opcional a proposito: el
 * alumno NO TIENE tier —un solo plan, dos ciclos— y un `tier?: SubscriptionTier`
 * dejaria que alguien lo leyera sin preguntar por el producto y se llevara un
 * `undefined` hasta el lugar equivocado. Con la union, TypeScript obliga a
 * decidir en cada lectura.
 */
export type PreapprovalMapping =
  | {
      producto: "trainer";
      uid: string;
      tier: SubscriptionTier;
      cycle: SubscriptionCycle;
    }
  | {
      producto: "athlete";
      uid: string;
      cycle: SubscriptionCycle;
    };

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
 *
 * ── Por que el indice cubre los DOS productos ──
 *
 * Porque la colision que importa es entre productos, no dentro de uno. El
 * precio del alumno vive en su propio archivo (`athlete-plan-config.ts`, ver
 * el porque alla), pero si quedara fuera de ESTE indice aparecerian dos fallas
 * nuevas: un precio de alumno igual a uno del PF le acreditaria a un alumno un
 * tier de entrenador —exactamente la catastrofe que el throw existe para
 * impedir—, y un plan de alumno que perdiera su documento en `mp_plans` no
 * tendria fallback y el pago no destrabaria nada.
 */
const BY_AMOUNT: ReadonlyMap<number, PreapprovalMapping> = (() => {
  const m = new Map<number, PreapprovalMapping>();
  const choque = (amount: number, previo: PreapprovalMapping, quien: string) =>
    new Error(
      "mp/tier-mapping: dos planes comparten el monto " +
        `${amount} (${describirPlan(previo)} y ${quien}). ` +
        "El monto dejo de identificar el plan — revisar TIER_PRICES_ARS " +
        "y ATHLETE_PRICE_MONTHLY_ARS.",
    );

  for (const tier of PAID_TIERS) {
    for (const cycle of CYCLES) {
      const amount = amountFor(tier, cycle);
      if (amount === null) continue;
      const previo = m.get(amount);
      if (previo) throw choque(amount, previo, `${tier}/${cycle}`);
      m.set(amount, { producto: "trainer", uid: "", tier, cycle });
    }
  }

  for (const cycle of CYCLES) {
    const amount = athleteAmountFor(cycle);
    const previo = m.get(amount);
    if (previo) throw choque(amount, previo, `alumno/${cycle}`);
    m.set(amount, { producto: "athlete", uid: "", cycle });
  }

  return m;
})();

/** Como se nombra un plan en un mensaje de error o en un log. */
function describirPlan(m: PreapprovalMapping): string {
  return m.producto === "trainer"
    ? `${m.tier}/${m.cycle}`
    : `alumno/${m.cycle}`;
}

/**
 * Deriva el par (tier, ciclo) desde el monto cobrado. `null` si ningun plan
 * vale eso.
 *
 * Es la red de seguridad, no el camino normal — ver el encabezado. Devuelve
 * `null` y no un tier por defecto: adivinar un plan a partir de un monto que no
 * reconocemos seria regalar entitlement.
 */
export function tierFromAmount(amount: unknown): PreapprovalMapping | null {
  if (typeof amount !== "number" || !Number.isFinite(amount)) return null;
  return BY_AMOUNT.get(amount) ?? null;
}

/**
 * Guarda el mapeo preapproval → (PF, plan). Se llama INMEDIATAMENTE despues de
 * que MP devuelve el id.
 *
 * `set` sin merge: el documento es inmutable por diseño. Un cambio de plan crea
 * un preapproval NUEVO en MP, con su propio id — nunca se reescribe el viejo,
 * asi que el historial de que compro cada PF queda entero.
 *
 * El `producto` viaja adentro del mapping y por eso se escribe solo. Este es el
 * unico escritor de `mp_plans`, asi que todo documento nuevo lo tiene; los
 * viejos no, y de eso se ocupa el default de [lookupPlan].
 */
export async function recordPlan(
  app: App,
  planId: string,
  mapping: PreapprovalMapping,
): Promise<void> {
  await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .set({
      ...mapping,
      createdAt: FieldValue.serverTimestamp(),
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
export async function lookupPlan(
  app: App,
  planId: string,
  summarizedAmount?: unknown,
): Promise<PreapprovalMapping | null> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .get();

  const data = snap.data();
  if (snap.exists && data) {
    const tier = data.tier;
    const cycle = data.cycle;
    const uid = data.uid;

    // ⚠️ DEFAULT A `trainer` CUANDO EL CAMPO FALTA, y no es una comodidad.
    //
    // `producto` se agrego el 2026-09-17. Todo documento de `mp_plans` escrito
    // antes —o sea TODOS los planes de PF que hay en produccion— no lo tiene.
    // Sin este default, el primer deploy que incluya este codigo deja ilegible
    // el mapeo de cada PF que ya paga: `lookupPlan` cae al fallback por monto,
    // que loguea un warn por cada reconciliacion, y si el monto tampoco
    // matchea devuelve null y el pago deja de acreditar.
    //
    // El default es seguro en la direccion que importa: un plan de alumno
    // SIEMPRE se escribe con `producto` explicito (ver `recordPlan`), asi que
    // un documento sin el campo solo puede ser viejo, y viejo solo puede ser
    // de un PF.
    const producto: ProductoMp = data.producto === "athlete" ? "athlete" : "trainer";

    // Se valida aunque lo hayamos escrito nosotros: es un documento de
    // Firestore, y "lo escribimos nosotros" no es una garantia de runtime. Es
    // la misma leccion que documenta `subscription-state.ts`.
    const uidOk = typeof uid === "string" && uid !== "";
    const cycleOk =
      typeof cycle === "string" && (CYCLES as readonly string[]).includes(cycle);

    if (uidOk && cycleOk && producto === "athlete") {
      return { producto, uid, cycle: cycle as SubscriptionCycle };
    }

    if (
      uidOk && cycleOk &&
      typeof tier === "string" && (PAID_TIERS as readonly string[]).includes(tier)
    ) {
      return {
        producto: "trainer",
        uid,
        tier: tier as SubscriptionTier,
        cycle: cycle as SubscriptionCycle,
      };
    }

    logger.warn("mp/tier-mapping: documento de mapeo ilegible — se usa el monto", {
      planId,
      producto,
      tier,
      cycle,
    });
  }

  const porMonto = tierFromAmount(summarizedAmount);
  if (!porMonto) return null;

  logger.warn(
    "mp/tier-mapping: sin documento de mapeo — plan derivado del monto",
    { planId, amount: summarizedAmount, plan: describirPlan(porMonto) },
  );
  return porMonto;
}
