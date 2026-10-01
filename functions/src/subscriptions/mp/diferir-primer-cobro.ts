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
 * Tiene dos mitades que comparten constantes y vocabulario:
 *
 *   1. AL ABRIR EL CHECKOUT (`decidirDiferimiento`): si el PF califica, y hasta
 *      cuando tiene pago el periodo.
 *   2. AL RECONCILIAR (`aplicarPruebaDiferidaAlEstado` y
 *      `aplicarPruebaDiferidaAlPeriodo`): como se lee despues un plan que nacio
 *      con prueba. Hace falta porque el link de un checkout no vence y MP no
 *      deja dar de baja un plan. Ver el encabezado de esa seccion.
 *
 * ── Por que el pago se comprueba CONTRA MP y no contra nuestra fecha ──
 *
 * `currentPeriodEnd` dice hasta cuando le DURA el plan al PF, no que lo haya
 * PAGADO. Una fecha futura tambien la pueden tener un PF sembrado a mano con el
 * Admin SDK (no hay pago que descontar) o una suscripcion que se cancelo antes de
 * cobrar nada, como una prueba cancelada antes de su primer cobro. Diferir contra
 * una fecha asi es regalar dias: por eso se exige ver en MP un cobro real, y el
 * diferimiento nunca pasa de lo que ese cobro cubre.
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

import { SubscriptionStatus } from "../effective-limit";
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
 * MP. Nuestra fecha puede estar corrida hacia adelante (un tope que no se aplico,
 * una fecha sembrada a mano) y MP puede respaldar menos de lo que ella dice:
 * quedarse con la menor es no regalarle al PF mas de lo que las dos aceptan.
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

// ---------------------------------------------------------------------------
// La otra mitad: como se LEE, al reconciliar, un plan que nacio con prueba.
// ---------------------------------------------------------------------------
//
// El plan diferido guarda `diferidoHastaMs` (E) en `mp_plans`. Mientras su
// suscripcion no tenga ningun cobro exitoso, el reconciliador la lee con las
// reglas de abajo; apenas MP cobra una vez, todo vuelve a ser como en cualquier
// otro plan. Las reglas existen por tres cosas que vienen de MP y no se pueden
// arreglar de nuestro lado:
//
//   1. **El link de un checkout no vence y MP no deja dar de baja un plan**
//      (`client.ts`, `cancelPreapproval`). Los dias de prueba se calcularon para
//      el momento en que se abrio el checkout; si el PF paga ese mismo link
//      semanas despues, el primer cobro cae semanas despues de E. Sin una regla,
//      le daria plan pago todo ese tiempo sin que MP haya cobrado nada. Y se
//      puede usar a proposito: abrir el checkout, no pagarlo, y autorizarlo
//      cuando convenga para correr el primer cobro tanto como se quiera.
//
//   2. **`pending_charge_quantity` durante la prueba.** Si MP cuenta el primer
//      cobro programado como pendiente (no esta verificado), `hayCobroPendiente`
//      lo leeria como un cobro rebotado y el PF pasaria a `grace`, con su mail de
//      "no pudimos cobrar", sin que se le haya intentado cobrar nada.
//
//   3. **Una prueba cancelada antes de su primer cobro.** `resolverFinDePeriodo`
//      arma el fin con `next_payment_date`, con lo que ya estaba guardado o, si
//      no hay nada, con alta mas un periodo entero. Ninguno de los tres sabe que
//      el PF solo pago hasta E (a traves del plan anterior): el ultimo le regala
//      un mes que nunca se cobro, y los otros se pasan de E por el redondeo a
//      dias.
//
// Lo que NO hacen: no dan de baja nada en MP. El pagador autorizo de buena fe, la
// baja es terminal, y una decision nuestra equivocada no se puede deshacer. Se
// limitan a decidir que escribimos en `subscription`.

/**
 * Cuanto despues de abrir el checkout puede autorizar el pagador para que la
 * prueba que le calculamos siga valiendo.
 *
 * Los dias se contaron desde el momento en que se abrio el checkout. Asumimos que
 * MP los cuenta desde que el pagador AUTORIZA (no esta medido), asi que el primer
 * cobro cae `autorizacion + dias`. Autorizando a las pocas horas la diferencia es
 * chica y entra en [HOLGURA_PRUEBA_MS]; autorizando varios dias despues, el cobro
 * se corre esos mismos dias y deja de ser el que le corresponde.
 */
export const VENTANA_AUTORIZACION_MS = 24 * 60 * 60 * 1000;

/**
 * Cuanto despues de E se sigue tratando como "en prueba" a una suscripcion que
 * todavia no cobro.
 *
 * El primer cobro cae en E o hasta un dia despues (por el `ceil` de
 * [diasDePrueba]) mas lo que tardo el pagador en autorizar (hasta
 * [VENTANA_AUTORIZACION_MS]), y MP puede demorarse en intentarlo. Tres dias
 * cubren eso con aire; pasados, un cobro pendiente vuelve a leerse como `grace`
 * y el aviso de "no pudimos cobrar" es verdad.
 */
export const HOLGURA_PRUEBA_MS = 3 * DIA_MS;

