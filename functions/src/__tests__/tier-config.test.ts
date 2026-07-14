/**
 * Unit tests for the tier price/limit config (paywall). Guards the pricing
 * invariants so a future edit can't silently break the "2 months free" promise
 * or drift the client/server limits apart.
 */

import {
  SubscriptionCycle,
  TIER_PRICES_ARS,
  TIER_WEIGHT_LIMITS,
} from "../subscriptions/tier-config";

describe("TIER_WEIGHT_LIMITS", () => {
  it("free=2, plan1=7, plan2=15", () => {
    expect(TIER_WEIGHT_LIMITS).toEqual({ free: 2, plan1: 7, plan2: 15 });
  });
});

describe("TIER_PRICES_ARS", () => {
  it("Plan 1 = $12.000/mes, $120.000/año", () => {
    expect(TIER_PRICES_ARS.plan1).toEqual({ monthly: 12000, annual: 120000 });
  });

  it("Plan 2 = $22.000/mes, $220.000/año", () => {
    expect(TIER_PRICES_ARS.plan2).toEqual({ monthly: 22000, annual: 220000 });
  });

  it("annual = monthly × 10 (2 months free) for every paid tier", () => {
    for (const tier of ["plan1", "plan2"] as const) {
      const p = TIER_PRICES_ARS[tier];
      expect(p.annual).toBe(p.monthly * 10);
    }
  });

  it("every paid tier has a positive price for every cycle", () => {
    const cycles: SubscriptionCycle[] = ["monthly", "annual"];
    for (const tier of ["plan1", "plan2"] as const) {
      for (const cycle of cycles) {
        expect(TIER_PRICES_ARS[tier][cycle]).toBeGreaterThan(0);
      }
    }
  });
});
