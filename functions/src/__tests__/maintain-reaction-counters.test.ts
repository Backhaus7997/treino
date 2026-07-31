/**
 * Unit tests for the pure reaction-count aggregation logic.
 *
 * No emulator or network access is required.
 */

import { aggregateReactionCounts } from "../social/maintain-reaction-counters";

describe("aggregateReactionCounts", () => {
  it("groups reactions by supported type", () => {
    expect(
      aggregateReactionCounts([
        { type: "strong" },
        { type: "fire" },
        { type: "strong" },
        { type: "clap" },
        { type: "fire" },
      ]),
    ).toEqual({ strong: 2, fire: 2, clap: 1 });
  });

  it("returns an empty map when there are no reactions", () => {
    expect(aggregateReactionCounts([])).toEqual({});
  });

  it("omits zero-count reaction types", () => {
    expect(aggregateReactionCounts([{ type: "fire" }])).toEqual({ fire: 1 });
  });

  it("ignores malformed and unsupported reaction documents", () => {
    expect(
      aggregateReactionCounts([
        { type: "strong" },
        { type: "heart" },
        { type: 42 },
        {},
      ]),
    ).toEqual({ strong: 1 });
  });
});
