/**
 * Pure unit tests for athleteCountFromLinks (#388) — NO emulator needed.
 *
 * ALUMNOS on the coach public profile = DISTINCT athletes with an `active`
 * trainer_links doc. Pending/paused/terminated links must not count, and a
 * duplicated/malformed doc must never inflate the discovery sales surface.
 * The end-to-end Firestore wiring (recomputeAthleteCount) mirrors the
 * reviewAggregate emulator suite and shares its error-safe design.
 */

import { athleteCountFromLinks } from "../link-aggregate";

function link(
  docId: string,
  athleteId: string | undefined,
  status: string | undefined,
) {
  return { docId, athleteId, status };
}

describe("athleteCountFromLinks (#388 active-links student count)", () => {
  it("empty input → 0", () => {
    expect(athleteCountFromLinks([])).toBe(0);
  });

  it("counts only active links", () => {
    expect(
      athleteCountFromLinks([
        link("l1", "a1", "active"),
        link("l2", "a2", "pending"),
        link("l3", "a3", "paused"),
        link("l4", "a4", "terminated"),
      ]),
    ).toBe(1);
  });

  it("two distinct active athletes → 2 (the Lautaro seed case)", () => {
    expect(
      athleteCountFromLinks([
        link("l1", "martin", "active"),
        link("l2", "sofia", "active"),
      ]),
    ).toBe(2);
  });

  it("dedupes duplicated active links of the same athlete", () => {
    expect(
      athleteCountFromLinks([
        link("l1", "a1", "active"),
        link("l2", "a1", "active"),
      ]),
    ).toBe(1);
  });

  it("terminated + relinked active pair counts once via distinct docs", () => {
    expect(
      athleteCountFromLinks([
        link("old", "a1", "terminated"),
        link("new", "a1", "active"),
      ]),
    ).toBe(1);
  });

  it("active link missing athleteId falls back to docId (never dropped)", () => {
    expect(
      athleteCountFromLinks([
        link("legacy-doc", undefined, "active"),
        link("l2", "a2", "active"),
      ]),
    ).toBe(2);
  });

  it("missing status is not counted", () => {
    expect(athleteCountFromLinks([link("l1", "a1", undefined)])).toBe(0);
  });
});
