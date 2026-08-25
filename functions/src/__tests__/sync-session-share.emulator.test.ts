/**
 * [EMULATOR-CI] Integration tests for syncSessionShareHandler against a REAL
 * Firestore emulator (paywall Fase 7, PR4).
 *
 * WHY BOTH SUITES EXIST. The LOCAL fake-store suite
 * (`sync-session-share.test.ts`) is the primary, always-runnable net: it is the
 * only one that can assert NEGATIVE facts — the exact list of doc operations —
 * which is precisely what the content guard is about ("did NOT write" is the
 * whole point). What it cannot do is prove the handler talks to Firestore
 * correctly. This suite is that half:
 *   - `FieldValue.serverTimestamp()` really resolves to a `Timestamp` on the
 *     stored doc, instead of staying an unresolved sentinel;
 *   - `snap.exists` / `snap.data()?.trainerId` behave against a real document,
 *     including the missing-doc case the ownership checks depend on;
 *   - the doc that lands is shaped the way firestore.rules reads it — three
 *     read clauses resolve `session_shares/{athleteId}.trainerId`
 *     (~1471 sessions, ~1485 setLogs, ~1727 measurements).
 *
 * Requires the Firebase Firestore emulator (Java 21+) — NOT runnable in this
 * environment locally (Java <21 here). Runs in CI via:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand"
 *
 * `--runInBand` matters: `session_shares/{athleteId}` is ONE doc per athlete and
 * these tests assert absolute state on it across a sequence of handler calls.
 * The athlete id is suite-local so no other file writes the same doc.
 *
 * Pattern mirrors promote-link.emulator.test.ts (Admin SDK against
 * `FIRESTORE_EMULATOR_HOST`, named test app, per-test seed/cleanup).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "sync-session-share-emulator-test");
});

afterAll(async () => {
  await testApp.delete();
});

import { syncSessionShareHandler } from "../sync-session-share";

const db = () => admin.firestore(testApp);

const TRAINER_A = "emu-share-trainer-A";
const TRAINER_B = "emu-share-trainer-B";
/** Suite-local so no other emulator suite writes this same session_shares doc. */
const ATHLETE = "emu-share-athlete-1";

function link(
  status: string,
  trainerId = TRAINER_A,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return { trainerId, athleteId: ATHLETE, status, ...extra };
}

/** The shape `sync-entitlements.ts` writes: status untouched, paywall fields added. */
function blockedBySweep(status: string, trainerId = TRAINER_A): Record<string, unknown> {
  return link(status, trainerId, {
    entitlement: "blocked",
    blockedAt: admin.firestore.Timestamp.now(),
    blockedReason: "over-limit",
  });
}

async function getShare(): Promise<admin.firestore.DocumentData | undefined> {
  const snap = await db().collection("session_shares").doc(ATHLETE).get();
  return snap.exists ? snap.data() : undefined;
}

async function seedShare(trainerId: string): Promise<void> {
  await db()
    .collection("session_shares")
    .doc(ATHLETE)
    .set({ trainerId, updatedAt: admin.firestore.Timestamp.now() });
}

async function cleanupShare(): Promise<void> {
  await db()
    .collection("session_shares")
    .doc(ATHLETE)
    .delete()
    .catch(() => undefined);
}

// ---------------------------------------------------------------------------
// Grant — real transition into `active`
// ---------------------------------------------------------------------------

describe("[EMULATOR-CI] transition into active → share written to real Firestore", () => {
  afterEach(cleanupShare);

  it("creates session_shares/{athleteId} with trainerId and a RESOLVED serverTimestamp", async () => {
    await syncSessionShareHandler(testApp, link("pending"), link("active"));

    const share = await getShare();
    expect(share).toBeDefined();
    expect(share?.trainerId).toBe(TRAINER_A);
    // The fake store cannot check this: it keeps the sentinel object verbatim.
    // Against real Firestore the field must have RESOLVED, otherwise the doc
    // would carry an unusable placeholder.
    expect(share?.updatedAt).toBeInstanceOf(admin.firestore.Timestamp);
  });

  it("overwrites an existing share from the same trainer when the link goes active", async () => {
    await seedShare(TRAINER_A);

    await syncSessionShareHandler(testApp, link("pending"), link("active"));

    expect((await getShare())?.trainerId).toBe(TRAINER_A);
  });

  it("takes the share over from another trainer on a real promotion", async () => {
    await seedShare(TRAINER_B);

    await syncSessionShareHandler(
      testApp,
      link("pending", TRAINER_A),
      link("active", TRAINER_A),
    );

    expect((await getShare())?.trainerId).toBe(TRAINER_A);
  });
});

// ---------------------------------------------------------------------------
// No transition — the content guard, round-tripped
// ---------------------------------------------------------------------------

