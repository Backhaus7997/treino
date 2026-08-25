/**
 * effective-limit.ts — resolves the weighted-load limit a trainer is actually
 * entitled to right now, from their subscription state (paywall Fase 7, PR1).
 * Pure function, no Firestore — unit-testable. Single source of truth for
 * "what limit applies" across the accept gate, the UI, and the downgrade job.
 */

import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "./tier-config";

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
}

const FREE_LIMIT = TIER_WEIGHT_LIMITS.free; // 2

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

  // OJO con `??` aca: `null` es un VALOR LEGITIMO (plan3 = sin tope), no una
  // ausencia. Con `TIER_WEIGHT_LIMITS[tier] ?? FREE_LIMIT` el plan mas caro
  // devolvia 2 — menos alumnos que el mas barato — y compilaba perfecto.
  // El chequeo de propiedad separa "el tier no existe" de "el tier no tiene
  // tope". Va con hasOwnProperty y no con `in`: `in` camina la CADENA DE
  // PROTOTIPOS, asi que `"toString" in TIER_WEIGHT_LIMITS` da true y devolvia
  // la funcion toString tipada como `number | null`. Un limite que es una
  // funcion rompe toda comparacion aguas abajo, en silencio.
  const tierLimit = Object.prototype.hasOwnProperty.call(TIER_WEIGHT_LIMITS, sub.tier)
    ? TIER_WEIGHT_LIMITS[sub.tier]
    : FREE_LIMIT;

  // Indentacion de los `case` al ras del `switch`: es lo que pide la regla
  // `indent` del repo (default SwitchCase: 0) y lo que ya hacia
  // notify-friendship.ts. Este archivo era el unico de src/ que la violaba
  // — nadie lo vio porque el CI corre build y tests, no eslint.
  switch (sub.status) {
  case "active":
  case "grace":
    return tierLimit;
  case "cancelled":
    return sub.currentPeriodEndMs != null && nowMs < sub.currentPeriodEndMs
      ? tierLimit
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
