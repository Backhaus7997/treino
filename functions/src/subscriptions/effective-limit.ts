/**
 * effective-limit.ts — resolves the weighted-load limit a trainer is actually
 * entitled to right now, from their subscription state (paywall Fase 7, PR1).
 * Pure function, no Firestore — unit-testable. Single source of truth for
 * "what limit applies" across the accept gate, the UI, and the downgrade job.
 */

import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "./tier-config";

// Set y no `in`: mismo motivo que `tierLimit` — "toString" vive en el
// prototipo y `"toString" in TIER_WEIGHT_LIMITS` da `true`.
const KNOWN_TIERS: ReadonlySet<string> = new Set(Object.keys(TIER_WEIGHT_LIMITS));

/**
 * Runtime list of every valid status. La union se DERIVA de esta lista, no al
 * reves, para que el validador de `subscription-state.ts` no pueda quedar
 * desincronizado del tipo: agregar un status sin darselo al validador deja de
 * ser posible.
 */
export const SUBSCRIPTION_STATUSES = [
  "active",
  "pending",
  "grace",
  "paused",
  "cancelled",
] as const;

export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

/** The subscription sub-object on users/{uid}, as the resolver reads it. */
export interface SubscriptionState {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  /** MP-confirmed paid-through instant, ms since epoch. Null while free. */
  currentPeriodEndMs?: number | null;
  /**
   * EL PISO PREPAGO: el tier que el PF ya pago y que sigue vigente aunque su
   * suscripcion actual sea otra. Ver [resolverPisoPrepago] para de donde sale.
   */
  prepaidTier?: SubscriptionTier | null;
  /** Hasta cuando vale el piso, ms desde epoch. Va SIEMPRE con `prepaidTier`. */
  prepaidUntilMs?: number | null;
}

/**
 * El piso prepago, como lo devuelve [resolverPisoPrepago] y como se escribe.
 * Los dos campos viajan juntos o no viajan: uno solo no significa nada.
 */
export interface PisoPrepago {
  tier: SubscriptionTier;
  untilMs: number;
}

const FREE_LIMIT = TIER_WEIGHT_LIMITS.free; // 2

/**
 * Ordena limites para poder comparar `number | null`.
 *
 * `null` es plan3 = SIN TOPE, o sea el MAYOR de todos — no una ausencia. Un `>`
 * a secas con `null` de un lado compara contra 0 en JS y da la respuesta al
 * reves, y justo para el PF que mas paga.
 *
 * Vive ACA, que es el modulo puro del limite, y no en cada consumidor. Habia dos
 * copias privadas —`limitRank` en `subscription-mail.ts` y `rangoDelLimite` en
 * `mp/reconcile.ts`— y el piso prepago necesitaba una tercera adentro de este
 * mismo archivo. Tres copias de la misma trampa es como se desincroniza: la
 * cuarta persona que la escriba de memoria se la come.
 */
export function limitRank(limit: number | null): number {
  return limit === null ? Number.POSITIVE_INFINITY : limit;
}

/**
 * El limite NOMINAL de un tier. `null` = SIN TOPE (plan3).
 *
 * Va con `hasOwnProperty` y NO con `in`: `in` camina la cadena de prototipos,
 * asi que `"toString" in TIER_WEIGHT_LIMITS` da true y devolveria la funcion
 * toString tipada como `number | null`. Un limite que es una funcion rompe toda
 * comparacion aguas abajo, en silencio. Estaba inline en `effectiveWeightLimit`;
 * se extrae porque el piso prepago necesita exactamente lo mismo.
 */
export function tierLimit(tier: SubscriptionTier): number | null {
  return Object.prototype.hasOwnProperty.call(TIER_WEIGHT_LIMITS, tier)
    ? TIER_WEIGHT_LIMITS[tier]
    : FREE_LIMIT;
}

/**
 * Effective weighted-load limit for a subscription.
 *
 * - null subscription (no map at all) → Free (2). No backfill needed.
 * - active / grace → the paid tier limit. Grace still entitled: MP is
 *   retrying within the 7-day window, don't punish on first failure (ADR-3).
 * - pending → Free (2) at launch. A first-time subscriber has no prior paid
 *   entitlement until the webhook confirms.
 * - paused → Free (2).
 * - cancelled → paid tier until currentPeriodEnd, then Free. (`nowMs` lets the
 *   caller pass a deterministic clock; defaults to Date.now()).
 * - unknown tier / unknown status → Free (2). Nunca undefined: ver el default
 *   del switch.
 */
/**
 * Limite efectivo del PF. `null` = SIN LIMITE (plan3, ver tier-config).
 * Todo consumidor tiene que contemplar ese caso — el tipo lo obliga.
 */
