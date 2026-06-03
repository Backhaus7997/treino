/**
 * Integration tests for notifyOnReview Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-642 — new review → sendFcm called with uids=[trainerId], body + deepLink correct
 *   SCENARIO-681 — trainer with empty fcmTokens → sendFcm silently skips (no error)
 *
 * REQ-PN-CF-005. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { notifyOnReviewHandler } from "../notifications/notify-review";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-review-test",
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

async function seedUserPublicProfile(uid: string, displayName: string): Promise<void> {
  await db().collection("userPublicProfiles").doc(uid).set({ uid, displayName });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await db().collection("userPublicProfiles").doc(uid).delete().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// SCENARIO-642 — new review → notify trainer with correct body + deepLink
// ---------------------------------------------------------------------------
describe("SCENARIO-642: new review → sendFcm called with trainerId, correct body+deepLink", () => {
  const trainerId = "trainer-review-642";
  const athleteId = "athlete-review-642";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-642"]);
    await seedUser(athleteId, ["athlete-token-642"]);
    await seedUserPublicProfile(athleteId, "Juan");
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[trainerId]", async () => {
    const mock = makeMockMessaging();
    const reviewData = {
      trainerId,
      athleteId,
      rating: 5,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnReviewHandler(testApp, reviewData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-642");
    expect(callArg.tokens).not.toContain("athlete-token-642");
  });

  it("body is '${athleteName} dejó una reseña de ${rating}⭐'", async () => {
    const mock = makeMockMessaging();
    const reviewData = {
      trainerId,
      athleteId,
      rating: 5,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnReviewHandler(testApp, reviewData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe("Juan dejó una reseña de 5⭐");
  });

  it("data.deepLink is /coach/trainer/{trainerId}", async () => {
    const mock = makeMockMessaging();
    const reviewData = {
      trainerId,
      athleteId,
      rating: 5,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnReviewHandler(testApp, reviewData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.data?.deepLink).toBe(`/coach/trainer/${trainerId}`);
  });

  it("uses fallback athlete name when userPublicProfiles displayName is absent", async () => {
    const mock = makeMockMessaging();
    // Seed athlete without public profile
    const noProfileAthleteId = "athlete-no-profile-642";
    await seedUser(noProfileAthleteId, []);
    const reviewData = {
      trainerId,
      athleteId: noProfileAthleteId,
      rating: 4,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnReviewHandler(testApp, reviewData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    // Fallback is "Un atleta"
    expect(callArg.notification?.body).toBe("Un atleta dejó una reseña de 4⭐");
    await db().collection("users").doc(noProfileAthleteId).delete().catch(() => undefined);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-681 — trainer with empty fcmTokens → silently skips, no error
// ---------------------------------------------------------------------------
describe("SCENARIO-681: trainer with empty fcmTokens → sendFcm silently skips", () => {
  const trainerId = "trainer-review-681";
  const athleteId = "athlete-review-681";

  beforeEach(async () => {
    await seedUser(trainerId, []); // empty tokens
    await seedUser(athleteId, ["athlete-token-681"]);
    await seedUserPublicProfile(athleteId, "Maria");
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("resolves without error and does not call sendEachForMulticast", async () => {
    const mock = makeMockMessaging();
    const reviewData = {
      trainerId,
      athleteId,
      rating: 3,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await expect(
      notifyOnReviewHandler(testApp, reviewData, mock),
    ).resolves.not.toThrow();

    // sendEachForMulticast should not be called (sendFcm skips empty token lists)
    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});
