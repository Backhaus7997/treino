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
        { type: "like" },
        { type: "fire" },
        { type: "like" },
        { type: "clap" },
        { type: "fire" },
      ]),
    ).toEqual({ like: 2, fire: 2, clap: 1 });
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
        { type: "like" },
        { type: "heart" },
        { type: 42 },
        {},
      ]),
    ).toEqual({ like: 1 });
  });

  // Guard against the failure that shipped when `strong` was renamed to `like`:
  // this function keeps its own copy of the type list, so a rename in Dart and
  // in firestore.rules left it silently dropping every reaction and writing an
  // empty counter. Nothing failed — the counter just stayed at zero.
  //
  // Keep this list in sync with:
  //   - `ReactionType` in lib/features/feed/domain/reaction_type.dart
  //   - the allowlist in `reactionPayloadOk()` in firestore.rules
  it("counts exactly the reaction types the app and rules allow", () => {
    const appReactionTypes = ["like", "fire", "clap"];

    const counts = aggregateReactionCounts(
      appReactionTypes.map((type) => ({ type })),
    );

    expect(Object.keys(counts).sort()).toEqual([...appReactionTypes].sort());
    expect(counts).toEqual({ like: 1, fire: 1, clap: 1 });
  });

  it("no longer counts the retired `strong` type", () => {
    expect(aggregateReactionCounts([{ type: "strong" }])).toEqual({});
  });
});
