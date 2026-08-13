/**
 * Unit tests for the effective-limit resolver (paywall PR1). No infra.
 */

import {
  effectiveWeightLimit,
  SubscriptionState,
} from "../subscriptions/effective-limit";

const sub = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs?: number | null,
): SubscriptionState => ({ tier, status, currentPeriodEndMs });

const NOW = 1_000_000;

describe("effectiveWeightLimit", () => {
  it("null subscription → Free (2), no backfill", () => {
    expect(effectiveWeightLimit(null, NOW)).toBe(2);
    expect(effectiveWeightLimit(undefined, NOW)).toBe(2);
  });

  it("active → the paid tier limit", () => {
    expect(effectiveWeightLimit(sub("plan1", "active"), NOW)).toBe(7);
    expect(effectiveWeightLimit(sub("plan2", "active"), NOW)).toBe(15);
  });

  it("grace → still the paid tier limit (MP retrying, ADR-3)", () => {
    expect(effectiveWeightLimit(sub("plan2", "grace"), NOW)).toBe(15);
  });

  it("pending → Free (2), no entitlement until webhook confirms", () => {
    expect(effectiveWeightLimit(sub("plan2", "pending"), NOW)).toBe(2);
  });

  it("paused → Free (2)", () => {
    expect(effectiveWeightLimit(sub("plan1", "paused"), NOW)).toBe(2);
  });

  it("cancelled before currentPeriodEnd → still paid tier", () => {
    expect(
      effectiveWeightLimit(sub("plan2", "cancelled", NOW + 1000), NOW),
    ).toBe(15);
  });

  it("cancelled after currentPeriodEnd → Free (2)", () => {
    expect(
      effectiveWeightLimit(sub("plan2", "cancelled", NOW - 1000), NOW),
    ).toBe(2);
  });

  it("cancelled with null currentPeriodEnd → Free (2)", () => {
    expect(effectiveWeightLimit(sub("plan2", "cancelled", null), NOW)).toBe(2);
  });
});