export function effectiveWeightLimit(
  sub: SubscriptionState | null | undefined,
  nowMs: number = Date.now(),
): number | null {
  if (!sub) return FREE_LIMIT;

  return conPisoPrepago(limiteDelStatus(sub, nowMs), sub, nowMs);
}

/**
 * El maximo entre lo que dice el status y el PISO PREPAGO, mientras el piso siga
 * vigente.
 *
 * ── Por que el piso NO pasa por el switch de status ──
 *
 * Porque no habla de la suscripcion actual: dice "esto ya esta pagado". El
 * status del plan NUEVO no tiene nada que opinar sobre un periodo que el PF
 * compro antes. Si el piso pasara por el switch, un `pending` del plan nuevo lo
 * bajaria a Free y el piso no serviria para nada justo cuando mas hace falta.
 *
 * ── Por que MAXIMO y no reemplazo ──
 *
 * Es un PISO, nunca un techo. Solo puede SUBIR el limite. Eso es lo que hace
 * que este cambio sea seguro para los cuatro consumidores de este modulo: el
 * gate de `promote-link` puede dejar pasar de mas pero nunca denegar de mas, y
 * el barrido de `sync-entitlements` puede desbloquear pero nunca bloquear por
 * culpa del piso. Un bug acá se paga en cupo regalado, no en alumnos
 * bloqueados — que es el lado barato de equivocarse.
 *
 * Se compara con [limitRank] y NUNCA con `>` a secas: `null` es plan3 = SIN
 * TOPE, o sea el mayor, y crudo vale 0.
 */
function conPisoPrepago(
  base: number | null,
  sub: SubscriptionState,
  nowMs: number,
): number | null {
  const { prepaidTier, prepaidUntilMs } = sub;
  if (prepaidTier == null || prepaidUntilMs == null) return base;
  if (nowMs >= prepaidUntilMs) return base;

  const piso = tierLimit(prepaidTier);
  return limitRank(piso) > limitRank(base) ? piso : base;
}

/** El limite que sale del status, o sea el modulo entero antes del piso. */
function limiteDelStatus(
  sub: SubscriptionState,
  nowMs: number,
): number | null {
  // OJO con `??` aca: `null` es un VALOR LEGITIMO (plan3 = sin tope), no una
  // ausencia. Con `TIER_WEIGHT_LIMITS[tier] ?? FREE_LIMIT` el plan mas caro
  // devolvia 2 — menos alumnos que el mas barato — y compilaba perfecto.
  // El chequeo de propiedad vive ahora en [tierLimit]; ver el porque del
  // `hasOwnProperty` alla.
  const limiteNominal = tierLimit(sub.tier);

  // Indentacion de los `case` al ras del `switch`: es lo que pide la regla
  // `indent` del repo (default SwitchCase: 0) y lo que ya hacia
  // notify-friendship.ts. Este archivo era el unico de src/ que la violaba
  // — nadie lo vio porque el CI corre build y tests, no eslint.
  switch (sub.status) {
  case "active":
  case "grace":
    return limiteNominal;
  case "cancelled":
    return sub.currentPeriodEndMs != null && nowMs < sub.currentPeriodEndMs
      ? limiteNominal
      : FREE_LIMIT;
  case "pending":
  case "paused":
    return FREE_LIMIT;
  // ── DOS garantias distintas, y hacen falta las dos ──────────────────────
  //
  // 1. RUNTIME (`return FREE_LIMIT`). El tipo es una promesa de compilacion
  //    sobre un dato que se escribe A MANO con el Admin SDK (ninguna Cloud
  //    Function escribe `subscription`). Sin default, un "canceled" de una sola
  //    L caia por afuera del switch y la funcion devolvia undefined, con dos
  //    efectos opuestos y los dos malos: el gate de promote-link dejaba de
  //    denegar (`carga > undefined` es false) y el barrido de sync-entitlements
  //    bloqueaba a TODOS los alumnos (`carga <= undefined` tambien es false).
  //    El mismo typo abria el paywall y vaciaba el padron.
  //
  // 2. COMPILACION (`const _exhaustive: never`). Un default pelado se come esa
  //    garantia: antes, el switch SIN default hacia que agregar un miembro a
  //    SUBSCRIPTION_STATUSES sin manejarlo fuera error de compilacion. Con solo
  //    el default, el dia que alguien agregue "trialing" — que es justo lo que
  //    este diseño invita a hacer — todo plan2 en trial resuelve a 2 alumnos:
  //    sin error, sin test rojo y sin warn, porque el status ES valido y el
  //    mapper no lo degrada. Exactamente el bug que este modulo vino a cerrar,
  //    entrando por la puerta de atras. Esta asignacion vuelve a romper el
  //    build en ese caso: `sub.status` solo es `never` si el switch cubrio toda
  //    la union. El `void` es porque `noUnusedLocals` esta prendido.
  default: {
    const _exhaustive: never = sub.status;
    void _exhaustive;
    return FREE_LIMIT;
  }
  }
}

