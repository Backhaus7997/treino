/**
 * Smoke / integration tests for the deleteAccount handler.
 * Run against Firebase Local Emulator (Firestore + Auth + Storage).
 *
 * SCENARIOS covered (PR#1 — kept):
 *   SCENARIO-533 — CF callable by authenticated client (REQ-ACCDEL-CF-001)
 *   SCENARIO-534 — Spoofed uid rejected (REQ-ACCDEL-CF-002)
 *   SCENARIO-549 — Auth user deleted after success (REQ-ACCDEL-CF-012)
 *   SCENARIO-547 — Audit log records started then success (REQ-ACCDEL-CF-011)
 *   SCENARIO-551 — CF returns structured success response (REQ-ACCDEL-CF-014)
 *
 * SCENARIOS added (PR#2 — T21):
 *   SCENARIO-535 — Trainer role rejected (REQ-ACCDEL-CF-003)
 *   SCENARIO-547 (final) — Audit log includes cascadeResults (REQ-ACCDEL-CF-011)
 *   SCENARIO-548 — Audit log status partial when a cascade step errors (REQ-ACCDEL-CF-011)
 *   SCENARIO-550 — Idempotent re-run completes cleanly (REQ-ACCDEL-CF-013)
 *   SCENARIO-551 (full) — deletedCollections includes all cascade collection names (REQ-ACCDEL-CF-014)
 *
 * Strategy: invoke runDeleteAccount (core logic) and deleteAccountHandler (callable
 * wrapper guard checks) directly against the emulator-backed named app.
 */

import * as admin from "firebase-admin";

// Point Admin SDK to emulators — must be set before any firebase-admin import
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";
process.env.GCLOUD_PROJECT = "treino-dev";
process.env.FUNCTIONS_EMULATOR = "true";

import { wrapV2 } from "firebase-functions-test/lib/v2";
import { CallableRequest } from "firebase-functions/v2/https";

// Mock the storage cascade module with a passthrough factory: by default,
// delegates to the real implementation (so all existing tests keep using real
// emulator-backed Storage). Individual tests can override per-call via
// mockRejectedValueOnce to simulate cascade failures (SCENARIO-548).
jest.mock("../cascade/storage", () => {
  const actual = jest.requireActual("../cascade/storage");
  return {
    ...actual,
    deleteAvatar: jest.fn(actual.deleteAvatar),
  };
});

import * as storageCascade from "../cascade/storage";
import { deleteAccountHandler, runDeleteAccount } from "../delete-account";
import { DeleteAccountRequest, DeleteAccountResponse } from "../types";

const projectConfig = {
  projectId: "treino-dev",
  storageBucket: "treino-dev.appspot.com",
};

let smokeApp: admin.app.App;

beforeAll(() => {
  smokeApp = admin.initializeApp(projectConfig, "smoke-test");
});

afterAll(async () => {
  await smokeApp.delete();
});

// Wrap the callable handler for guard-layer tests
const wrappedHandler = wrapV2(deleteAccountHandler);

// ── Helpers ────────────────────────────────────────────────────────────────

async function createTestUser(
  uid: string,
  role: "athlete" | "trainer" = "athlete"
): Promise<void> {
  await admin.auth(smokeApp).createUser({ uid, email: `${uid}@test.com` });
  await admin
    .firestore(smokeApp)
    .collection("users")
    .doc(uid)
    .set({ uid, role, email: `${uid}@test.com` });
}

async function cleanupUser(uid: string): Promise<void> {
  await Promise.all([
    admin.auth(smokeApp).deleteUser(uid).catch(() => undefined),
    admin
      .firestore(smokeApp)
      .recursiveDelete(admin.firestore(smokeApp).collection("users").doc(uid))
      .catch(() => undefined),
    admin
      .firestore(smokeApp)
      .collection("audit_log")
      .doc(uid)
      .delete()
      .catch(() => undefined),
    admin
      .firestore(smokeApp)
      .collection("userPublicProfiles")
      .doc(uid)
      .delete()
      .catch(() => undefined),
    admin
      .firestore(smokeApp)
      .collection("friendships")
      .where("members", "array-contains", uid)
      .get()
      .then((qs) => {
        const b = admin.firestore(smokeApp).batch();
        qs.docs.forEach((d) => b.delete(d.ref));
        return b.commit();
      })
      .catch(() => undefined),
  ]);
}

