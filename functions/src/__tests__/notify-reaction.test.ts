/**
 * Unit + integration tests for notifyOnReaction Cloud Function.
 *
 * Unit tests exercise the complete pure truth table without an emulator.
 * Integration tests require the Firestore emulator at 127.0.0.1:8080 and use
 * a mocked Messaging instance.
 */

import * as admin from "firebase-admin";
import {
  notifyOnReactionHandler,
  resolveReactionNotification,
} from "../notifications/notify-reaction";

describe("resolveReactionNotification — pure truth table", () => {
  const base = {
    before: undefined,
    after: { type: "like" },
    post: { authorUid: "author" },
    postId: "post-1",
    reactorUid: "reactor",
    actorDisplayName: "Sofía",
  };

  it("notifies the author when another user creates a reaction", () => {
    expect(resolveReactionNotification(base)).toEqual({
      kind: "notify",
      recipientUid: "author",
      actorUid: "reactor",
      title: "TREINO",
      body: "Sofía reaccionó a tu publicación",
      deepLink: "/feed",
      postId: "post-1",
    });
  });

  it("does not notify when the author reacts to their own post", () => {
    expect(
      resolveReactionNotification({ ...base, reactorUid: "author" }),
    ).toEqual({ kind: "skip", reason: "author reacted to own post" });
  });

  it("does not notify when an existing reaction changes type", () => {
    expect(
      resolveReactionNotification({
        ...base,
        before: { type: "like" },
        after: { type: "fire" },
      }),
    ).toEqual({ kind: "skip", reason: "existing reaction updated" });
  });

  it("does not notify when a reaction is deleted", () => {
    expect(
      resolveReactionNotification({
        ...base,
        before: { type: "like" },
        after: undefined,
      }),
    ).toEqual({ kind: "skip", reason: "after missing (delete)" });
  });

  it("does not notify when the post does not exist", () => {
    expect(resolveReactionNotification({ ...base, post: undefined })).toEqual({
      kind: "skip",
      reason: "post missing or authorUid missing",
    });
  });

  it("does not notify when the post has no authorUid", () => {
    expect(resolveReactionNotification({ ...base, post: {} })).toEqual({
      kind: "skip",
      reason: "post missing or authorUid missing",
    });
  });

  it("falls back to Alguien for an empty or absent actor name", () => {
    expect(
      resolveReactionNotification({ ...base, actorDisplayName: "" }),
    ).toMatchObject({
      kind: "notify",
      body: "Alguien reaccionó a tu publicación",
    });
    expect(
      resolveReactionNotification({ ...base, actorDisplayName: undefined }),
    ).toMatchObject({
      kind: "notify",
      body: "Alguien reaccionó a tu publicación",
    });
  });
});

// ─── Integration tests (require Firestore emulator) ───────────────────────

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-reaction-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(
      async (message: admin.messaging.MulticastMessage) => ({
        successCount: message.tokens.length,
        failureCount: 0,
        responses: message.tokens.map(() => ({
          success: true,
          messageId: "id",
        })),
      }),
    ),
  } as unknown as admin.messaging.Messaging;
}

async function cleanup(postId: string, ...uids: string[]): Promise<void> {
  await db().collection("posts").doc(postId).delete().catch(() => undefined);
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await db()
      .collection("userPublicProfiles")
      .doc(uid)
      .delete()
      .catch(() => undefined);
  }
}

describe("notifyOnReactionHandler — integration", () => {
  const postId = "reaction-notification-post";
  const authorUid = "reaction-author";
  const reactorUid = "reaction-reactor";

  beforeEach(async () => {
    await db().collection("posts").doc(postId).set({ authorUid });
    await db()
      .collection("users")
      .doc(authorUid)
      .set({ uid: authorUid, fcmTokens: ["author-token"] });
    await db()
      .collection("userPublicProfiles")
      .doc(reactorUid)
      .set({ uid: reactorUid, displayName: "Sofía" });
  });

  afterEach(() => cleanup(postId, authorUid, reactorUid));

  it("sends a reaction push to the post author", async () => {
    const messaging = makeMockMessaging();

    await notifyOnReactionHandler(
      testApp,
      postId,
      reactorUid,
      undefined,
      { type: "like" },
      messaging,
    );

    expect(messaging.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const message = (messaging.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(message.tokens).toEqual(["author-token"]);
    expect(message.notification).toEqual({
      title: "TREINO",
      body: "Sofía reaccionó a tu publicación",
    });
    expect(message.data).toMatchObject({
      deepLink: "/feed",
      postId,
      actorUid: reactorUid,
    });
  });

  it("does not send for an update", async () => {
    const messaging = makeMockMessaging();

    await notifyOnReactionHandler(
      testApp,
      postId,
      reactorUid,
      { type: "like" },
      { type: "fire" },
      messaging,
    );

    expect(messaging.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});
