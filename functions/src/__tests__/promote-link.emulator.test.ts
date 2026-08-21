/**
 * [EMULATOR-CI] Integration tests for syncTrainerLoad against a REAL
 * Firestore emulator — reads-before-writes ordering + concurrency (paywall
 * Fase 7, PR4, design D-6, tasks 1.7-1.8).
 *
 * The LOCAL fake-tx suite (promote-link.test.ts) is the primary,
 * always-runnable net for the reads-before-writes invariant — it throws
 * synchronously if `tx.get()` is ever called after a write. This suite is
 * the CONFIRMATION against real Firestore transaction semantics, plus the
 * one thing the fake genuinely cannot simulate: actual optimistic-concurrency
 * retries across two overlapping transactions.
 *
 * Requires the Firebase Firestore emulator (Java 21+) — NOT runnable in this
 * environment locally (Java <21 here). Runs in CI via:
 *   firebase emulators:exec --only firestore \
 *     "npx jest --forceExit --runInBand src/__tests__/promote-link.emulator.test.ts"
 *
 * `--runInBand` matters for the concurrency test: it asserts on absolute
 * document state after `Promise.allSettled`, which must not interleave with
 * other test files' writes to the same emulator instance.
 *
 * Pattern mirrors cleanup-assigned-plans.test.ts (admin SDK against
 * `FIRESTORE_EMULATOR_HOST`, named test app, per-test seed/cleanup).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-rules-test";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-rules-test" }, "promote-link-emulator-test");
});

afterAll(async () => {
  await testApp.delete();
});

import { syncTrainerLoad } from "../subscriptions/promote-link";

const db = () => admin.firestore(testApp);

const TRAINER = "emu-trainer-1";

function link(id: string, status: string, extra: Record<string, unknown> = {}) {
  return {
    trainerId: TRAINER,
    athleteId: id,
    status,
    entitlement: "entitled",
    ...extra,
  };
}

async function seed(links: Record<string, Record<string, unknown>>): Promise<void> {
  const batch = db().batch();
  batch.set(db().collection("users").doc(TRAINER), {
    subscription: { tier: "plan1", status: "active" },
  });
  for (const [id, data] of Object.entries(links)) {
    batch.set(db().collection("trainer_links").doc(id), data);
  }
  await batch.commit();
}

async function cleanup(linkIds: string[]): Promise<void> {
  const batch = db().batch();
  batch.delete(db().collection("users").doc(TRAINER));
  for (const id of linkIds) {
    batch.delete(db().collection("trainer_links").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("[EMULATOR-CI] syncTrainerLoad — reads-before-writes vs real Firestore", () => {
  const ACTIVE_IDS = ["a1", "a2", "a3", "a4", "a5", "a6"];
  const PENDING_ID = "pending-1";

  beforeEach(() =>
    seed({
      ...Object.fromEntries(ACTIVE_IDS.map((id) => [id, link(id, "active")])),
      [PENDING_ID]: link(PENDING_ID, "pending"),
    }),
  );
  afterEach(() => cleanup([...ACTIVE_IDS, PENDING_ID]));

  it("accepts a single promotion end-to-end (6.0 -> 7.0 at plan1(7))", async () => {
    const result = await syncTrainerLoad(testApp, {
      promotion: { linkId: PENDING_ID, callerUid: TRAINER, expectedFromStatus: "pending" },
    });

    expect(result).toMatchObject({ weightedLoad: 7.0, limit: 7, promoted: true });

    const linkSnap = await db().collection("trainer_links").doc(PENDING_ID).get();
    expect(linkSnap.data()?.status).toBe("active");

    const trainerSnap = await db().collection("users").doc(TRAINER).get();
    expect(trainerSnap.data()?.weightedLoad).toBe(7.0);
  });
});

describe("[EMULATOR-CI] syncTrainerLoad — concurrency (optimistic-lock retry)", () => {
  const ACTIVE_IDS = ["c1", "c2", "c3", "c4", "c5", "c6"];
  const PENDING_1 = "concurrent-pending-1";
  const PENDING_2 = "concurrent-pending-2";

  beforeEach(() =>
    seed({
      ...Object.fromEntries(ACTIVE_IDS.map((id) => [id, link(id, "active")])),
      [PENDING_1]: link(PENDING_1, "pending"),
      [PENDING_2]: link(PENDING_2, "pending"),
    }),
  );
  afterEach(() => cleanup([...ACTIVE_IDS, PENDING_1, PENDING_2]));

  it(
    "exactly one of two concurrent accepts commits; the loser retries, re-reads, and " +
      "correctly rejects resource-exhausted — final load is 7, never 8",
    async () => {
      // plan1(7): 6.0 active + either pending pushes to 7.0 (passes) or, once
      // the winner commits, 7.0 + the other pending projects 8.0 (blocked).
      // NOT flaky either way: with real contention the Admin SDK retries the
      // loser, which re-reads the now-committed 7.0 and projects 8.0 > 7;
      // without contention (transactions don't overlap) the second call
      // simply reads 7.0 after the first already committed and fails the
      // same way. The assertion is independent of timing — see design D-6.
      const results = await Promise.allSettled([
        syncTrainerLoad(testApp, {
          promotion: { linkId: PENDING_1, callerUid: TRAINER, expectedFromStatus: "pending" },
        }),
        syncTrainerLoad(testApp, {
          promotion: { linkId: PENDING_2, callerUid: TRAINER, expectedFromStatus: "pending" },
        }),
      ]);

      const fulfilled = results.filter((r) => r.status === "fulfilled");
      const rejected = results.filter((r) => r.status === "rejected");

      expect(fulfilled).toHaveLength(1);
      expect(rejected).toHaveLength(1);
      expect((rejected[0] as PromiseRejectedResult).reason).toMatchObject({
        code: "resource-exhausted",
      });

      const trainerSnap = await db().collection("users").doc(TRAINER).get();
      expect(trainerSnap.data()?.weightedLoad).toBe(7.0);
    },
  );
});
