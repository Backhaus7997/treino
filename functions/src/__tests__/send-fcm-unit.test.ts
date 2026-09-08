/** Pure unit tests for history persistence in sendFcm (no emulator). */

// `FieldValue` va acá y no en el doble modular: la puerta modular REEXPORTA de
// ésta, así que una sola fuente de verdad. Hasta que este PR mockeó
// `firebase-admin/firestore`, `send-fcm.ts` leía el `FieldValue` REAL por el
// subpath — era el drift que el trinquete existe para cerrar, y que acá era
// inocuo sólo porque `serverTimestamp()` es una fábrica pura.
jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: {
      serverTimestamp: () => "__ts__",
      arrayRemove: (...v: unknown[]) => ({ __arrayRemove: v }),
    },
  }),
  messaging: jest.fn(),
}));

jest.mock("firebase-admin/messaging", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).messaging());

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

import { App } from "firebase-admin/app";
import { Messaging } from "firebase-admin/messaging";
import { sendFcm } from "../notifications/send-fcm";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";

type UserState = {
  tokens: string[];
  add: jest.Mock;
  notificationPrefs?: Record<string, Record<string, boolean | undefined>>;
};

function installFirestore(users: Record<string, UserState>): void {
  const firestore = {
    collection: jest.fn((collectionName: string) => {
      if (collectionName !== "users") throw new Error("unexpected collection");
      return {
        doc: (uid: string) => ({
          get: jest.fn(async () => ({
            exists: true,
            data: () => ({
              fcmTokens: users[uid].tokens,
              notificationPrefs: users[uid].notificationPrefs,
            }),
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

  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue(firestore);
}

function mockMessaging(): Messaging {
  return {
    sendEachForMulticast: jest.fn(async (message) => ({
      successCount: message.tokens.length,
      failureCount: 0,
      responses: message.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as Messaging;
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
      {} as App,
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
        {} as App,
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
        {} as App,
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
    } as unknown as Messaging;

    await expect(
      sendFcm(
        {} as App,
        { ...baseInput, uids: ["user"] },
        messaging,
      ),
    ).rejects.toThrow("fcm down");

    expect(add).toHaveBeenCalledTimes(1);
  });
});

describe("sendFcm push preferences", () => {
  beforeEach(() => jest.clearAllMocks());

  const pushInput = {
    ...baseInput,
    kind: "chat-message" as const,
    prefKey: "mensaje_nuevo",
  };

  it("does not dispatch when the recipient explicitly disabled push", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({
      user: {
        tokens: ["token"],
        add,
        notificationPrefs: { mensaje_nuevo: { push: false } },
      },
    });
    const messaging = mockMessaging();

    await expect(
      sendFcm(
        {} as App,
        { ...pushInput, uids: ["user"] },
        messaging,
      ),
    ).resolves.toEqual({ successCount: 0, failureCount: 0 });

    expect(messaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it("dispatches when push is explicitly enabled", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({
      user: {
        tokens: ["token"],
        add,
        notificationPrefs: { mensaje_nuevo: { push: true } },
      },
    });
    const messaging = mockMessaging();

    await sendFcm(
      {} as App,
      { ...pushInput, uids: ["user"] },
      messaging,
    );

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });

  it("defaults to dispatch when notificationPrefs is absent", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({ user: { tokens: ["token"], add } });
    const messaging = mockMessaging();

    await sendFcm(
      {} as App,
      { ...pushInput, uids: ["user"] },
      messaging,
    );

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });

  it("defaults to dispatch when the row has no push key", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({
      user: {
        tokens: ["token"],
        add,
        notificationPrefs: { mensaje_nuevo: { email: false } },
      },
    });
    const messaging = mockMessaging();

    await sendFcm(
      {} as App,
      { ...pushInput, uids: ["user"] },
      messaging,
    );

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });

  it("does not gate notifications without a prefKey", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({
      user: {
        tokens: ["token"],
        add,
        notificationPrefs: { mensaje_nuevo: { push: false } },
      },
    });
    const messaging = mockMessaging();

    await sendFcm(
      {} as App,
      { ...baseInput, uids: ["user"] },
      messaging,
    );

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
  });

  it("dispatches only the enabled recipient tokens", async () => {
    const disabledAdd = jest.fn(async () => ({ id: "history-disabled" }));
    const enabledAdd = jest.fn(async () => ({ id: "history-enabled" }));
    installFirestore({
      disabled: {
        tokens: ["disabled-token"],
        add: disabledAdd,
        notificationPrefs: { mensaje_nuevo: { push: false } },
      },
      enabled: {
        tokens: ["enabled-token"],
        add: enabledAdd,
        notificationPrefs: { mensaje_nuevo: { push: true } },
      },
    });
    const messaging = mockMessaging();

    await sendFcm(
      {} as App,
      { ...pushInput, uids: ["disabled", "enabled"] },
      messaging,
    );

    expect(messaging.sendEachForMulticast).toHaveBeenCalledWith(
      expect.objectContaining({ tokens: ["enabled-token"] }),
    );
  });

  it("still writes history when push is disabled", async () => {
    const add = jest.fn(async () => ({ id: "history" }));
    installFirestore({
      user: {
        tokens: ["token"],
        add,
        notificationPrefs: { mensaje_nuevo: { push: false } },
      },
    });

    await sendFcm(
      {} as App,
      { ...pushInput, uids: ["user"] },
      mockMessaging(),
    );

    expect(add).toHaveBeenCalledTimes(1);
  });
});
