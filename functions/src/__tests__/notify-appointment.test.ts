/**
 * Integration tests for notifyOnAppointment Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-632 — new appointment (requested) → notify trainer
 *   SCENARIO-633 — requested → confirmed → notify athlete
 *   SCENARIO-634 — confirmed → cancelled (no cancelledBy) → notify both
 *   SCENARIO-635 — reason === 'athlete-account-deleted' → sendFcm NOT called
 *   SCENARIO-636 — before.status === after.status → sendFcm NOT called (no-op write)
 *
 * REQ-PN-CF-003. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { notifyOnAppointmentHandler } from "../notifications/notify-appointment";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-appointment-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

function makeMockMessaging() {
  const mock = {
    sendEachForMulticast: jest.fn(async (msg: admin.messaging.MulticastMessage) => ({
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  };
  return mock;
}

async function seedUser(uid: string, fcmTokens: string[]): Promise<void> {
  await db().collection("users").doc(uid).set({ uid, fcmTokens });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// SCENARIO-632 — new appointment (status: 'requested') → notify trainer
// ---------------------------------------------------------------------------
describe("SCENARIO-632: new appointment status=requested → notify trainer", () => {
  const trainerId = "trainer-appt-632";
  const athleteId = "athlete-appt-632";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-632"]);
    await seedUser(athleteId, ["athlete-token-632"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[trainerId] and deepLink=/coach/agenda", async () => {
    const mock = makeMockMessaging();
    const afterData = {
      trainerId,
      athleteId,
      status: "requested",
      scheduledAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnAppointmentHandler(testApp, undefined, afterData, mock as any);

    expect(mock.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const callArg = mock.sendEachForMulticast.mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-632");
    expect(callArg.tokens).not.toContain("athlete-token-632");
    expect(callArg.data?.deepLink).toBe("/coach/agenda");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-633 — requested → confirmed → notify athlete
// ---------------------------------------------------------------------------
describe("SCENARIO-633: requested→confirmed → notify athlete", () => {
  const trainerId = "trainer-appt-633";
  const athleteId = "athlete-appt-633";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-633"]);
    await seedUser(athleteId, ["athlete-token-633"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[athleteId] and deepLink=/coach?tab=agenda", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "confirmed",
      scheduledAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnAppointmentHandler(testApp, beforeData, afterData, mock as any);

    expect(mock.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const callArg = mock.sendEachForMulticast.mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("athlete-token-633");
    expect(callArg.tokens).not.toContain("trainer-token-633");
    expect(callArg.data?.deepLink).toBe("/coach?tab=agenda");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-634 — confirmed → cancelled (cancelledBy absent) → notify both
// ---------------------------------------------------------------------------
describe("SCENARIO-634: confirmed→cancelled, no cancelledBy → notify both parties", () => {
  const trainerId = "trainer-appt-634";
  const athleteId = "athlete-appt-634";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-634"]);
    await seedUser(athleteId, ["athlete-token-634"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with both uids when cancelledBy absent", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "confirmed" };
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      scheduledAt: admin.firestore.Timestamp.now(),
      // no cancelledBy field
    };

    await notifyOnAppointmentHandler(testApp, beforeData, afterData, mock as any);

    expect(mock.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const callArg = mock.sendEachForMulticast.mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-634");
    expect(callArg.tokens).toContain("athlete-token-634");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-635 — after.reason === 'athlete-account-deleted' → skip
// ---------------------------------------------------------------------------
describe("SCENARIO-635: reason=athlete-account-deleted → sendFcm NOT called", () => {
  const trainerId = "trainer-appt-635";
  const athleteId = "athlete-appt-635";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-635"]);
    await seedUser(athleteId, ["athlete-token-635"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when reason is athlete-account-deleted", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      reason: "athlete-account-deleted",
      scheduledAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnAppointmentHandler(testApp, beforeData, afterData, mock as any);

    expect(mock.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it("resolves without error", async () => {
    const mock = makeMockMessaging();
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      reason: "athlete-account-deleted",
    };
    await expect(
      notifyOnAppointmentHandler(testApp, undefined, afterData, mock as any),
    ).resolves.not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-636 — before.status === after.status → skip (no-op write)
// ---------------------------------------------------------------------------
describe("SCENARIO-636: before.status === after.status → skip (no-op write)", () => {
  const trainerId = "trainer-appt-636";
  const athleteId = "athlete-appt-636";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-636"]);
    await seedUser(athleteId, ["athlete-token-636"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when status is unchanged", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "requested",
      scheduledAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnAppointmentHandler(testApp, beforeData, afterData, mock as any);

    expect(mock.sendEachForMulticast).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// No-op: after data is missing (delete event)
// ---------------------------------------------------------------------------
describe("no-op: after document missing (delete event)", () => {
  it("resolves cleanly without calling sendFcm", async () => {
    const mock = makeMockMessaging();
    await expect(
      notifyOnAppointmentHandler(testApp, undefined, undefined, mock as any),
    ).resolves.not.toThrow();
    expect(mock.sendEachForMulticast).not.toHaveBeenCalled();
  });
});
