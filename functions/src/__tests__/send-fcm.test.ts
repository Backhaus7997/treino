/**
 * Unit tests for the sendFcm shared helper.
 *
 * Tests run against the Firebase Local Emulator (Firestore).
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-625 — sendFcm dispatches to all valid tokens across multiple uids
 *   SCENARIO-626 — sendFcm removes stale token on registration-token-not-registered error
 *   SCENARIO-627 — sendFcm removes stale token on invalid-registration-token error
 *   SCENARIO-628 — sendFcm skips uid with empty fcmTokens array
 *   SCENARIO-677 — sendFcm called with empty uids[] → no Firestore reads, no multicast, no error
 *
 * REQ-PN-CF-001. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "send-fcm-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { sendFcm, SendFcmInput } from "../notifications/send-fcm";

const db = () => admin.firestore(testApp);

const COL_USERS = "users";

const NOTIFICATION: SendFcmInput["notification"] = {
  title: "Test Title",
  body: "Test Body",
};

const DATA: Record<string, string> = {
  deepLink: "/coach",
};

async function seedUser(
  uid: string,
  fcmTokens?: string[],
): Promise<void> {
  const data: Record<string, unknown> = { uid };
  if (fcmTokens !== undefined) {
    data.fcmTokens = fcmTokens;
  }
  await db().collection(COL_USERS).doc(uid).set(data);
}

async function getUserTokens(uid: string): Promise<string[]> {
  const snap = await db().collection(COL_USERS).doc(uid).get();
  if (!snap.exists) return [];
  const data = snap.data()!;
  return (data.fcmTokens as string[] | undefined) ?? [];
}

async function deleteUser(uid: string): Promise<void> {
  await db().collection(COL_USERS).doc(uid).delete().catch(() => undefined);
}

// Build a mock messaging object that returns a canned BatchResponse
function buildMockMessaging(responses: Array<{ error?: { code: string } }>): admin.messaging.Messaging {
  const sendEachForMulticast = jest.fn().mockResolvedValue({
    responses: responses.map((r) => ({
      success: !r.error,
      error: r.error
        ? { code: r.error.code, message: "FCM error" }
        : undefined,
    })),
    successCount: responses.filter((r) => !r.error).length,
    failureCount: responses.filter((r) => r.error).length,
  } as admin.messaging.BatchResponse);

  return { sendEachForMulticast } as unknown as admin.messaging.Messaging;
}

// ---------------------------------------------------------------------------
// SCENARIO-677 — empty uids[] → no Firestore reads, no multicast, no error
// ---------------------------------------------------------------------------
describe("SCENARIO-677: empty uids array → no-op", () => {
  it("returns 0/0 and does not call sendEachForMulticast", async () => {
    const mockMessaging = buildMockMessaging([]);

    const result = await sendFcm(
      testApp,
      { uids: [], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    expect(result.successCount).toBe(0);
    expect(result.failureCount).toBe(0);
    expect(
      (mockMessaging.sendEachForMulticast as jest.Mock).mock.calls,
    ).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-625 — single uid with one token → multicast called with [token]
// ---------------------------------------------------------------------------
describe("SCENARIO-625: single uid with one token → dispatches to that token", () => {
  const uid = "fcm-test-user-625a";

  beforeEach(() => seedUser(uid, ["tok-single"]));
  afterEach(() => deleteUser(uid));

  it("calls sendEachForMulticast with the single token", async () => {
    const mockMessaging = buildMockMessaging([{ /* success */ }]);

    const result = await sendFcm(
      testApp,
      { uids: [uid], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    const calls = (mockMessaging.sendEachForMulticast as jest.Mock).mock.calls;
    expect(calls).toHaveLength(1);
    expect(calls[0][0].tokens).toEqual(["tok-single"]);
    expect(result.successCount).toBe(1);
    expect(result.failureCount).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-625 (multi-uid) — two uids each with one token → both tokens flattened
// ---------------------------------------------------------------------------
describe("SCENARIO-625: two uids each with one token → both tokens dispatched", () => {
  const uid1 = "fcm-test-user-625b1";
  const uid2 = "fcm-test-user-625b2";

  beforeEach(async () => {
    await seedUser(uid1, ["tok-uid1"]);
    await seedUser(uid2, ["tok-uid2"]);
  });
  afterEach(async () => {
    await deleteUser(uid1);
    await deleteUser(uid2);
  });

  it("flattens tokens from both uids into a single multicast call", async () => {
    const mockMessaging = buildMockMessaging([{ /* success */ }, { /* success */ }]);

    const result = await sendFcm(
      testApp,
      { uids: [uid1, uid2], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    const calls = (mockMessaging.sendEachForMulticast as jest.Mock).mock.calls;
    expect(calls).toHaveLength(1);
    expect(calls[0][0].tokens).toHaveLength(2);
    expect(calls[0][0].tokens).toContain("tok-uid1");
    expect(calls[0][0].tokens).toContain("tok-uid2");
    expect(result.successCount).toBe(2);
    expect(result.failureCount).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-628 — uid with empty/absent fcmTokens → skipped silently
// ---------------------------------------------------------------------------
describe("SCENARIO-628: uid with empty or absent fcmTokens → skipped silently", () => {
  const uidEmpty = "fcm-test-user-628a";
  const uidAbsent = "fcm-test-user-628b";

  beforeEach(async () => {
    await seedUser(uidEmpty, []);
    await seedUser(uidAbsent); // no fcmTokens field
  });
  afterEach(async () => {
    await deleteUser(uidEmpty);
    await deleteUser(uidAbsent);
  });

  it("does not call sendEachForMulticast when fcmTokens is empty", async () => {
    const mockMessaging = buildMockMessaging([]);

    const result = await sendFcm(
      testApp,
      { uids: [uidEmpty], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    expect(result.successCount).toBe(0);
    expect(result.failureCount).toBe(0);
    expect(
      (mockMessaging.sendEachForMulticast as jest.Mock).mock.calls,
    ).toHaveLength(0);
  });

  it("does not call sendEachForMulticast when fcmTokens field is absent", async () => {
    const mockMessaging = buildMockMessaging([]);

    const result = await sendFcm(
      testApp,
      { uids: [uidAbsent], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    expect(result.successCount).toBe(0);
    expect(result.failureCount).toBe(0);
    expect(
      (mockMessaging.sendEachForMulticast as jest.Mock).mock.calls,
    ).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-626 — stale token removed on messaging/registration-token-not-registered
// ---------------------------------------------------------------------------
describe("SCENARIO-626: stale token removed on registration-token-not-registered", () => {
  const uid = "fcm-test-user-626";

  beforeEach(() => seedUser(uid, ["tok-valid", "tok-stale"]));
  afterEach(() => deleteUser(uid));

  it("removes the stale token and leaves the valid token intact", async () => {
    const mockMessaging = buildMockMessaging([
      { /* tok-valid: success */ },
      { error: { code: "messaging/registration-token-not-registered" } },
    ]);

    await sendFcm(
      testApp,
      { uids: [uid], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    const tokens = await getUserTokens(uid);
    expect(tokens).toContain("tok-valid");
    expect(tokens).not.toContain("tok-stale");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-627 — stale token removed on messaging/invalid-registration-token
// ---------------------------------------------------------------------------
describe("SCENARIO-627: stale token removed on invalid-registration-token", () => {
  const uid = "fcm-test-user-627";

  beforeEach(() => seedUser(uid, ["tok-invalid"]));
  afterEach(() => deleteUser(uid));

  it("removes the invalid token from fcmTokens", async () => {
    const mockMessaging = buildMockMessaging([
      { error: { code: "messaging/invalid-registration-token" } },
    ]);

    await sendFcm(
      testApp,
      { uids: [uid], notification: NOTIFICATION, data: DATA },
      mockMessaging,
    );

    const tokens = await getUserTokens(uid);
    expect(tokens).not.toContain("tok-invalid");
    expect(tokens).toHaveLength(0);
  });
});
