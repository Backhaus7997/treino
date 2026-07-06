/**
 * Integration tests for notifyOverduePaymentsHandler Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-NOTIF-01 — overdue + never-notified → sends push + sets lastOverdueNotifiedAt
 *   SCENARIO-NOTIF-02 — paid payment → skipped (not returned by dueAt query)
 *   SCENARIO-NOTIF-03 — not-yet-due (dueAt in future) → skipped
 *   SCENARIO-NOTIF-04 — overdue but notified <7 days ago → anti-spam skip
 *   SCENARIO-NOTIF-05 — overdue + notified >7 days ago → re-notified
 *   SCENARIO-NOTIF-06 — legacy payment without dueAt → skipped (not in query)
 */

import * as admin from "firebase-admin";
import { notifyOverduePaymentsHandler } from "../payments/notify-overdue-payments";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-overdue-payments-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

// ---------------------------------------------------------------------------
// Mock messaging factory
// ---------------------------------------------------------------------------

type MockMessaging = admin.messaging.Messaging & {
  calls: Array<admin.messaging.MulticastMessage>;
};

/**
 * Returns a mock admin.messaging.Messaging instance that records calls
 * to sendEachForMulticast.
 */
function makeMockMessaging(): MockMessaging {
  const calls: Array<admin.messaging.MulticastMessage> = [];
  const mock = {
    calls,
    sendEachForMulticast: async (
      message: admin.messaging.MulticastMessage,
    ): Promise<admin.messaging.BatchResponse> => {
      calls.push(message);
      return {
        responses: message.tokens.map(() => ({
          success: true,
          messageId: "mock-msg-id",
        })),
        successCount: message.tokens.length,
        failureCount: 0,
      };
    },
  } as unknown as MockMessaging;
  return mock;
}

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

async function seedLink(
  trainerId: string,
  athleteId: string,
  status = "active",
): Promise<void> {
  await db()
    .collection("trainer_links")
    .doc(`${trainerId}_${athleteId}`)
    .set({ trainerId, athleteId, status });
}

async function seedUserWithToken(uid: string, token: string): Promise<void> {
  await db().collection("users").doc(uid).set({ fcmTokens: [token] });
}

async function seedPublicProfile(uid: string, displayName: string): Promise<void> {
  await db()
    .collection("userPublicProfiles")
    .doc(uid)
    .set({ displayName });
}

