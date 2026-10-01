/**
 * diferir-primer-cobro.ts: que volver a suscribirse no cobre dos veces el mismo
 * periodo.
 *
 * ── El problema ──
 *
 * Un PF que se da de baja conserva el plan pago hasta `currentPeriodEnd`: es lo
 * que promete la baja y lo que implementa la rama `cancelled` de
 * `effectiveWeightLimit`. Si antes de esa fecha vuelve a suscribirse al MISMO
 * plan, el checkout nuevo cobra en el acto y paga dos veces los mismos dias. MP
 * no lo evita: cada preapproval es independiente y no sabe nada del anterior.
 *
 * ── El arreglo ──
 *
 * El plan nuevo se crea con una prueba de N dias (`auto_recurring.free_trial`),
 * donde N es lo que le queda al periodo pago. MP cobra por primera vez cuando la
 * prueba termina, o sea cuando lo que ya estaba pago vence.
 *
 * Este archivo es PURO a proposito: no toca Firestore ni MP. Las dos lecturas que
 * necesita entran por parametro (`leerPlanes`, `leerSuscripciones`), asi que se
 * testea con fakes de una linea y ningun test puede pasar porque un mock de
 * Firestore acepto de mas.
 *
 * ── Por que el pago se comprueba CONTRA MP y no contra nuestra fecha ──
 *
 * `currentPeriodEnd` dice hasta cuando le DURA el plan al PF, no que lo haya
 * PAGADO. Una fecha futura tambien la pueden tener un PF sembrado a mano con el
 * Admin SDK (no hay pago que descontar) o una suscripcion que se cancelo antes de
 * cobrar nada. Diferir contra una fecha asi es regalar dias: por eso se exige ver
 * en MP un cobro real, y el diferimiento nunca pasa de lo que ese cobro cubre.
 *
 * ── La pregunta de fondo: fallar para que lado ──
 *
 * Todo lo dudoso en este archivo termina en NO diferir, o sea en el
 * comportamiento de antes (cobrar en el acto). Con una sola excepcion, que es
 * deliberada: si no podemos LEER lo que necesitamos para decidir, se tira. Seguir
 * adelante sin saber si el PF tiene dias pagos es exactamente el doble cobro que
 * esto viene a cerrar, y el PF puede reintentar.
 */

import { logger } from "firebase-functions";

import { toSubscriptionState } from "../subscription-state";
import { SubscriptionTier } from "../tier-config";
import { MpPreapproval } from "./client";

/** Un dia en ms. La prueba que le mandamos a MP se cuenta en dias. */
export const DIA_MS = 24 * 60 * 60 * 1000;

/**
 * Con menos que esto de periodo restante NO se difiere.
 *
 * El solapamiento que se evita seria menor que un dia, y la prueba mas corta que
 * podemos mandar es de un dia: diferir por horas le regalaria al PF casi un dia
 * entero para ahorrarle unas pocas horas, y le suma un caso borde a un cobro.
 */
export const MIN_DIFERIMIENTO_MS = DIA_MS;

/**
 * Cuantos planes del PF se le consultan a MP para comprobar un pago.
 *
 * Cada uno es una llamada en el camino del boton "ELEGIR PLAN", asi que el peor
 * caso tiene que estar acotado. Tres alcanzan para lo real: el plan que pago, y
 * un par de checkouts posteriores que el PF abrio y no completo.
 */
export const MAX_PLANES_A_REVISAR = 3;

/** Un plan de `mp_plans` tal como sale de Firestore, sin interpretar. */
export interface PlanDeLaCuenta {
  id: string;
  data: Record<string, unknown>;
}

/**
 * `unknown` → ms si tiene forma de Timestamp, si no 0.
 *
 * El 0 manda al plan al final del orden (el mas viejo) en vez de tirar: un plan
 * sin fecha legible puede seguir siendo el que pago, y descartarlo seria perder
 * la evidencia. Solo pierde frente a los que tienen fecha.
 */
function creadoEnMs(createdAt: unknown): number {
  const t = createdAt as { toMillis?: unknown } | null | undefined;
  return t != null && typeof t.toMillis === "function"
    ? (t.toMillis as () => number)()
    : 0;
}

/**
 * Los planes de este PF que vale la pena consultarle a MP para comprobar un
 * pago: los de PF (no los de alumno) del MISMO tier que pide, del mas nuevo al
 * mas viejo, y no mas de [MAX_PLANES_A_REVISAR].
 *
 * El filtro por tier no es prolijidad. El diferimiento solo aplica a volver al
 * mismo plan, asi que un pago de otro tier no prueba nada sobre este.
 *
 * `producto !== "athlete"` y no `=== "trainer"`: los planes de PF anteriores al
 * 2026-09-17 no tienen el campo (ver el default de `lookupPlan`), y son
 * justamente los que mas pueden haber pagado.
 *
 * El orden se resuelve ACA, en memoria, y no en la query: un `orderBy` sobre un
 * campo distinto del `where` exigiria un indice compuesto. Con un puñado de
 * planes por PF ordenar despues no cuesta nada.
 */
