/**
 * Integration tests for notifyOnLinkChange Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-637 — new link (pending) → notify trainer
 *   SCENARIO-638 — pending → active → notify athlete
 *   SCENARIO-639 — active → terminated (no reason) → notify BOTH
 *   SCENARIO-640 — reason === 'account-deleted' → sendFcm NOT called
 *   SCENARIO-641 — before.status === after.status → sendFcm NOT called (no-op)
 *   SCENARIO-642 — active → paused → notify athlete (pausada)
 *   SCENARIO-643 — paused → active (resume) → notify athlete (reanudada)
 *
 * REQ-PN-CF-004. Fase 6 Etapa 2 + Etapa 3.
 */

import * as admin from "firebase-admin";
import { notifyOnLinkChangeHandler } from "../notifications/notify-link-change";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-link-change-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(async (msg: admin.messaging.MulticastMessage) => ({
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as admin.messaging.Messaging;
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
// SCENARIO-637 — new link (status: 'pending') → notify trainer
// ---------------------------------------------------------------------------
describe("SCENARIO-637: new link status=pending → notify trainer", () => {
  const trainerId = "trainer-link-637";
  const athleteId = "athlete-link-637";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-637"]);
    await seedUser(athleteId, ["athlete-token-637"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[trainerId] and deepLink=/coach", async () => {
    const mock = makeMockMessaging();
    const afterData = { trainerId, athleteId, status: "pending" };

    await notifyOnLinkChangeHandler(testApp, undefined, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-637");
    expect(callArg.tokens).not.toContain("athlete-token-637");
    expect(callArg.data?.deepLink).toBe("/coach");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-638 — pending → active → notify athlete
// ---------------------------------------------------------------------------
describe("SCENARIO-638: pending→active → notify athlete", () => {
  const trainerId = "trainer-link-638";
  const athleteId = "athlete-link-638";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-638"]);
    await seedUser(athleteId, ["athlete-token-638"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[athleteId] and deepLink=/coach", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "pending" };
    const afterData = { trainerId, athleteId, status: "active" };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("athlete-token-638");
    expect(callArg.tokens).not.toContain("trainer-token-638");
    expect(callArg.data?.deepLink).toBe("/coach");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-639 — active → terminated (no reason) → notify BOTH
// ---------------------------------------------------------------------------
describe("SCENARIO-639: active→terminated, no reason → notify BOTH parties", () => {
  const trainerId = "trainer-link-639";
  const athleteId = "athlete-link-639";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-639"]);
    await seedUser(athleteId, ["athlete-token-639"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with both trainer and athlete tokens (SCENARIO-639)", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "active" };
    const afterData = {
      trainerId,
      athleteId,
      status: "terminated",
      // no reason field
    };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-639");
    expect(callArg.tokens).toContain("athlete-token-639");
    expect(callArg.data?.deepLink).toBe("/coach");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-640 — after.reason === 'account-deleted' → skip
// ---------------------------------------------------------------------------
describe("SCENARIO-640: reason=account-deleted → sendFcm NOT called", () => {
  const trainerId = "trainer-link-640";
  const athleteId = "athlete-link-640";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-640"]);
    await seedUser(athleteId, ["athlete-token-640"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when reason is account-deleted", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "active" };
    const afterData = {
      trainerId,
      athleteId,
      status: "terminated",
      reason: "account-deleted",
    };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("resolves without error", async () => {
    const mock = makeMockMessaging();
    const afterData = {
      trainerId,
      athleteId,
      status: "terminated",
      reason: "account-deleted",
    };
    await expect(
      notifyOnLinkChangeHandler(testApp, undefined, afterData, mock),
    ).resolves.not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-641 — before.status === after.status → skip (no-op write)
// ---------------------------------------------------------------------------
describe("SCENARIO-641: before.status === after.status → skip (no-op write)", () => {
  const trainerId = "trainer-link-641";
  const athleteId = "athlete-link-641";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-641"]);
    await seedUser(athleteId, ["athlete-token-641"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when status is unchanged", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "pending" };
    const afterData = { trainerId, athleteId, status: "pending" };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-642 — active → paused → notify athlete (Fase 6 Etapa 3)
// ---------------------------------------------------------------------------
describe("SCENARIO-642: active→paused → notify athlete", () => {
  const trainerId = "trainer-link-642";
  const athleteId = "athlete-link-642";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-642"]);
    await seedUser(athleteId, ["athlete-token-642"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("notifies only the athlete with the pausada copy", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "active" };
    const afterData = { trainerId, athleteId, status: "paused" };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("athlete-token-642");
    expect(callArg.tokens).not.toContain("trainer-token-642");
    expect(callArg.notification?.title).toBe("Vinculación pausada");
    expect(callArg.notification?.body).toBe("Tu PF pausó el vínculo.");
    expect(callArg.data?.deepLink).toBe("/coach");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-643 — paused → active (resume) → notify athlete (Fase 6 Etapa 3)
// ---------------------------------------------------------------------------
describe("SCENARIO-643: paused→active (resume) → notify athlete", () => {
  const trainerId = "trainer-link-643";
  const athleteId = "athlete-link-643";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-643"]);
    await seedUser(athleteId, ["athlete-token-643"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("notifies only the athlete with the reanudada copy (not 'aceptada')", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "paused" };
    const afterData = { trainerId, athleteId, status: "active" };

    await notifyOnLinkChangeHandler(testApp, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("athlete-token-643");
    expect(callArg.tokens).not.toContain("trainer-token-643");
    expect(callArg.notification?.title).toBe("Vinculación reanudada");
    expect(callArg.notification?.body).toBe("Tu PF reanudó el vínculo.");
    expect(callArg.data?.deepLink).toBe("/coach");
  });
});

// ---------------------------------------------------------------------------
// No-op: after document missing (delete event)
// ---------------------------------------------------------------------------
describe("no-op: after document missing (delete event)", () => {
  it("resolves cleanly without calling sendFcm", async () => {
    const mock = makeMockMessaging();
    await expect(
      notifyOnLinkChangeHandler(testApp, undefined, undefined, mock),
    ).resolves.not.toThrow();
    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});
