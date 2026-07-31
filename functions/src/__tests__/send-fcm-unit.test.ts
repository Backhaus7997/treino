/** Pure unit tests for history persistence in sendFcm (no emulator). */

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
  messaging: jest.fn(),
}));

import * as admin from "firebase-admin";
import { sendFcm } from "../notifications/send-fcm";

type UserState = { tokens: string[]; add: jest.Mock };

function installFirestore(users: Record<string, UserState>): void {
  const firestore = {
    collection: jest.fn((collectionName: string) => {
      if (collectionName !== "users") throw new Error("unexpected collection");
      return {
        doc: (uid: string) => ({
          get: jest.fn(async () => ({
            exists: true,
            data: () => ({ fcmTokens: users[uid].tokens }),
          })),
          collection: (subcollectionName: string) => {
            if (subcollectionName !== "notifications") {
              throw new Error("unexpected subcollection");
            }
            return { add: users[uid].add };
          },
          update: jest.fn(async () => undefined),
        }),
      };
    }),
  };

  (admin.firestore as unknown as jest.Mock).mockReturnValue(firestore);
}

function mockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(async (message) => ({
      successCount: message.tokens.length,
      failureCount: 0,
      responses: message.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as admin.messaging.Messaging;
}

const baseInput = {
  kind: "reaction" as const,
  notification: { title: "TREINO", body: "Sofía reaccionó" },
  data: { deepLink: "/feed", postId: "post-1" },
  actorUid: "actor-1",
};

describe("sendFcm notification history", () => {
  beforeEach(() => jest.clearAllMocks());

  it("writes one complete history document per recipient", async () => {
    const firstAdd = jest.fn(async () => ({ id: "history-1" }));
    const secondAdd = jest.fn(async () => ({ id: "history-2" }));
    installFirestore({
      "user-1": { tokens: ["token-1"], add: firstAdd },
      "user-2": { tokens: ["token-2"], add: secondAdd },
    });

    await sendFcm(
      {} as admin.app.App,
      { ...baseInput, uids: ["user-1", "user-2"] },
      mockMessaging(),
    );

    for (const add of [firstAdd, secondAdd]) {
      expect(add).toHaveBeenCalledTimes(1);
      expect(add).toHaveBeenCalledWith({
        kind: "reaction",
        title: "TREINO",
        body: "Sofía reaccionó",
        deepLink: "/feed",
        createdAt: expect.anything(),
        actorUid: "actor-1",
      });
    }
  });

  it("still sends the push when history persistence fails", async () => {
    const add = jest.fn(async () => Promise.reject(new Error("firestore down")));
    installFirestore({ user: { tokens: ["token"], add } });
    const messaging = mockMessaging();

    await expect(
      sendFcm(
        {} as admin.app.App,
        { ...baseInput, uids: ["user"] },
        messaging,
      ),
    ).resolves.toEqual({ successCount: 1, failureCount: 0 });

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });

  it("persists history even when the recipient has no FCM tokens", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({ user: { tokens: [], add } });
    const messaging = mockMessaging();

    await expect(
      sendFcm(
        {} as admin.app.App,
        { ...baseInput, uids: ["user"] },
        messaging,
      ),
    ).resolves.toEqual({ successCount: 0, failureCount: 0 });

    expect(add).toHaveBeenCalledTimes(1);
    expect(messaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it("finishes history persistence even when FCM dispatch fails", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({ user: { tokens: ["token"], add } });
    const messaging = {
      sendEachForMulticast: jest.fn(async () =>
        Promise.reject(new Error("fcm down")),
      ),
    } as unknown as admin.messaging.Messaging;

    await expect(
      sendFcm(
        {} as admin.app.App,
        { ...baseInput, uids: ["user"] },
        messaging,
      ),
    ).rejects.toThrow("fcm down");

    expect(add).toHaveBeenCalledTimes(1);
  });
});