/**
 * Que PISO PREPAGO hay que dejar escrito cuando el reconciliador esta por
 * escribir [tierEntrante] encima de [actual].
 *
 * PURA, como todo este archivo: sin Firestore, sin reloj propio, sin MP.
 *
 * ── EL PROBLEMA QUE RESUELVE ──
 *
 * Un PF con plan3 (SIN TOPE) que se pasa a plan1 (7) perdia el remanente que ya
 * habia pagado: el reconciliador escribia `{tier: plan1, status: active}` y el
 * `currentPeriodEnd` del plan3 desaparecia del entitlement. El limite caia en el
 * acto y `syncEntitlementsOnSubscription` le bloqueaba alumnos EN LA MISMA
 * invocacion, mas el mail de degradacion. A alguien que pago por esos alumnos.
 *
 * Lo mismo con el ANUAL: plan3 anual son 12 meses en UN cobro. Un cambio en
 * marzo evaporaba nueve.
 *
 * ── DE DONDE SALE EL DATO, QUE ES LA PARTE LINDA ──
 *
 * De ningun lado nuevo. [actual] es lo que el reconciliador esta por PISAR, y es
 * exactamente lo que se pierde — refrescado todas las noches por el barrido
 * mientras ese plan estuvo vivo. Cero llamadas a MP: el piso no depende de que
 * la baja confirme, asi que un 429 de Mercado Pago no le toca el entitlement al
 * PF.
 *
 * ── LOS DOS CONSERVABLES ──
 *
 *   1. El piso que YA estaba guardado, si sigue vigente. Nunca se tira uno vivo:
 *      tirarlo BAJA el limite, y bajar el limite es revocar relaciones
 *      existentes — lo que la politica de `subscription-state.ts` prohibe.
 *
 *   2. El periodo que estamos por pisar, si es futuro, si su status dice que se
 *      pago (`active`, `grace` o `cancelled`) y —esto es lo que evita el bug
 *      obvio— si su tier es ESTRICTAMENTE MAYOR que el entrante.
 *
 * Gana el de mayor tier; si empatan, el de fecha mas lejana.
 *
 * ── POR QUE LA COMPARACION VA CONTRA EL TIER NOMINAL DE [actual] ──
 *
 * Y no contra el limite EFECTIVO, que es la version ingenua y esta rota. El
 * limite efectivo ya incluye el piso, asi que un plan1 con piso plan3
 * reconciliandose todas las noches se veria a si mismo como "downgrade" y
 * capturaria un piso nuevo de plan1 cada noche: escritura diaria de
 * `users/{uid}`, o sea un disparo diario de `syncEntitlementsOnSubscription`
 * para siempre. Comparando tier nominal contra tier entrante, reconciliar el
 * MISMO plan no captura nada y el piso viejo se conserva intacto.
 *
 * @param actual        - Lo que hoy dice `users/{uid}.subscription`, ya saneado.
 * @param tierEntrante  - El tier que el reconciliador esta por escribir.
 * @param statusEntrante- El status que va con el. Solo `active`/`grace` capturan
 *                        piso nuevo: un `pending` no confirma ninguna compra, y
 *                        `paused`/`cancelled` entrantes son otra politica.
 * @param nowMs         - Reloj, inyectado.
 */
export function resolverPisoPrepago(
  actual: SubscriptionState | null | undefined,
  tierEntrante: SubscriptionTier,
  statusEntrante: SubscriptionStatus,
  nowMs: number,
): PisoPrepago | null {
  if (!actual) return null;

  const candidatos: PisoPrepago[] = [];

  // (1) El piso guardado, si no vencio.
  if (
    actual.prepaidTier != null &&
    actual.prepaidUntilMs != null &&
    nowMs < actual.prepaidUntilMs
  ) {
    candidatos.push({ tier: actual.prepaidTier, untilMs: actual.prepaidUntilMs });
  }

  // (2) Lo que estamos por pisar, solo si el entrante CONFIRMA una compra.
  const confirma = statusEntrante === "active" || statusEntrante === "grace";
  const pago =
    actual.status === "active" ||
    actual.status === "grace" ||
    actual.status === "cancelled";
  if (
    confirma &&
    pago &&
    actual.currentPeriodEndMs != null &&
    nowMs < actual.currentPeriodEndMs &&
    limitRank(tierLimit(actual.tier)) > limitRank(tierLimit(tierEntrante))
  ) {
    candidatos.push({ tier: actual.tier, untilMs: actual.currentPeriodEndMs });
  }

  if (candidatos.length === 0) return null;

  return candidatos.reduce((mejor, c) => {
    const rc = limitRank(tierLimit(c.tier));
    const rm = limitRank(tierLimit(mejor.tier));
    if (rc !== rm) return rc > rm ? c : mejor;
    return c.untilMs > mejor.untilMs ? c : mejor;
  });
}

