/**
 * tier-config.ts — subscription tier limits + price table (paywall Fase 7, PR1).
 *
 * Server-authoritative config for the PF→TREINO subscription. The weight
 * limits MUST stay in sync with `kTierWeightLimits` in
 * `lib/features/coach/domain/subscription_tier.dart` (client shows N/limit;
 * server enforces).
 *
 * Fase 1 = three flat tiers. Free 2 · Plan 1 7 · Plan 2 15. The usage-based
 * 16+ tier is Fase 2 and lives nowhere yet.
 */

export type SubscriptionTier = "free" | "plan1" | "plan2";
export type SubscriptionCycle = "monthly" | "annual";

/** Weighted-load limit per tier (active=1.0, paused=0.5 count toward it). */
export const TIER_WEIGHT_LIMITS: Record<SubscriptionTier, number> = {
  free: 2,
  plan1: 7,
  plan2: 15,
};

/**
 * Price table in ARS. Server-authoritative — NEVER trust a client-supplied
 * amount.
 *
 * ⚠️ PLACEHOLDER VALUES — GATE B (business decision, blocks PR3 go-live, NOT
 * PR1 merge). The real Plan 1 / Plan 2 monthly + annual prices and the annual
 * discount % are an open product/ops decision. Do NOT deploy the subscribe
 * flow (PR3) with these placeholders. `free` has no price (never charged).
 */
export const TIER_PRICES_ARS: Record<
  Exclude<SubscriptionTier, "free">,
  Record<SubscriptionCycle, number>
> = {
  // TODO(GATE-B): replace with real ARS prices before PR3 go-live.
  plan1: { monthly: 0, annual: 0 },
  plan2: { monthly: 0, annual: 0 },
};
