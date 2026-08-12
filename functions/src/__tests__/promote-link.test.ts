/**
 * Unit tests for syncTrainerLoad / promotionDenialReason (paywall Fase 7,
 * PR4). LOCAL — no emulator. Uses the hand-rolled FakeTx firestore double
 * (design D-6) so the reads-before-writes invariant is verified without
 * Java 21 / the Firestore emulator.
 */

// `admin.firestore` is both a factory AND the namespace holding the
// `Timestamp`/`FieldValue` sentinels the gate writes. The double has to carry
// both, or the write path silently can't be exercised.
jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  // Stable sentinel: `FieldValue.delete()` must be reference-equal across
  // calls so tests can assert the delete marker itself, like the real SDK.
  const deleteSentinel = { __fakeFieldValue: "delete" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms }),
  };
  firestore.FieldValue = { delete: () => deleteSentinel };
  return { firestore };
});

import * as admin from "firebase-admin";
import {
  createFakeFirestore,
  FakeDoc,
  FakeFirestoreState,
} from "./helpers/fake-tx-firestore";
import {
  promotionDenialReason,
  syncTrainerLoad,
} from "../subscriptions/promote-link";

function install(seed: Partial<FakeFirestoreState>): FakeFirestoreState {
  const { db, state } = createFakeFirestore(seed);
  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const app = {} as admin.app.App;

const link = (overrides: Record<string, unknown> = {}) => ({
  trainerId: "trainer-1",
  athleteId: "athlete-1",
  status: "pending",
  entitlement: "entitled",
  ...overrides,
});

const plan1Active = { tier: "plan1", status: "active" };

describe("syncTrainerLoad — precondition ladder", () => {
  beforeEach(() => jest.clearAllMocks());

  it("not-found — link doesn't exist", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "missing", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("permission-denied — caller isn't the link's trainer", async () => {
    install({
      trainer_links: { L1: link({ trainerId: "trainer-1" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "someone-else", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("failed-precondition/wrong-status — status doesn't match expectedFromStatus", async () => {
    install({
      trainer_links: { L1: link({ status: "terminated" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition", message: "wrong-status" });
  });

  it("failed-precondition/link-blocked — target link is entitlement:blocked", async () => {
    install({
      trainer_links: { L1: link({ status: "pending", entitlement: "blocked" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition", message: "link-blocked" });
  });

  it("already-active — success no-op, promoted:false, link untouched", async () => {
    const state = install({
      trainer_links: { L1: link({ status: "active" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });
    expect(result.promoted).toBe(false);
    expect(state.trainer_links.L1.status).toBe("active");
  });

  it("not-found — trainer profile doc missing", async () => {
    install({
      trainer_links: { L1: link() },
      users: {},
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("invalid-argument — promotion missing linkId/callerUid", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("syncTrainerLoad — gate boundary (strict <=)", () => {
  beforeEach(() => jest.clearAllMocks());

  function seedActiveLinks(count: number, trainerId = "trainer-1") {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < count; i++) {
      links[`active-${i}`] = link({ trainerId, athleteId: `a${i}`, status: "active" });
    }
    return links;
  }

  it("6.0 + accept(1.0) = 7.0 at plan1(7) — passes, writes active + weightedLoad", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(6), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });

    expect(result).toMatchObject({ trainerId: "trainer-1", weightedLoad: 7.0, limit: 7, promoted: true });
    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.users["trainer-1"].weightedLoad).toBe(7.0);
  });

  it("7.0 + accept(1.0) = 8.0 at plan1(7) — blocks resource-exhausted, nothing written", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(7), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "plan-limit", tier: "plan1", limit: 7, currentLoad: 7.0, projectedLoad: 8.0 },
    });

    expect(state.trainer_links.L1.status).toBe("pending");
    expect(state.users["trainer-1"].weightedLoad).toBeUndefined();
  });

  // ── Transition-specific link fields ─────────────────────────────────────
  //
  // The gate REPLACES TrainerLinkRepository.accept()/resume() (slices 2-3),
  // so it must write everything those methods wrote — not just `status`.
  // `accept()` stamped `acceptedAt`; `resume()` cleared `pausedAt`. Dropping
  // either is a SILENT data regression: `trainer_coach_view.dart` renders
  // `acceptedAt ?? requestedAt`, so a missing stamp shows the request date as
  // the start date instead of failing loudly.

  it("accept stamps acceptedAt (replaces repository.accept)", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(2), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      nowMs: 1_700_000_000_000,
    });

    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.trainer_links.L1.acceptedAt).toEqual(
      admin.firestore.Timestamp.fromMillis(1_700_000_000_000),
    );
  });

  it("resume clears pausedAt and does NOT restamp acceptedAt (replaces repository.resume)", async () => {
    const originalAcceptedAt = admin.firestore.Timestamp.fromMillis(1_600_000_000_000);
    const state = install({
      trainer_links: {
        ...seedActiveLinks(2),
        L1: link({
          athleteId: "paused-1",
          status: "paused",
          acceptedAt: originalAcceptedAt,
          pausedAt: admin.firestore.Timestamp.fromMillis(1_650_000_000_000),
        }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      nowMs: 1_700_000_000_000,
    });

    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.trainer_links.L1.pausedAt).toBe(admin.firestore.FieldValue.delete());
    // Preserved — a resumed link is NOT a new one (repository.resume contract).
    expect(state.trainer_links.L1.acceptedAt).toEqual(originalAcceptedAt);
  });

  it("reconciliation (promotion:null) touches no link fields", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(2), L1: link({ status: "paused" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, { trainerId: "trainer-1", promotion: null });

    expect(state.trainer_links.L1.status).toBe("paused");
    expect(state.trainer_links.L1.acceptedAt).toBeUndefined();
    expect(state.trainer_links.L1.pausedAt).toBeUndefined();
  });

  it("resume: 6.5 + resume(0.5) = 7.0 at plan1(7) — passes", async () => {
    install({
      trainer_links: {
        ...seedActiveLinks(6),
        L1: link({ athleteId: "paused-1", status: "paused" }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
    });

    expect(result).toMatchObject({ weightedLoad: 7.0, limit: 7, promoted: true });
  });

  it("resume: two paused, resume one at load 7.0 → projects 7.5 — blocks", async () => {
    install({
      trainer_links: {
        ...seedActiveLinks(6),
        L1: link({ athleteId: "paused-1", status: "paused" }),
        L2: link({ athleteId: "paused-2", status: "paused" }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      }),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
  });
});

describe("syncTrainerLoad — reconciliation (promotion: null)", () => {
  beforeEach(() => jest.clearAllMocks());

  it("recomputes and writes regardless of limit — never blocks, no promotion applied", async () => {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < 15; i++) {
      links[`p${i}`] = link({ athleteId: `a${i}`, status: "paused" });
    }
    const state = install({
      trainer_links: links,
      users: { "trainer-1": { subscription: plan1Active } }, // limit 7, real load 7.5 > limit
    });

    const result = await syncTrainerLoad(app, { trainerId: "trainer-1", promotion: null });

    expect(result).toMatchObject({ trainerId: "trainer-1", weightedLoad: 7.5, limit: 7, promoted: false });
    expect(state.users["trainer-1"].weightedLoad).toBe(7.5);
  });

  it("invalid-argument — trainerId missing with no promotion", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, { promotion: null }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("promotionDenialReason", () => {
  it("plan-limit — limit equals the subscription's nominal tier limit", () => {
    expect(promotionDenialReason({ tier: "plan1", status: "active" }, 7)).toBe("plan-limit");
  });

  it("subscription-inactive — limit is below the nominal tier limit (lapsed paid sub)", () => {
    // plan2 nominal = 15, but effectiveWeightLimit degraded to Free (2) because
    // e.g. status is 'pending'/'paused' — a paid trainer without entitlement.
    expect(promotionDenialReason({ tier: "plan2", status: "pending" }, 2)).toBe("subscription-inactive");
  });

  it("free-tier edge — no subscription, limit equals Free's own nominal (2) → plan-limit", () => {
    expect(promotionDenialReason(null, 2)).toBe("plan-limit");
  });
});