async function seedPayment(
  docId: string,
  trainerId: string,
  athleteId: string,
  status: string,
  dueAt: admin.firestore.Timestamp | null,
  lastOverdueNotifiedAt?: admin.firestore.Timestamp | null,
): Promise<void> {
  const data: Record<string, unknown> = {
    id: docId,
    trainerId,
    athleteId,
    amountArs: 10000,
    concept: "test",
    status,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (dueAt !== null) {
    data.dueAt = dueAt;
  }
  if (lastOverdueNotifiedAt !== undefined && lastOverdueNotifiedAt !== null) {
    data.lastOverdueNotifiedAt = lastOverdueNotifiedAt;
  }
  await db().collection("payments").doc(docId).set(data);
}

async function cleanupDocs(
  ...refs: Array<admin.firestore.DocumentReference>
): Promise<void> {
  for (const ref of refs) {
    await ref.delete().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// Reference time: 2026-07-06 10:00:00 UTC
// ---------------------------------------------------------------------------
const NOW = new Date(Date.UTC(2026, 6, 6, 10, 0, 0));
// A dueAt in the past (overdue)
const DUE_PAST = admin.firestore.Timestamp.fromDate(
  new Date(Date.UTC(2026, 6, 1, 23, 59, 59)),
);
// A dueAt in the future (not yet due)
const DUE_FUTURE = admin.firestore.Timestamp.fromDate(
  new Date(Date.UTC(2026, 7, 1, 23, 59, 59)),
);
// lastOverdueNotifiedAt 3 days ago (within 7-day window)
const NOTIFIED_RECENT = admin.firestore.Timestamp.fromDate(
  new Date(Date.UTC(2026, 6, 3, 10, 0, 0)),
);
// lastOverdueNotifiedAt 10 days ago (outside 7-day window)
const NOTIFIED_OLD = admin.firestore.Timestamp.fromDate(
  new Date(Date.UTC(2026, 5, 26, 10, 0, 0)),
);

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-01 — overdue + never-notified → sends push + sets field
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-01: overdue + never-notified → sends push and sets lastOverdueNotifiedAt", () => {
  const trainerId = "trainer-notif-01";
  const athleteId = "athlete-notif-01";
  const paymentId = `${trainerId}_${athleteId}_notif-01`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("notifies the athlete and writes lastOverdueNotifiedAt", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-01");
    await seedPublicProfile(trainerId, "Coach Ramírez");
    await seedPayment(paymentId, trainerId, athleteId, "pending", DUE_PAST);

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(1);
    expect(result.skipped).toBe(0);
    expect(result.scanned).toBe(1);

    // Mock messaging should have received exactly one call
    expect(mockMsg.calls).toHaveLength(1);
    expect(mockMsg.calls[0].notification?.title).toBe("Pago pendiente");
    expect(mockMsg.calls[0].notification?.body).toContain("Coach Ramírez");

    // lastOverdueNotifiedAt must be set to NOW
    const snap = await db().collection("payments").doc(paymentId).get();
    const data = snap.data()!;
    const writtenAt = (data.lastOverdueNotifiedAt as admin.firestore.Timestamp).toDate();
    expect(writtenAt.getTime()).toBe(NOW.getTime());
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-02 — paid payment → skipped (status != pending, not in query)
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-02: paid payment → skipped", () => {
  const trainerId = "trainer-notif-02";
  const athleteId = "athlete-notif-02";
  const paymentId = `${trainerId}_${athleteId}_notif-02`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("returns notified:0, skipped:0, scanned:0 for a paid payment", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-02");
    await seedPublicProfile(trainerId, "Coach Test 02");
    // Paid payment — dueAt is in the past but status is 'paid', so the
    // where('status','==','pending') filter excludes it from results.
    await seedPayment(paymentId, trainerId, athleteId, "paid", DUE_PAST);

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(0);
    expect(result.scanned).toBe(0);
    expect(mockMsg.calls).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-03 — not-yet-due (dueAt in future) → skipped
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-03: not-yet-due payment → skipped", () => {
  const trainerId = "trainer-notif-03";
  const athleteId = "athlete-notif-03";
  const paymentId = `${trainerId}_${athleteId}_notif-03`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("returns notified:0, scanned:0 when dueAt is in the future", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-03");
    await seedPublicProfile(trainerId, "Coach Test 03");
    await seedPayment(paymentId, trainerId, athleteId, "pending", DUE_FUTURE);

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(0);
    expect(result.scanned).toBe(0);
    expect(mockMsg.calls).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-04 — overdue but notified <7 days ago → anti-spam skip
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-04: overdue but notified <7 days ago → anti-spam skip", () => {
  const trainerId = "trainer-notif-04";
  const athleteId = "athlete-notif-04";
  const paymentId = `${trainerId}_${athleteId}_notif-04`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("skips notification when lastOverdueNotifiedAt is within 7-day threshold", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-04");
    await seedPublicProfile(trainerId, "Coach Test 04");
    await seedPayment(
      paymentId,
      trainerId,
      athleteId,
      "pending",
      DUE_PAST,
      NOTIFIED_RECENT, // 3 days ago — within threshold
    );

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(0);
    expect(result.skipped).toBe(1);
    expect(result.scanned).toBe(1);
    expect(mockMsg.calls).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-05 — overdue + notified >7 days ago → re-notified
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-05: overdue + notified >7 days ago → re-notified", () => {
  const trainerId = "trainer-notif-05";
  const athleteId = "athlete-notif-05";
  const paymentId = `${trainerId}_${athleteId}_notif-05`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("re-notifies and updates lastOverdueNotifiedAt when outside 7-day window", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-05");
    await seedPublicProfile(trainerId, "Coach Test 05");
    await seedPayment(
      paymentId,
      trainerId,
      athleteId,
      "pending",
      DUE_PAST,
      NOTIFIED_OLD, // 10 days ago — outside threshold
    );

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(1);
    expect(result.skipped).toBe(0);
    expect(result.scanned).toBe(1);
    expect(mockMsg.calls).toHaveLength(1);

    // lastOverdueNotifiedAt must be updated to NOW
    const snap = await db().collection("payments").doc(paymentId).get();
    const data = snap.data()!;
    const writtenAt = (data.lastOverdueNotifiedAt as admin.firestore.Timestamp).toDate();
    expect(writtenAt.getTime()).toBe(NOW.getTime());
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-NOTIF-06 — legacy payment without dueAt → skipped
// ---------------------------------------------------------------------------

describe("SCENARIO-NOTIF-06: legacy payment without dueAt → skipped", () => {
  const trainerId = "trainer-notif-06";
  const athleteId = "athlete-notif-06";
  const paymentId = `${trainerId}_${athleteId}_notif-06`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("users").doc(athleteId),
      db().collection("userPublicProfiles").doc(trainerId),
      db().collection("payments").doc(paymentId),
    );
  });

  it("returns notified:0, scanned:0 for a legacy payment without dueAt", async () => {
    await seedLink(trainerId, athleteId);
    await seedUserWithToken(athleteId, "token-athlete-06");
    await seedPublicProfile(trainerId, "Coach Test 06");
    // Pass null to seedPayment so dueAt is omitted from the doc.
    // Firestore's where('dueAt','<=',now) excludes docs without the field.
    await seedPayment(paymentId, trainerId, athleteId, "pending", null);

    const mockMsg = makeMockMessaging();
    const result = await notifyOverduePaymentsHandler(testApp, NOW, mockMsg);

    expect(result.notified).toBe(0);
    // scanned:0 because Firestore excludes dueAt-less docs from the query
    expect(result.scanned).toBe(0);
    expect(mockMsg.calls).toHaveLength(0);
  });
});