export function planesARevisar(
  planes: PlanDeLaCuenta[],
  tier: SubscriptionTier,
): string[] {
  return planes
    .filter(({ data }) => data.producto !== "athlete" && data.tier === tier)
    .map(({ id, data }) => ({ id, creado: creadoEnMs(data.createdAt) }))
    .sort((a, b) => b.creado - a.creado)
    .slice(0, MAX_PLANES_A_REVISAR)
    .map((p) => p.id);
}

/**
 * Hasta cuando esta PAGO el periodo de una suscripcion, segun lo que MP dice que
 * cobro. `null` si no hay evidencia de un cobro real.
 *
 * Es la fecha del ULTIMO cobro exitoso mas un periodo de `auto_recurring`. Se
 * exigen las tres cosas juntas (que haya cobrado, cuando fue el ultimo, y un
 * periodo que entendemos) porque con una sola que falte la cuenta seria
 * inventada, y una fecha inventada es un dia regalado o un cobro adelantado.
 *
 * Los campos `charged_quantity` y `last_charged_date` salen de `summarized`, tal
 * como los define el SDK oficial (`sdk-nodejs/src/clients/preApproval/
 * commonTypes.ts`, `SummarizedResponse`, consultado el 2026-10-01).
 *
 * OJO, lo que NO esta medido: ningun payload real del repo trae
 * `last_charged_date`, y ningun codigo lo lee todavia. El reconciliador y
 * `arrepentimiento-por-mail.ts` ya leen `summarized` de los resultados de
 * `searchPreapprovalsByPlan` sin volver a pedir por id, pero si MP omitiera ese
 * campo de la busqueda esta funcion daria `null` y el PF seguiria cobrando en el
 * acto: el comportamiento de antes, nunca uno peor.
 *
 * La aritmetica de meses es la de `finDePeriodoDesdeAltaMs` (reconcile.ts), y
 * esta copiada y no importada a proposito: `reconcile.ts` importa este archivo, y
 * un import en el otro sentido seria circular.
 */
export function pagadoHastaDe(sub: MpPreapproval): number | null {
  const resumen = sub.summarized;
  if (resumen === null || typeof resumen !== "object") return null;
  const { charged_quantity: cobros, last_charged_date: ultimo } = resumen as {
    charged_quantity?: unknown;
    last_charged_date?: unknown;
  };

  if (typeof cobros !== "number" || !Number.isFinite(cobros) || cobros < 1) {
    return null;
  }
  if (typeof ultimo !== "string") return null;
  const ultimoMs = Date.parse(ultimo);
  if (!Number.isFinite(ultimoMs)) return null;

  const ar = sub.auto_recurring;
  if (ar === null || typeof ar !== "object") return null;
  const { frequency: n, frequency_type: tipo } = ar as {
    frequency?: unknown;
    frequency_type?: unknown;
  };
  // Mismos limites que `finDePeriodoDesdeAltaMs`: un periodo que no entendemos
  // no se suma.
  if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > 24) {
    return null;
  }
  if (tipo !== "months") return null;

  // `setUTCMonth` normaliza el desborde de mes solo (31 de enero + 1 mes cae en
  // marzo), que es como cuenta el calendario.
  const d = new Date(ultimoMs);
  d.setUTCMonth(d.getUTCMonth() + n);
  return d.getTime();
}

/**
 * Cuantos dias de prueba hay que mandarle a MP para que el primer cobro caiga en
 * [diferidoHastaMs] o apenas despues, NUNCA antes.
 *
 * `ceil` y no `round`: redondear hacia abajo adelantaria el cobro y el PF
 * pagaria antes de que venza lo que ya pago, que es el bug entero. El costo de
 * redondear hacia arriba es que el primer cobro cae hasta un dia despues, que
 * es el lado barato de equivocarse.
 *
 * Vive aca y la llama `abrir-checkout.ts`: los dias salen de UN solo lugar, a
 * partir de `diferidoHastaMs` y del reloj del request.
 */
export function diasDePrueba(diferidoHastaMs: number, nowMs: number): number {
  return Math.ceil((diferidoHastaMs - nowMs) / DIA_MS);
}

/** Por que NO se difiere. Va al log para poder explicar un cobro en el acto. */
export type MotivoSinDiferir =
  | "sin-suscripcion"
  | "estado-degradado"
  | "no-esta-cancelada"
  | "otro-tier"
  | "sin-fecha-de-fin"
  | "queda-menos-de-un-dia"
  | "sin-pago-comprobado"
  | "pago-vence-pronto";

export type Diferimiento =
  | { diferir: false; motivo: MotivoSinDiferir }
  | {
      diferir: true;
      /** Hasta cuando esta pago el periodo, en ms. El primer cobro cae ahi. */
      diferidoHastaMs: number;
    };