describe("[EMULATOR-CI] active → active (no transition) → guarded by content", () => {
  afterEach(cleanupShare);

  it("does not steal a share that a real doc says belongs to another trainer", async () => {
    await seedShare(TRAINER_B);

    await syncSessionShareHandler(
      testApp,
      link("active", TRAINER_A),
      blockedBySweep("active", TRAINER_A),
    );

    expect((await getShare())?.trainerId).toBe(TRAINER_B);
  });

  it("rebuilds the share when the real doc is MISSING", async () => {
    // Nothing seeded: `snap.exists` is false against real Firestore, which is
    // the branch the repair depends on.
    await syncSessionShareHandler(testApp, link("active"), link("active"));

    const share = await getShare();
    expect(share?.trainerId).toBe(TRAINER_A);
    expect(share?.updatedAt).toBeInstanceOf(admin.firestore.Timestamp);
  });

  it("leaves an already-correct share in place", async () => {
    await seedShare(TRAINER_A);
    const before = (await getShare())?.updatedAt as admin.firestore.Timestamp;

    await syncSessionShareHandler(testApp, link("active"), link("active"));

    const after = (await getShare())?.updatedAt as admin.firestore.Timestamp;
    expect(after.isEqual(before)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Revoke — status left `active`, or the doc is gone
// ---------------------------------------------------------------------------

describe("[EMULATOR-CI] leaving active → share removed when it belongs to this trainer", () => {
  beforeEach(() => seedShare(TRAINER_A));
  afterEach(cleanupShare);

  it("removes the share when status changes to terminated", async () => {
    await syncSessionShareHandler(testApp, link("active"), link("terminated"));

    expect(await getShare()).toBeUndefined();
  });

  it("removes the share when status changes to paused", async () => {
    await syncSessionShareHandler(testApp, link("active"), link("paused"));

    expect(await getShare()).toBeUndefined();
  });

  it("removes the share when the link document is deleted", async () => {
    await syncSessionShareHandler(testApp, link("active"), undefined);

    expect(await getShare()).toBeUndefined();
  });
});

describe("[EMULATOR-CI] leaving active but the share belongs to another trainer → NOT removed", () => {
  beforeEach(() => seedShare(TRAINER_B));
  afterEach(cleanupShare);

  it("leaves the share untouched when this link is terminated", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active", TRAINER_A),
      link("terminated", TRAINER_A),
    );

    expect((await getShare())?.trainerId).toBe(TRAINER_B);
  });

  it("leaves the share untouched when this link is deleted", async () => {
    await syncSessionShareHandler(testApp, link("active", TRAINER_A), undefined);

    expect((await getShare())?.trainerId).toBe(TRAINER_B);
  });
});

// ---------------------------------------------------------------------------
// Sequences — several events over the SAME real document
// ---------------------------------------------------------------------------

describe("[EMULATOR-CI] sequences over the same session_shares doc", () => {
  afterEach(cleanupShare);

  it("the full robbery: the sweep on PF1's link never moves PF2's share", async () => {
    // Athlete with two trainers, both links active. PF1 goes over its plan
    // limit and the entitlement sweep stamps `entitlement: 'blocked'` on PF1's
    // link — a write that changes no status. PF2, paid up, must keep the
    // athlete's sessions/setLogs/measurements.
    await syncSessionShareHandler(
      testApp,
      link("pending", TRAINER_A),
      link("active", TRAINER_A),
    );
    expect((await getShare())?.trainerId).toBe(TRAINER_A);

    await syncSessionShareHandler(
      testApp,
      link("pending", TRAINER_B),
      link("active", TRAINER_B),
    );
    expect((await getShare())?.trainerId).toBe(TRAINER_B);

    await syncSessionShareHandler(
      testApp,
      link("active", TRAINER_A),
      blockedBySweep("active", TRAINER_A),
    );
    expect((await getShare())?.trainerId).toBe(TRAINER_B);

    // Enforcement re-runs the sweep — idempotent.
    await syncSessionShareHandler(
      testApp,
      blockedBySweep("active", TRAINER_A),
      blockedBySweep("active", TRAINER_A),
    );
    expect((await getShare())?.trainerId).toBe(TRAINER_B);
  });

  it("terminating an OLD link of the same pair is repaired by the live one", async () => {
    // firestore.rules allows several historical links per trainer/athlete pair
    // (~473). Terminating the old one deletes the share the NEW, active link of
    // the SAME trainer needs — the trainerId check cannot tell them apart. The
    // content guard on the grant path is what puts it back.
    await syncSessionShareHandler(testApp, link("pending"), link("active"));
    expect((await getShare())?.trainerId).toBe(TRAINER_A);

    await syncSessionShareHandler(testApp, link("active"), link("terminated"));
    expect(await getShare()).toBeUndefined();

    await syncSessionShareHandler(testApp, link("active"), link("active"));
    expect((await getShare())?.trainerId).toBe(TRAINER_A);
  });

  it("revoke then re-grant: pause, resume, terminate, re-accept", async () => {
    await syncSessionShareHandler(testApp, link("pending"), link("active"));
    expect((await getShare())?.trainerId).toBe(TRAINER_A);

    await syncSessionShareHandler(testApp, link("active"), link("paused"));
    expect(await getShare()).toBeUndefined();

    // A write while paused must not resurrect it.
    await syncSessionShareHandler(testApp, link("paused"), link("paused"));
    expect(await getShare()).toBeUndefined();

    await syncSessionShareHandler(testApp, link("paused"), link("active"));
    expect((await getShare())?.trainerId).toBe(TRAINER_A);

    await syncSessionShareHandler(testApp, link("active"), link("terminated"));
    expect(await getShare()).toBeUndefined();

    await syncSessionShareHandler(testApp, link("pending"), link("active"));
    expect((await getShare())?.trainerId).toBe(TRAINER_A);
  });
});

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

describe("[EMULATOR-CI] edge cases", () => {
  afterEach(cleanupShare);

  it("is a no-op when the status is not active and no share doc exists", async () => {
    await syncSessionShareHandler(testApp, link("active"), link("terminated"));

    expect(await getShare()).toBeUndefined();
  });

  it("skips gracefully when trainerId is missing", async () => {
    await expect(
      syncSessionShareHandler(testApp, undefined, {
        athleteId: ATHLETE,
        status: "active",
      }),
    ).resolves.toBeUndefined();

    expect(await getShare()).toBeUndefined();
  });

  it("skips gracefully when athleteId is missing", async () => {
    await expect(
      syncSessionShareHandler(testApp, undefined, {
        trainerId: TRAINER_A,
        status: "active",
      }),
    ).resolves.toBeUndefined();
  });
});