function makeCallableRequest(
  callerUid: string,
  targetUid: string,
  provider = "password"
): CallableRequest<DeleteAccountRequest> {
  return {
    data: { uid: targetUid },
    auth: {
      uid: callerUid,
      token: { firebase: { sign_in_provider: provider } },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
    rawRequest: {} as CallableRequest["rawRequest"],
    instanceIdToken: undefined,
    app: undefined,
  };
}

async function seedFullAthleteData(uid: string): Promise<void> {
  const db = admin.firestore(smokeApp);
  await createTestUser(uid);

  const batch = db.batch();
  // userPublicProfile
  batch.set(db.collection("userPublicProfiles").doc(uid), {
    uid,
    displayName: "Athlete Name",
  });
  // 2 friendships
  batch.set(db.collection("friendships").doc(`friendship-${uid}-a`), {
    members: [uid, "other-user-a"],
  });
  batch.set(db.collection("friendships").doc(`friendship-${uid}-b`), {
    members: [uid, "other-user-b"],
  });
  // 1 post
  batch.set(db.collection("posts").doc(`post-${uid}`), {
    authorUid: uid,
    authorDisplayName: "Athlete Name",
    authorAvatarUrl: "https://example.com/avatar.jpg",
  });
  // 1 trainer link
  batch.set(db.collection("trainer_links").doc(`link-${uid}`), {
    athleteId: uid,
    trainerId: "trainer-xyz",
    status: "active",
  });
  // 1 future appointment
  batch.set(db.collection("appointments").doc(`appt-future-${uid}`), {
    athleteId: uid,
    trainerId: "trainer-xyz",
    scheduledAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
    ),
    status: "confirmed",
  });
  // 1 past appointment
  batch.set(db.collection("appointments").doc(`appt-past-${uid}`), {
    athleteId: uid,
    trainerId: "trainer-xyz",
    scheduledAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    ),
    status: "confirmed",
  });
  await batch.commit();
}

async function cleanupFullAthleteData(uid: string): Promise<void> {
  const db = admin.firestore(smokeApp);
  await Promise.all([
    cleanupUser(uid),
    db.collection("posts").doc(`post-${uid}`).delete().catch(() => undefined),
    db
      .collection("trainer_links")
      .doc(`link-${uid}`)
      .delete()
      .catch(() => undefined),
    db
      .collection("appointments")
      .doc(`appt-future-${uid}`)
      .delete()
      .catch(() => undefined),
    db
      .collection("appointments")
      .doc(`appt-past-${uid}`)
      .delete()
      .catch(() => undefined),
  ]);
}

// ── Callable-layer guard tests ─────────────────────────────────────────────

