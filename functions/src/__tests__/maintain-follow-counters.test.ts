/**
 * Unit + integration tests for maintainFollowCounters.
 *
 * Unit tests exercise the pure `resolveCounterDelta` — the full transition
 * truth table, no emulator required.
 *
 * Integration tests exercise `maintainFollowCountersHandler` against the
 * Firestore emulator to verify the transactional both-sides update, the
 * skip-missing-doc guard, and symmetry (the bug that motivated this CF:
 * delete used to leave a phantom follower).
 */

import * as admin from "firebase-admin";
import {
  maintainFollowCountersHandler,
  resolveCounterDelta,
} from "../social/maintain-follow-counters";

const members = ["req", "other"];
const accepted = { status: "accepted", requesterId: "req", members };
const pending = { status: "pending", requesterId: "req", members };

// ─── Unit tests (no emulator) ──────────────────────────────────────────────

describe("resolveCounterDelta — transition truth table", () => {
  it("∅ → accepted (auto-accept) applies +1 to both", () => {
    expect(resolveCounterDelta(undefined, accepted)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: 1,
    });
  });

  it("pending → accepted (manual accept) applies +1 to both", () => {
    expect(resolveCounterDelta(pending, accepted)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: 1,
    });
  });

  it("accepted → ∅ (unfollow / delete) applies -1 to both", () => {
    expect(resolveCounterDelta(accepted, undefined)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: -1,
    });
  });

  it("∅ → pending is a noop (not yet following)", () => {
    expect(resolveCounterDelta(undefined, pending)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });

  it("pending → ∅ (cancel request) is a noop (never counted)", () => {
    expect(resolveCounterDelta(pending, undefined)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });

  it("accepted → accepted (no-op write) is a noop", () => {
    expect(resolveCounterDelta(accepted, accepted)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });

  it("becoming accepted with malformed parties is a noop", () => {
    const bad = { status: "accepted", requesterId: "req", members: ["req"] };
    expect(resolveCounterDelta(undefined, bad)).toEqual({
      kind: "noop",
      reason: "after: malformed parties",
    });
  });

  it("leaving accepted with malformed parties is a noop", () => {
    const bad = { status: "accepted", members }; // no requesterId
    expect(resolveCounterDelta(bad, undefined)).toEqual({
      kind: "noop",
      reason: "before: malformed parties",
    });
  });
});

// ─── Integration tests (require emulator) ──────────────────────────────────

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "maintain-follow-counters-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

async function seedProfile(
  uid: string,
  counters: { followersCount?: number; followingCount?: number } = {},
): Promise<void> {
  await db().collection("userPublicProfiles").doc(uid).set({ uid, ...counters });
}

async function counters(
  uid: string,
): Promise<{ followers: number; following: number }> {
  const snap = await db().collection("userPublicProfiles").doc(uid).get();
  const d = snap.data() ?? {};
  return {
    followers: (d.followersCount as number | undefined) ?? 0,
    following: (d.followingCount as number | undefined) ?? 0,
  };
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db()
      .collection("userPublicProfiles")
      .doc(uid)
      .delete()
      .catch(() => undefined);
  }
}

describe("maintainFollowCountersHandler — integration", () => {
  const req = "mfc-req";
  const other = "mfc-other";
  const pair = [req, other];
  const acceptedDoc = { status: "accepted", requesterId: req, members: pair };
  const pendingDoc = { status: "pending", requesterId: req, members: pair };

  beforeEach(async () => {
    await seedProfile(req, { followingCount: 0, followersCount: 0 });
    await seedProfile(other, { followingCount: 0, followersCount: 0 });
  });

  afterEach(() => cleanup(req, other));

  it("accept increments requester.following AND other.followers (symmetry)", async () => {
    await maintainFollowCountersHandler(testApp, pendingDoc, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  it("unfollow decrements BOTH sides — no phantom follower (the bug)", async () => {
    // Start from the followed state.
    await seedProfile(req, { followingCount: 1, followersCount: 0 });
    await seedProfile(other, { followingCount: 0, followersCount: 1 });

    // accepted → deleted.
    await maintainFollowCountersHandler(testApp, acceptedDoc, undefined);

    expect(await counters(req)).toEqual({ followers: 0, following: 0 });
    // Previously followersCount stayed at 1 (phantom). Now it is decremented.
    expect(await counters(other)).toEqual({ followers: 0, following: 0 });
  });

  it("auto-accept (create accepted) increments both", async () => {
    await maintainFollowCountersHandler(testApp, undefined, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  it("pending create does not touch counters", async () => {
    await maintainFollowCountersHandler(testApp, undefined, pendingDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 0 });
    expect(await counters(other)).toEqual({ followers: 0, following: 0 });
  });

  it("skips a missing profile doc without throwing", async () => {
    await cleanup(other); // other has no public profile
    await maintainFollowCountersHandler(testApp, undefined, acceptedDoc);

    // requester still updated; missing other silently skipped.
    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    const otherSnap = await db()
      .collection("userPublicProfiles")
      .doc(other)
      .get();
    expect(otherSnap.exists).toBe(false); // not resurrected
  });
});