/** Lo que el reconciliador sabe de un plan y de su suscripcion de MP. */
export interface PruebaDiferidaInput {
  /**
   * `mp_plans/{planId}.diferidoHastaMs` (E), TAL CUAL salio del documento. Si no
   * es un numero finito, el plan no es diferido y nada de lo de abajo aplica.
   */
  diferidoHastaMs: unknown;
  /** `mp_plans/{planId}.createdAt` en ms, o `null` si no se pudo leer. */
  planCreadoMs: number | null;
  /** El `status` CRUDO de la suscripcion de MP. */
  mpStatus: unknown;
  /** El estado al que llego el mapeo de siempre (`mapMpStatus`). */
  statusHoy: SubscriptionStatus;
  /** `summarized` de la suscripcion de MP. */
  summarized: unknown;
  /** `date_created` de la suscripcion de MP: cuando el pagador autorizo. */
  mpDateCreated: unknown;
  nowMs: number;
}

/**
 * E si este plan es diferido Y su suscripcion todavia no cobro nada; si no,
 * `null`, que quiere decir "este plan se lee como cualquier otro".
 *
 * Que `charged_quantity` falte o no sea un numero se lee como "no cobro": es el
 * estado normal de una suscripcion recien autorizada. Desde el primer cobro real
 * las reglas se apagan solas, y con ellas cualquier posibilidad de que una
 * prueba retenga a alguien que ya esta pagando.
 */
function enPruebaSinCobrar(
  diferidoHastaMs: unknown,
  summarized: unknown,
): number | null {
  if (typeof diferidoHastaMs !== "number" || !Number.isFinite(diferidoHastaMs)) {
    return null;
  }
  const cobros = (summarized as { charged_quantity?: unknown } | null | undefined)
    ?.charged_quantity;
  if (typeof cobros === "number" && Number.isFinite(cobros) && cobros >= 1) {
    return null;
  }
  return diferidoHastaMs;
}

/**
 * Si la suscripcion se autorizo dentro de la ventana que la prueba calculada
 * tolera. Cualquier fecha que falte o no se entienda cuenta como FUERA: ante la
 * duda no se le da plan pago a una suscripcion que todavia no cobro.
 */
function autorizadaATiempo(
  planCreadoMs: number | null,
  mpDateCreated: unknown,
): boolean {
  if (planCreadoMs === null || !Number.isFinite(planCreadoMs)) return false;
  if (typeof mpDateCreated !== "string") return false;
  const autorizadaMs = Date.parse(mpDateCreated);
  if (!Number.isFinite(autorizadaMs)) return false;
  return autorizadaMs - planCreadoMs <= VENTANA_AUTORIZACION_MS;
}

/**
 * El estado que el reconciliador tiene que escribir para un plan que puede ser
 * diferido. Para uno que no lo es (o que ya cobro), devuelve [statusHoy] tal cual.
 *
 * Solo toca una suscripcion que MP dice `authorized`:
 *
 *   - **Autorizada fuera de la ventana** (el link se pago mucho despues de abrir
 *     el checkout): `pending`. De este plan el PF no recibe nada hasta el primer
 *     cobro real de MP, y la guarda de `pending` del reconciliador conserva lo
 *     que ya tuviera pago. Ver el punto 1 del encabezado de esta seccion.
 *
 *   - **A tiempo y antes de E + [HOLGURA_PRUEBA_MS]**: `active`, aunque MP diga
 *     que hay un cobro pendiente. Durante la prueba no se debe nada.
 *
 *   - **A tiempo y pasado ese horizonte**: el mapeo de siempre, o sea `grace` si
 *     hay un cobro pendiente. Ahi el primer cobro ya tendria que haber salido.
 */
export function aplicarPruebaDiferidaAlEstado(
  i: PruebaDiferidaInput,
): SubscriptionStatus {
  const e = enPruebaSinCobrar(i.diferidoHastaMs, i.summarized);
  if (e === null) return i.statusHoy;
  if (i.mpStatus !== "authorized") return i.statusHoy;

  if (!autorizadaATiempo(i.planCreadoMs, i.mpDateCreated)) return "pending";
  if (i.nowMs < e + HOLGURA_PRUEBA_MS) return "active";
  return i.statusHoy;
}

/**
 * El fin de periodo que el reconciliador tiene que escribir para un plan que
 * puede ser diferido. Para uno que no lo es (o que ya cobro), devuelve
 * [periodEndMs] tal cual.
 *
 * Solo toca una suscripcion que MP dice `cancelled` o `paused`: `min(fin, E)`, y
 * si no habia fin por ningun camino, E. El PF solo pago hasta E, a traves del
 * plan anterior; lo que pase de ahi (el mes que la cascada de
 * `resolverFinDePeriodo` deriva del alta) es un periodo que nunca se cobro.
 *
 * Tener E como respaldo cuando falta la fecha importa: un `null` le sacaria el
 * plan en el acto a alguien que si pago hasta E.
 *
 * El arrepentimiento NO pasa por aca. Quien llama conserva su precedencia: el
 * instante del arrepentimiento gana sobre cualquier fin de periodo.
 */
export function aplicarPruebaDiferidaAlPeriodo(
  i: PruebaDiferidaInput & { periodEndMs: number | null },
): number | null {
  const e = enPruebaSinCobrar(i.diferidoHastaMs, i.summarized);
  if (e === null) return i.periodEndMs;
  if (i.mpStatus !== "cancelled" && i.mpStatus !== "paused") {
    return i.periodEndMs;
  }
  return Math.min(i.periodEndMs ?? e, e);
}