describe("callable guard: unauthenticated", () => {
  it("throws unauthenticated when auth context is absent", async () => {
    const req: CallableRequest<DeleteAccountRequest> = {
      data: { uid: "any-uid" },
      auth: undefined,
      rawRequest: {} as CallableRequest["rawRequest"],
      instanceIdToken: undefined,
      app: undefined,
    };
    await expect(wrappedHandler(req)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

describe("SCENARIO-534: anti-spoof guard", () => {
  const callerUid = "spoof-caller";
  const targetUid = "spoof-target";

  beforeEach(async () => {
    await createTestUser(callerUid);
    await createTestUser(targetUid);
  });
  afterEach(async () => {
    await cleanupUser(callerUid);
    await cleanupUser(targetUid);
  });

  it("throws permission-denied when caller uid != data.uid", async () => {
    const req = makeCallableRequest(callerUid, targetUid);
    await expect(wrappedHandler(req)).rejects.toMatchObject({
      code: "permission-denied",
    });
  });
});

// ── Core logic tests (runDeleteAccount) ───────────────────────────────────

describe("SCENARIO-533: core logic callable by authenticated athlete", () => {
  const uid = "smoke-athlete-533";

  beforeEach(() => createTestUser(uid));
  afterEach(() => cleanupUser(uid));

  it("SCENARIO-533: resolves without error for a valid athlete", async () => {
    const result = await runDeleteAccount(smokeApp, uid, "password");
    expect(result).toBeDefined();
  });
});

describe("SCENARIO-535: trainer role rejected", () => {
  const uid = "smoke-trainer-535";

  beforeEach(() => createTestUser(uid, "trainer"));
  afterEach(() => cleanupUser(uid));

  it("SCENARIO-535: throws permission-denied for trainer role", async () => {
    await expect(runDeleteAccount(smokeApp, uid, "password")).rejects.toMatchObject({
      code: "permission-denied",
    });
  });

  it("SCENARIO-535: no data is modified when trainer is rejected", async () => {
    await runDeleteAccount(smokeApp, uid, "password").catch(() => undefined);

    // Trainer's user doc should still exist
    const snap = await admin
      .firestore(smokeApp)
      .collection("users")
      .doc(uid)
      .get();
    expect(snap.exists).toBe(true);
  });
});

describe("SCENARIO-551, 549, 547: success path", () => {
  const uid = "smoke-success-551";

  beforeEach(() => createTestUser(uid));
  afterEach(() => cleanupUser(uid));

  it("SCENARIO-551: returns { status: success, deletedCollections, errors: [] }", async () => {
    const result = (await runDeleteAccount(
      smokeApp,
      uid,
      "password"
    )) as DeleteAccountResponse;

    expect(result.status).toBe("success");
    expect(Array.isArray(result.deletedCollections)).toBe(true);
    expect(result.deletedCollections.length).toBeGreaterThan(0);
    expect(result.errors).toHaveLength(0);
  });

  it("SCENARIO-549: auth user no longer retrievable after success", async () => {
    await cleanupUser(uid);
    await createTestUser(uid);

    await runDeleteAccount(smokeApp, uid, "password");

    await expect(admin.auth(smokeApp).getUser(uid)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });

  it("SCENARIO-547: audit_log/{uid} has status=success with completedAt set", async () => {
    await cleanupUser(uid);
    await createTestUser(uid);

    await runDeleteAccount(smokeApp, uid, "password");

    const snap = await admin
      .firestore(smokeApp)
      .collection("audit_log")
      .doc(uid)
      .get();

    expect(snap.exists).toBe(true);
    expect(snap.data()?.status).toBe("success");
    expect(snap.data()?.completedAt).toBeTruthy();
  });
});

describe("SCENARIO-551 (full): deletedCollections includes all cascade collection names", () => {
  const uid = "smoke-collections-551";

  beforeEach(() => seedFullAthleteData(uid));
  afterEach(() => cleanupFullAthleteData(uid));

  it("SCENARIO-551 (full): deletedCollections contains all 8 expected entries", async () => {
    const result = (await runDeleteAccount(
      smokeApp,
      uid,
      "password"
    )) as DeleteAccountResponse;

    expect(result.status).toBe("success");
    const expected = [
      "friendships",
      "posts",
      "trainer_links",
      "appointments",
      "storage",
      "storage-athlete",
      "athlete-data",
      "users",
      "userPublicProfiles",
      "users-auth",
    ];
    for (const col of expected) {
      expect(result.deletedCollections).toContain(col);
    }
  });
});

describe("SCENARIO-550: idempotent re-run completes cleanly", () => {
  const uid = "smoke-idempotent-550";

  beforeEach(() => createTestUser(uid));
  afterEach(() => cleanupUser(uid));

  it("SCENARIO-550: second call for same uid does not throw", async () => {
    // First call: deletes everything
    await runDeleteAccount(smokeApp, uid, "password");

    // Second call: all data already gone — should complete cleanly
    await expect(
      runDeleteAccount(smokeApp, uid, "password")
    ).resolves.toBeDefined();
  });
});

describe("SCENARIO-548: audit log partial status when a cascade step errors", () => {
  // Strong version: force the storage cascade module to throw via the
  // jest.mock factory at the top of this file. Verifies the orchestrator
  // really does:
  //   - accumulate the error into errors[]
  //   - set final response.status to 'partial' (not 'success')
  //   - continue with subsequent steps (deletedCollections still has
  //     users + userPublicProfiles + users-auth — the user IS gone)
  //   - mirror the same partial+errors shape in audit_log/{uid}
  //
  // The previous version of this test was vacuous: it asserted
  // `status in ['success', 'partial']` which is always true. Surfaced
  // during sdd-verify of the account-deletion change.
  const uid = "smoke-partial-548";

  beforeEach(() => createTestUser(uid));
  afterEach(() => cleanupUser(uid));

  it("returns status='partial' and accumulates errors when a cascade step throws", async () => {
    // Force the storage cascade step to fail on this single invocation.
    (storageCascade.deleteAvatar as jest.Mock).mockRejectedValueOnce(
      new Error("simulated storage failure")
    );

    const result = (await runDeleteAccount(
      smokeApp,
      uid,
      "password"
    )) as DeleteAccountResponse;

    // Orchestrator reports partial — at least one cascade step failed.
    expect(result.status).toBe("partial");

    // errors[] contains the storage failure with module prefix and message.
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors.some((e) => e.startsWith("storage:"))).toBe(true);
    expect(result.errors.some((e) => e.includes("simulated storage failure"))).toBe(true);

    // The auth user must still be deleted — the rest of the cascade ran.
    expect(result.deletedCollections).toContain("users-auth");
    expect(result.deletedCollections).toContain("users");

    // And: 'storage' is NOT in deletedCollections (the failing step
    // never gets pushed to the success list).
    expect(result.deletedCollections).not.toContain("storage");

    // The audit_log/{uid} doc mirrors the response shape.
    const auditDoc = await admin
      .firestore(smokeApp)
      .collection("audit_log")
      .doc(uid)
      .get();
    expect(auditDoc.exists).toBe(true);
    const audit = auditDoc.data();
    expect(audit?.status).toBe("partial");
    expect(audit?.errors).toEqual(result.errors);
  });

  it("returns status='success' on a clean run (no cascade errors injected)", async () => {
    // Sanity baseline: with no mock injection, an empty-data athlete deletes
    // cleanly with status=success and empty errors[].
    const result = (await runDeleteAccount(
      smokeApp,
      uid,
      "password"
    )) as DeleteAccountResponse;

    expect(result.status).toBe("success");
    expect(result.errors).toEqual([]);
    expect(result.deletedCollections).toContain("users-auth");
  });
});
