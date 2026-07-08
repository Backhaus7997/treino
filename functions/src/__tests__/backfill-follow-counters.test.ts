/**
 * Unit tests for the pure aggregator behind the follow-counters backfill.
 * No emulator / Firestore — just the fold logic.
 */

import { tallyFollowCounters } from "../../scripts/backfill-follow-counters";

describe("tallyFollowCounters", () => {
  it("counts an accepted follow on both sides", () => {
    const t = tallyFollowCounters([
      { requesterId: "a", members: ["a", "b"], status: "accepted" },
    ]);
    expect(t.get("a")).toEqual({ followers: 0, following: 1 }); // a follows b
    expect(t.get("b")).toEqual({ followers: 1, following: 0 }); // b followed
  });

  it("ignores pending friendships", () => {
    const t = tallyFollowCounters([
      { requesterId: "a", members: ["a", "b"], status: "pending" },
    ]);
    expect(t.size).toBe(0);
  });

  it("aggregates multiple follows for the same user", () => {
    const t = tallyFollowCounters([
      { requesterId: "a", members: ["a", "b"], status: "accepted" },
      { requesterId: "a", members: ["a", "c"], status: "accepted" },
      { requesterId: "d", members: ["d", "a"], status: "accepted" },
    ]);
    // a follows b and c (following 2), and is followed by d (followers 1).
    expect(t.get("a")).toEqual({ followers: 1, following: 2 });
    expect(t.get("b")).toEqual({ followers: 1, following: 0 });
    expect(t.get("c")).toEqual({ followers: 1, following: 0 });
    expect(t.get("d")).toEqual({ followers: 0, following: 1 });
  });

  it("skips malformed members (not exactly two)", () => {
    const t = tallyFollowCounters([
      { requesterId: "a", members: ["a"], status: "accepted" },
      { requesterId: "a", members: ["a", "b", "c"], status: "accepted" },
    ]);
    expect(t.size).toBe(0);
  });

  it("skips a friendship missing requesterId", () => {
    const t = tallyFollowCounters([
      { members: ["a", "b"], status: "accepted" },
    ]);
    expect(t.size).toBe(0);
  });

  it("skips when requester is not among members (corrupt doc)", () => {
    const t = tallyFollowCounters([
      { requesterId: "z", members: ["a", "b"], status: "accepted" },
    ]);
    // z isn't a member → the follow direction can't be trusted → skip.
    expect(t.size).toBe(0);
  });
});
