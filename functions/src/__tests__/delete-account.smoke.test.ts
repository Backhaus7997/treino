/**
 * Smoke / integration tests for the deleteAccount handler.
 * Run against Firebase Local Emulator (Firestore + Auth).
 *
 * SCENARIOS covered:
 *   SCENARIO-533 — CF callable by authenticated client (REQ-ACCDEL-CF-001)
 *   SCENARIO-534 — Spoofed uid rejected (REQ-ACCDEL-CF-002)
 *   SCENARIO-549 — Auth user deleted after success (REQ-ACCDEL-CF-012)
 *   SCENARIO-547 — Audit log records started then success (REQ-ACCDEL-CF-011)
 *   SCENARIO-551 — CF returns structured success response (REQ-ACCDEL-CF-014)
 *
 * Strategy: invoke runDeleteAccount (core logic) and deleteAccountHandler (callable
 * wrapper guard checks) directly against the emulator-backed named app.
 */

import * as admin from "firebase-admin";

// Point Admin SDK to emulators — must be set before any firebase-admin import
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";
process.env.FUNCTIONS_EMULATOR = "true";

import { wrapV2 } from "firebase-functions-test/lib/v2";
import { CallableRequest } from "firebase-functions/v2/https";
import { deleteAccountHandler, runDeleteAccount } from "../delete-account";
import { DeleteAccountRequest, DeleteAccountResponse } from "../types";

const projectConfig = { projectId: "treino-dev" };

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
    admin.firestore(smokeApp).collection("users").doc(uid).delete().catch(() => undefined),
    admin.firestore(smokeApp).collection("audit_log").doc(uid).delete().catch(() => undefined),
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
