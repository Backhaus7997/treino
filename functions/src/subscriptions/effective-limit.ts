/**
 * effective-limit.ts — resolves the weighted-load limit a trainer is actually
 * entitled to right now, from their subscription state (paywall Fase 7, PR1).
 * Pure function, no Firestore — unit-testable. Single source of truth for
 * "what limit applies" across the accept gate, the UI, and the downgrade job.
 */

import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "./tier-config";

export type SubscriptionStatus =
  | "active"
  | "pending"
  | "grace"
  | "paused"
  | "cancelled";

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
 */
export function effectiveWeightLimit(
  sub: SubscriptionState | null | undefined,
  nowMs: number = Date.now(),
): number {
  if (!sub) return FREE_LIMIT;

  const tierLimit = TIER_WEIGHT_LIMITS[sub.tier] ?? FREE_LIMIT;

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
  }
}
