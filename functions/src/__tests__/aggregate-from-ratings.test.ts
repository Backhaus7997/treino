/**
 * Pure unit tests for aggregateFromRatings (no emulator needed).
 *
 * Doc ids are rater uids (one doc per user by construction), so unlike
 * aggregateFromReviews there is no dedup dimension — these tests focus on
 * the average math and the defensive filtering of garbage rows.
 *
 * Fase W3 (template publishing).
 */

import { aggregateFromRatings } from "../template-rating-aggregate";

describe("aggregateFromRatings", () => {
  it("returns null + 0 for an empty list", () => {
    expect(aggregateFromRatings([])).toEqual({
      ratingAvg: null,
      ratingsCount: 0,
    });
  });

  it("computes the average of a single rating", () => {
    expect(aggregateFromRatings([{ rating: 4 }])).toEqual({
      ratingAvg: 4,
      ratingsCount: 1,
    });
  });

  it("computes a fractional average", () => {
    const result = aggregateFromRatings([
      { rating: 5 },
      { rating: 4 },
      { rating: 4 },
    ]);
    expect(result.ratingsCount).toBe(3);
    expect(result.ratingAvg).toBeCloseTo(13 / 3, 6);
  });

  it("skips rows whose rating is missing or not a number", () => {
    const result = aggregateFromRatings([
      { rating: 5 },
      {},
      { rating: "4" as unknown as number },
      { rating: null as unknown as number },
    ]);
    expect(result).toEqual({ ratingAvg: 5, ratingsCount: 1 });
  });

  it("skips out-of-range ratings so one bad doc cannot poison the aggregate", () => {
    const result = aggregateFromRatings([
      { rating: 3 },
      { rating: 0 },
      { rating: 6 },
      { rating: -1 },
    ]);
    expect(result).toEqual({ ratingAvg: 3, ratingsCount: 1 });
  });

  it("returns null + 0 when every row is invalid", () => {
    expect(aggregateFromRatings([{ rating: 99 }, {}])).toEqual({
      ratingAvg: null,
      ratingsCount: 0,
    });
  });
});
