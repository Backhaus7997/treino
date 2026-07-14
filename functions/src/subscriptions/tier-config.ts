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
 * amount. `free` has no price (never charged).
 *
 * Precios definidos con estudio de mercado AR (competidores: ACTrainers,
 * EntrenadorPro, Rutify, Fibrit). Posicionamiento medio-alto — arriba de
 * ACTrainers/EntrenadorPro (producto más completo), debajo de Fibrit
 * (outlier). El anual da 2 meses gratis (~17% off): `monthly × 10`.
 *
 *   Plan 1 (3-7 alumnos):  $12.000/mes · $120.000/año
 *   Plan 2 (8-15 alumnos): $22.000/mes · $220.000/año
 */
export const TIER_PRICES_ARS: Record<
  Exclude<SubscriptionTier, "free">,
  Record<SubscriptionCycle, number>
> = {
  plan1: { monthly: 12000, annual: 120000 },
  plan2: { monthly: 22000, annual: 220000 },
};
