/**
 * Integration tests for notifyOnExerciseFeedback Cloud Function. Issue #628.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * Covered:
 *   - kind: "discomfort" → the granted trainer is notified
 *   - kind: "comment"    → NO push (a comment must not buzz the phone)
 *   - no session_shares grant → NO push (nobody can read it anyway)
 *   - the exercise, and the set when present, travel in the body
 *   - long text is truncated
 *   - deepLink points at the trainer's athlete detail screen
 */

import * as admin from "firebase-admin";
import { notifyOnExerciseFeedbackHandler } from "../notifications/notify-exercise-feedback";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-exercise-feedback-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

/** Minimal mock messaging that tracks sendEachForMulticast calls. */
function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(
      async (msg: admin.messaging.MulticastMessage) => ({
        successCount: msg.tokens.length,
        failureCount: 0,
        responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
      }),
    ),
  } as unknown as admin.messaging.Messaging;
}

const athleteUid = "athlete-628";
const trainerUid = "trainer-628";

async function seed({ withGrant = true }: { withGrant?: boolean } = {}) {
  await db().collection("users").doc(trainerUid).set({
    uid: trainerUid,
    fcmTokens: ["trainer-token"],
  });
  await db()
    .collection("userPublicProfiles")
    .doc(athleteUid)
    .set({ uid: athleteUid, displayName: "Martín" });
  if (withGrant) {
    await db()
      .collection("session_shares")
      .doc(athleteUid)
      .set({ trainerId: trainerUid });
  }
}

async function cleanup() {
  await db().collection("users").doc(trainerUid).delete().catch(() => undefined);
  await db()
    .collection("userPublicProfiles")
    .doc(athleteUid)
    .delete()
    .catch(() => undefined);
  await db()
    .collection("session_shares")
    .doc(athleteUid)
    .delete()
    .catch(() => undefined);
}

function feedback(overrides: Record<string, unknown> = {}) {
  return {
    exerciseId: "ex-bench",
    exerciseName: "Press banca",
    slotIndex: 0,
    kind: "discomfort",
    text: "Me tiró el hombro derecho",
    createdAt: admin.firestore.Timestamp.now(),
    ...overrides,
  };
}

function bodyOf(mock: admin.messaging.Messaging): string {
  const call = (mock.sendEachForMulticast as jest.Mock).mock
    .calls[0][0] as admin.messaging.MulticastMessage;
  return call.notification?.body ?? "";
}

describe("notifyOnExerciseFeedback", () => {
  beforeEach(async () => {
    await cleanup();
  });

  afterEach(async () => {
    await cleanup();
  });

  it("notifies the granted trainer on a discomfort report", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const call = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(call.tokens).toEqual(["trainer-token"]);
    expect(call.data?.kind).toBe("exercise-discomfort");
  });

  it("does NOT notify on a plain comment", async () => {
    // The reason the two kinds exist: a routine comment must not buzz the
    // trainer's phone a dozen times per session.
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback({ kind: "comment" }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("does NOT notify when there is no session_shares grant", async () => {
    // Without the grant the trainer cannot read the doc anyway (rules), so
    // there is nobody to notify.
    await seed({ withGrant: false });
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("carries the athlete name and the exercise in the body", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback(),
      mock,
    );

    const body = bodyOf(mock);
    expect(body).toContain("Martín");
    expect(body).toContain("Press banca");
    expect(body).toContain("Me tiró el hombro derecho");
  });

  it("includes the set number when the report is anchored to one", async () => {
    // "serie 3" is precisely what the chat could never carry.
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback({ setNumber: 3 }),
      mock,
    );

    expect(bodyOf(mock)).toContain("serie 3");
  });

  it("omits the set when the report is exercise-level", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback(),
      mock,
    );

    expect(bodyOf(mock)).not.toContain("serie");
  });

  it("truncates long text and keeps the body within FCM limits", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback({ text: "x".repeat(400) }),
      mock,
    );

    const body = bodyOf(mock);
    expect(body).toContain("…");
    expect(body.length).toBeLessThanOrEqual(256);
  });

  it("handles a photo-only report without an empty-body crash", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback({ text: undefined }),
      mock,
    );

    const body = bodyOf(mock);
    expect(body).toContain("Press banca");
    expect(body.length).toBeGreaterThan(0);
  });

  it("deep-links to the trainer's athlete detail screen", async () => {
    await seed();
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      feedback(),
      mock,
    );

    const call = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(call.data?.deepLink).toBe(`/coach/alumno/${athleteUid}`);
  });

  it("falls back to a generic athlete name when the profile is missing",
    async () => {
      await seed();
      await db()
        .collection("userPublicProfiles")
        .doc(athleteUid)
        .delete();
      const mock = makeMockMessaging();

      await notifyOnExerciseFeedbackHandler(
        testApp,
        athleteUid,
        feedback(),
        mock,
      );

      expect(bodyOf(mock)).toContain("Tu alumno");
    });
});