export interface DecidirDiferimientoInput {
  uid: string;
  /** El tier que el PF esta por comprar. */
  tier: SubscriptionTier;
  /** `users/{uid}`, tal como salio de Firestore. */
  userData: Record<string, unknown> | undefined;
  nowMs: number;
  /**
   * TODOS los planes de MP de esta cuenta (`mp_plans where uid == uid`).
   *
   * Es una funcion y no un arreglo para no pagar la query a quien no califica
   * por su estado, que es casi todo checkout: solo se llama cuando el PF esta
   * cancelado, en el mismo tier, con mas de un dia por delante.
   */
  leerPlanes: () => Promise<PlanDeLaCuenta[]>;
  /** Las suscripciones de MP detras de un plan (`searchPreapprovalsByPlan`). */
  leerSuscripciones: (planId: string) => Promise<MpPreapproval[]>;
}

/**
 * Decide si el checkout que el PF esta por abrir tiene que diferir su primer
 * cobro, y hasta cuando.
 *
 * Se difiere SOLO si todo esto es cierto:
 *
 *   1. `subscription` se lee sin degradacion, y esta `cancelled`.
 *   2. Es del MISMO tier que el PF pide (cualquier ciclo: pasar de mensual a
 *      anual dentro del mismo plan tambien paga dos veces los dias que quedan).
 *   3. Le queda al menos [MIN_DIFERIMIENTO_MS] de periodo.
 *   4. MP muestra un cobro real que lo respalda (ver [pagadoHastaDe]).
 *
 * El resultado es el MENOR entre nuestra fecha de fin y lo que cubre el cobro de
 * MP. Cada fuente puede estar equivocada hacia adelante (la nuestra por un tope
 * que no se aplico, la de MP porque el cobro fue hace meses y la suscripcion se
 * reactivo): quedarse con la menor es no regalarle al PF mas de lo que las dos
 * aceptan.
 *
 * De los planes que se revisan se toma el primero (el mas nuevo) que muestre un
 * cobro. Dentro de ese plan, el pago mas lejano.
 *
 * Tira si no puede LEER los planes o las suscripciones: ver el encabezado. Quien
 * llama lo traduce a un error que el PF pueda reintentar.
 */
export async function decidirDiferimiento(
  i: DecidirDiferimientoInput,
): Promise<Diferimiento> {
  const { uid, tier, nowMs } = i;

  const sinDiferir = (
    motivo: MotivoSinDiferir,
    extra: Record<string, unknown> = {},
  ): Diferimiento => {
    logger.info("mp/diferir-primer-cobro: se cobra en el acto", {
      uid,
      tier,
      motivo,
      ...extra,
    });
    return { diferir: false, motivo };
  };

  const { state, degraded } = toSubscriptionState(i.userData, uid);
  if (degraded) return sinDiferir("estado-degradado");
  if (state === null) return sinDiferir("sin-suscripcion");
  if (state.status !== "cancelled") {
    return sinDiferir("no-esta-cancelada", { status: state.status });
  }
  if (state.tier !== tier) return sinDiferir("otro-tier", { tierActual: state.tier });

  const finMs = state.currentPeriodEndMs;
  if (finMs == null) return sinDiferir("sin-fecha-de-fin");
  if (finMs - nowMs < MIN_DIFERIMIENTO_MS) return sinDiferir("queda-menos-de-un-dia");

  // Desde aca se sale a la red, y un fallo TIRA (ver el encabezado).
  const planes = planesARevisar(await i.leerPlanes(), tier);

  let pagadoHasta: number | null = null;
  let planConPago: string | null = null;
  for (const planId of planes) {
    const fechas = (await i.leerSuscripciones(planId))
      .map(pagadoHastaDe)
      .filter((f): f is number => f !== null);
    if (fechas.length > 0) {
      pagadoHasta = Math.max(...fechas);
      planConPago = planId;
      break;
    }
  }
  if (pagadoHasta === null) {
    return sinDiferir("sin-pago-comprobado", { planesRevisados: planes.length });
  }

  const diferidoHastaMs = Math.min(finMs, pagadoHasta);
  if (diferidoHastaMs - nowMs < MIN_DIFERIMIENTO_MS) {
    return sinDiferir("pago-vence-pronto", {
      finDePeriodoIso: new Date(finMs).toISOString(),
      pagadoHastaIso: new Date(pagadoHasta).toISOString(),
    });
  }

  logger.info("mp/diferir-primer-cobro: se difiere el primer cobro", {
    uid,
    tier,
    planConPago,
    diferidoHastaIso: new Date(diferidoHastaMs).toISOString(),
    diasDePrueba: diasDePrueba(diferidoHastaMs, nowMs),
  });
  return { diferir: true, diferidoHastaMs };
}