// ─────────────────────────────────────────────────────────────────────────
// effectiveTier — limite-ejercicios-pf.md, PR1.
//
// El tope de ejercicios propios (`TIER_CUSTOM_EXERCISE_LIMITS`) se resuelve
// contra el TIER del PF, no contra un numero — a diferencia del tope de
// alumnos, que ES un numero (peso). Por eso hace falta una funcion que
// devuelva el tier efectivo, no el limite efectivo: `trainer-plan-limits.ts`
// hace `customExerciseLimitFor(effectiveTier(sub, nowMs))`.
//
// NO LLAMA A [effectiveWeightLimit] NI AL REVES. Son dos funciones puras que
// REPLICAN la misma matriz de casos, a proposito: `effectiveWeightLimit` es
// el camino de la plata (bloquea/desbloquea alumnos) y esta decision del plan
// (limite-ejercicios-pf.md, PR1) es explicita en no tocarlo ni compartir
// codigo forzado con el. La consistencia entre las dos no se garantiza por
// construccion: se prueba con un test, `effective-tier.test.ts`, que usa
// `tierLimit(effectiveTier(s)) === effectiveWeightLimit(s)` como oraculo
// sobre toda la matriz de estados.
// ─────────────────────────────────────────────────────────────────────────

/**
 * Tier efectivo del PF. Nunca undefined, nunca un tier inventado: un tier
 * desconocido en el mapa degrada a `"free"`, igual que `tierLimit` degrada su
 * limite.
 *
 * El PISO PREPAGO se aplica igual que en `effectiveWeightLimit` —MAXIMO,
 * nunca reemplazo— pero comparando por RANGO DE TIER en vez de por limite.
 * Reusa `tierLimit` + `limitRank` (ya exportadas y ya testeadas) para ese
 * ranking: la escalera de `TIER_CUSTOM_EXERCISE_LIMITS` crece en el MISMO
 * orden que `TIER_WEIGHT_LIMITS` (free < plan1 < plan2 < plan3, decision E1
 * del plan), asi que rankear por el limite de peso rankea por tier sin
 * necesitar una segunda tabla de orden que se pueda desincronizar.
 */
export function effectiveTier(
  sub: SubscriptionState | null | undefined,
  nowMs: number = Date.now(),
): SubscriptionTier {
  if (!sub) return "free";
  return tierConPisoPrepago(tierDelStatus(sub, nowMs), sub, nowMs);
}

/** El tier NOMINAL, saneado contra el mapa conocido. Ver `tierLimit`. */
function tierNominal(tier: SubscriptionTier): SubscriptionTier {
  return KNOWN_TIERS.has(tier) ? tier : "free";
}

/**
 * El tier que sale del status, antes del piso. Mismos cinco casos que
 * `limiteDelStatus`, con la misma doble garantia de exhaustividad (runtime +
 * compilacion) — ver el docblock de esa funcion para el porque de cada una.
 */
function tierDelStatus(
  sub: SubscriptionState,
  nowMs: number,
): SubscriptionTier {
  switch (sub.status) {
  case "active":
  case "grace":
    return tierNominal(sub.tier);
  case "cancelled":
    return sub.currentPeriodEndMs != null && nowMs < sub.currentPeriodEndMs
      ? tierNominal(sub.tier)
      : "free";
  case "pending":
  case "paused":
    return "free";
  default: {
    const _exhaustive: never = sub.status;
    void _exhaustive;
    return "free";
  }
  }
}

/** El maximo entre el tier del status y el PISO PREPAGO, por rango de tier. */
function tierConPisoPrepago(
  base: SubscriptionTier,
  sub: SubscriptionState,
  nowMs: number,
): SubscriptionTier {
  const { prepaidTier, prepaidUntilMs } = sub;
  if (prepaidTier == null || prepaidUntilMs == null) return base;
  if (nowMs >= prepaidUntilMs) return base;

  const piso = tierNominal(prepaidTier);
  return limitRank(tierLimit(piso)) > limitRank(tierLimit(base)) ? piso : base;
}
