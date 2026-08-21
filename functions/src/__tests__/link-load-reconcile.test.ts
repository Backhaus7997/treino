/**
 * Unit tests for linkLoadReconcile / linkLoadReconcileHandler (paywall Fase
 * 7, PR4, tasks 1.9-1.10). LOCAL — no emulator, same FakeTx firestore double
 * as promote-link.test.ts (design D-6).
 *
 * Idempotent, full-recompute (no increments), error-safe: catches all
 * exceptions and never rethrows (mirrors link-aggregate.ts's
 * recomputeAthleteCount pattern) so a malformed doc or a missing
 * users/{trainerId} profile never triggers an Eventarc retry storm.
 */

jest.mock("firebase-admin", () => ({ firestore: jest.fn() }));

const warnSpy = jest.fn();
const infoSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: { warn: (...args: unknown[]) => warnSpy(...args), info: (...args: unknown[]) => infoSpy(...args) },
}));

import * as admin from "firebase-admin";
import {
  createFakeFirestore,
  FakeDoc,
  FakeFirestoreState,
} from "./helpers/fake-tx-firestore";
import { linkLoadReconcileHandler } from "../subscriptions/link-load-reconcile";

function install(seed: Partial<FakeFirestoreState>): FakeFirestoreState {
  const { db, state } = createFakeFirestore(seed);
  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const app = {} as admin.app.App;

const link = (athleteId: string, status: string, extra: Record<string, unknown> = {}): FakeDoc => ({
  trainerId: "trainer-1",
  athleteId,
  status,
  entitlement: "entitled",
  ...extra,
});

describe("linkLoadReconcileHandler", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("recomputes weightedLoad from the live link set (full recompute, not an increment)", async () => {
    const state = install({
      trainer_links: {
        a1: link("a1", "active"),
        a2: link("a2", "active"),
        p1: link("p1", "paused"),
      },
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" }, weightedLoad: 999 } },
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    expect(state.users["trainer-1"].weightedLoad).toBe(2.5);
  });

  it("is idempotent — running twice for equivalent state yields the same value, no drift", async () => {
    const state = install({
      trainer_links: { a1: link("a1", "active"), p1: link("p1", "paused") },
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } },
    });

    await linkLoadReconcileHandler(app, "trainer-1");
    const firstRun = state.users["trainer-1"].weightedLoad;
    await linkLoadReconcileHandler(app, "trainer-1");
    const secondRun = state.users["trainer-1"].weightedLoad;

    expect(firstRun).toBe(1.5);
    expect(secondRun).toBe(1.5);
  });

  it("missing users/{trainerId} doc — logs a warning and completes without throwing", async () => {
    install({
      trainer_links: { a1: link("a1", "active") },
      users: {}, // trainer profile absent
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
  });

  it("never rethrows on unexpected errors (error-safe, mirrors link-aggregate.ts)", async () => {
    (admin.firestore as unknown as jest.Mock).mockImplementation(() => {
      throw new Error("boom");
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
  });

  it("recomputes over the trainer's effective limit without ever blocking (display-only, not a gate)", async () => {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < 15; i++) links[`p${i}`] = link(`a${i}`, "paused");
    const state = install({
      trainer_links: links,
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } }, // limit 7, real load 7.5
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();
    expect(state.users["trainer-1"].weightedLoad).toBe(7.5);
  });
});
