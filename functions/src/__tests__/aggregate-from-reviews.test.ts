/**
 * Pure unit tests for aggregateFromReviews (QA-REV-002) — NO emulator needed.
 *
 * The relink-manipulation dedupe logic ("una persona = una opinión") is
 * validated here in isolation; the end-to-end Firestore wiring is covered by
 * SCENARIO-REV-002 in review-aggregate.test.ts (which requires the emulator).
 */

import { aggregateFromReviews } from "../review-aggregate";

// Row builder. updatedAt as raw millis — aggregateFromReviews' toMillis accepts
// numbers, so we avoid needing a Firestore Timestamp here.
function row(docId: string, athleteId: string, rating: number, updatedAt = 0) {
  return { docId, athleteId, rating, updatedAt };
}

describe("aggregateFromReviews (QA-REV-002 dedupe by athleteId)", () => {
  it("empty input → null average, 0 count", () => {
    expect(aggregateFromReviews([])).toEqual({
      averageRating: null,
      reviewCount: 0,
    });
  });

  it("distinct athletes are averaged and counted as-is", () => {
    const agg = aggregateFromReviews([
      row("link1_a1", "a1", 4),
      row("link2_a2", "a2", 2),
    ]);
    expect(agg.reviewCount).toBe(2);
    expect(agg.averageRating).toBeCloseTo(3, 5);
  });

  it("same athlete relinked counts ONCE, keeping the latest rating", () => {
    const agg = aggregateFromReviews([
      row("link1_a1", "a1", 5, 1_000), // older review
      row("link2_a1", "a1", 1, 2_000), // newer relink review
    ]);
    expect(agg.reviewCount).toBe(1);
    // Latest opinion (1) wins — NOT the inflated average of 5 and 1 (= 3).
    expect(agg.averageRating).toBeCloseTo(1, 5);
  });

  it("mixes a relinked athlete and a distinct athlete correctly", () => {
    const agg = aggregateFromReviews([
      row("link1_a1", "a1", 4, 1_000),
      row("link2_a1", "a1", 4, 2_000), // a1 relink → still one opinion
      row("link3_a2", "a2", 2, 1_000),
    ]);
    expect(agg.reviewCount).toBe(2); // a1 + a2
    expect(agg.averageRating).toBeCloseTo(3, 5); // (4 + 2) / 2
  });

  it("picks the latest by updatedAt regardless of array order", () => {
    const agg = aggregateFromReviews([
      row("link2_a1", "a1", 1, 2_000), // newer, listed first
      row("link1_a1", "a1", 5, 1_000), // older, listed second
    ]);
    expect(agg.reviewCount).toBe(1);
    expect(agg.averageRating).toBeCloseTo(1, 5); // the 2_000 review wins
  });

  it("falls back to docId when athleteId is missing (never drops a review)", () => {
    const agg = aggregateFromReviews([
      { docId: "legacy1", rating: 4 },
      { docId: "legacy2", rating: 2 },
    ]);
    expect(agg.reviewCount).toBe(2);
    expect(agg.averageRating).toBeCloseTo(3, 5);
  });

  it("treats a missing rating as 0", () => {
    const agg = aggregateFromReviews([
      row("link1_a1", "a1", 4),
      { docId: "link2_a2", athleteId: "a2" }, // no rating
    ]);
    expect(agg.reviewCount).toBe(2);
    expect(agg.averageRating).toBeCloseTo(2, 5); // (4 + 0) / 2
  });
});
