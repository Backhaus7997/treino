/**
 * Smoke / integration tests for the deleteAccount callable.
 * Run against Firebase Local Emulator (Firestore + Auth + Functions).
 *
 * SCENARIOS covered:
 *   SCENARIO-533 — CF callable by authenticated client (REQ-ACCDEL-CF-001)
 *   SCENARIO-534 — Spoofed uid rejected (REQ-ACCDEL-CF-002)
 *   SCENARIO-549 — Auth user deleted after success (REQ-ACCDEL-CF-012)
 *   SCENARIO-547 — Audit log records started then success (REQ-ACCDEL-CF-011)
 *   SCENARIO-551 — CF returns structured success response (REQ-ACCDEL-CF-014)
 *
 * Strategy: import the handler function directly and invoke it with a
 * firebase-functions-test wrapped callable context. The Firestore and Auth
 * emulators are used for state verification.
 */

import * as admin from "firebase-admin";

// Point Admin SDK to emulators
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";
// Tell firebase-functions-test to run offline (unit test mode for the callable wrapper)
process.env.FUNCTIONS_EMULATOR = "true";

import functionsTest from "firebase-functions-test";
import { deleteAccountHandler } from "../delete-account";
import { DeleteAccountRequest, DeleteAccountResponse } from "../types";

const projectConfig = { projectId: "treino-dev" };
const testEnv = functionsTest(projectConfig, undefined);

let smokeApp: admin.app.App;

beforeAll(() => {
  smokeApp = admin.initializeApp(projectConfig, "smoke-test");
});

afterAll(async () => {
  testEnv.cleanup();
  await smokeApp.delete();
});

async function createTestUser(
  uid: string,
  role: "athlete" | "trainer" = "athlete"
): Promise<void> {
  // Create Auth user in emulator
  await admin.auth(smokeApp).createUser({ uid, email: `${uid}@test.com` });
  // Seed Firestore users doc
  await admin
    .firestore(smokeApp)
    .collection("users")
    .doc(uid)
    .set({ uid, role, email: `${uid}@test.com` });
}

async function deleteTestUser(uid: string): Promise<void> {
  try {
    await admin.auth(smokeApp).deleteUser(uid);
  } catch {
    // ignore not-found
  }
  try {
    await admin.firestore(smokeApp).collection("users").doc(uid).delete();
  } catch {
    // ignore
  }
  try {
    await admin
      .firestore(smokeApp)
      .collection("audit_log")
      .doc(uid)
      .delete();
  } catch {
    // ignore
  }
}

// Wrap the handler for callable invocation
const wrappedDeleteAccount = testEnv.wrap(deleteAccountHandler);

/**
 * Build a fake callable context with auth.
 */
function makeContext(
  uid: string,
  provider = "password"
): Record<string, unknown> {
  return {
    auth: {
      uid,
      token: {
        firebase: { sign_in_provider: provider },
      },
    },
  };
}

describe("deleteAccount — SCENARIO-534: anti-spoof guard", () => {
  it("throws permission-denied when caller uid != data.uid", async () => {
    const callerUid = "spoof-caller";
    const targetUid = "spoof-target";
    await createTestUser(callerUid);
    await createTestUser(targetUid);

    const ctx = makeContext(callerUid);
    const data: DeleteAccountRequest = { uid: targetUid };

    try {
      await wrappedDeleteAccount(data, ctx);
      fail("Expected HttpsError to be thrown");
    } catch (err: unknown) {
      const e = err as { code?: string; message?: string };
      expect(e.code).toBe("permission-denied");
    } finally {
      await deleteTestUser(callerUid);
      await deleteTestUser(targetUid);
    }
  });
});

describe("deleteAccount — SCENARIO-533, 547, 549, 551: success path", () => {
  const uid = "smoke-success-athlete";

  beforeEach(() => createTestUser(uid));
  afterEach(() => deleteTestUser(uid));

  it("SCENARIO-533: callable executes without permission error for authenticated athlete", async () => {
    const ctx = makeContext(uid);
    const data: DeleteAccountRequest = { uid };

    // Should not throw permission-denied or not-found
    const result = await wrappedDeleteAccount(data, ctx);
    expect(result).toBeDefined();
  });

  it("SCENARIO-551: returns { status, deletedCollections, errors } shape", async () => {
    // Re-create user since previous test deletes Auth entry
    await deleteTestUser(uid);
    await createTestUser(uid);

    const ctx = makeContext(uid);
    const data: DeleteAccountRequest = { uid };
    const result = (await wrappedDeleteAccount(data, ctx)) as DeleteAccountResponse;

    expect(result.status).toBe("success");
    expect(Array.isArray(result.deletedCollections)).toBe(true);
    expect(result.deletedCollections.length).toBeGreaterThan(0);
    expect(Array.isArray(result.errors)).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it("SCENARIO-549: auth user no longer exists after CF success", async () => {
    await deleteTestUser(uid);
    await createTestUser(uid);

    const ctx = makeContext(uid);
    const data: DeleteAccountRequest = { uid };
    await wrappedDeleteAccount(data, ctx);

    await expect(admin.auth(smokeApp).getUser(uid)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });

  it("SCENARIO-547: audit_log/{uid} exists with status success after completion", async () => {
    await deleteTestUser(uid);
    await createTestUser(uid);

    const ctx = makeContext(uid);
    const data: DeleteAccountRequest = { uid };
    await wrappedDeleteAccount(data, ctx);

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

describe("deleteAccount — unauthenticated guard", () => {
  it("throws unauthenticated when auth context is missing", async () => {
    const data: DeleteAccountRequest = { uid: "any-uid" };

    try {
      await wrappedDeleteAccount(data, {}); // no auth context
      fail("Expected HttpsError to be thrown");
    } catch (err: unknown) {
      const e = err as { code?: string };
      expect(e.code).toBe("unauthenticated");
    }
  });
});
