/**
 * Unit tests for the fractional weighted-load math (paywall PR1). No infra.
 */

import {
  canAccept,
  computeWeightedLoad,
  round2,
  WeightedLink,
} from "../subscriptions/weighted-load";

const link = (
  athleteId: string,
  status: WeightedLink["status"],
  entitlement?: "entitled" | "blocked",
): WeightedLink => ({ athleteId, status, entitlement });

describe("computeWeightedLoad", () => {
  it("active=1.0, paused=0.5, terminated=0", () => {
    expect(
      computeWeightedLoad([
        link("a", "active"),
        link("b", "paused"),
        link("c", "terminated"),
      ]),
    ).toBe(1.5);
  });

  it("pending links do not count (not following yet)", () => {
    expect(computeWeightedLoad([link("a", "pending")])).toBe(0);
  });

  it("blocked links are excluded (parked excess, ADR-5)", () => {
    expect(
      computeWeightedLoad([
        link("a", "active"),
        link("b", "active", "blocked"),
      ]),
    ).toBe(1.0);
  });

  it("dedupes by athlete, keeping the heaviest status", () => {
    // Same athlete: a historical terminated + a live active → count active only.
    expect(
      computeWeightedLoad([
        link("a", "terminated"),
        link("a", "active"),
      ]),
    ).toBe(1.0);
  });

  it("6 active + 2 paused sums to exactly 7.0", () => {
    const links = [
      ...["a", "b", "c", "d", "e", "f"].map((id) => link(id, "active")),
      link("g", "paused"),
      link("h", "paused"),
    ];
    expect(computeWeightedLoad(links)).toBe(7.0);
  });

  it("no accumulation drift over many halves", () => {
    const links = Array.from({ length: 21 }, (_, i) =>
      link(`p${i}`, "paused"),
    );
    // 21 × 0.5 = 10.5 exactly, no float noise.
    expect(computeWeightedLoad(links)).toBe(10.5);
  });
});

describe("canAccept — boundary math (strict <=)", () => {
  it("6a+2p=7.0 at plan1(7): adding an active (8.0) is blocked", () => {
    expect(canAccept(7.0, 1.0, 7)).toBe(false);
  });

  it("6a+1p=6.5: adding an active (7.5) is blocked (fraction over limit)", () => {
    expect(canAccept(6.5, 1.0, 7)).toBe(false);
  });

  it("6a=6.0 at plan1(7): adding an active (7.0) is allowed (at limit)", () => {
    expect(canAccept(6.0, 1.0, 7)).toBe(true);
  });

  it("free tier: 1 active (1.0), adding an active (2.0) at limit 2 allowed", () => {
    expect(canAccept(1.0, 1.0, 2)).toBe(true);
  });

  it("free tier: 2 active (2.0), adding an active (3.0) blocked", () => {
    expect(canAccept(2.0, 1.0, 2)).toBe(false);
  });

  it("accepting a paused-weight incoming (0.5) uses the fractional weight", () => {
    // 6.5 + 0.5 = 7.0 at limit 7 → allowed.
    expect(canAccept(6.5, 0.5, 7)).toBe(true);
  });
});

describe("round2", () => {
  it("snaps to nearest half", () => {
    expect(round2(6.9999999999)).toBe(7.0);
    expect(round2(7.5)).toBe(7.5);
    expect(round2(0.3)).toBe(0.5);
    expect(round2(0.2)).toBe(0.0);
  });
});
