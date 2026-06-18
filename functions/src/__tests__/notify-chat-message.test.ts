/**
 * Integration tests for notifyOnChatMessage Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-629 — new message → sendFcm called with recipients ≠ sender
 *   SCENARIO-630 — long message text → body text portion ≤ 100 chars
 *   SCENARIO-631 — data.deepLink == "/coach/chat/{chatId}?other={senderUid}"
 *   SCENARIO-666 — total body ≤ 256 chars
 *   SCENARIO-680 — sender NOT included in recipients
 *
 * REQ-PN-CF-002. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { notifyOnChatMessageHandler } from "../notifications/notify-chat-message";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-chat-message-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

/** Minimal mock messaging that tracks sendEachForMulticast calls. */
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

async function seedChat(chatId: string, members: string[]): Promise<void> {
  await db().collection("chats").doc(chatId).set({ members });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await db().collection("userPublicProfiles").doc(uid).delete().catch(() => undefined);
  }
}

async function cleanupChat(chatId: string): Promise<void> {
  await db().collection("chats").doc(chatId).delete().catch(() => undefined);
}

// ---------------------------------------------------------------------------
// SCENARIO-629 + SCENARIO-680 — recipients ≠ sender
// ---------------------------------------------------------------------------
describe("SCENARIO-629 + SCENARIO-680: new message → sendFcm called with recipients ≠ sender", () => {
  const chatId = "chat-629";
  const athleteUid = "athlete-629";
  const trainerUid = "trainer-629";

  beforeEach(async () => {
    await seedUser(athleteUid, ["athlete-token"]);
    await seedUser(trainerUid, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Athlete User");
    await seedChat(chatId, [athleteUid, trainerUid]);
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerUid);
    await cleanupChat(chatId);
  });

  it("calls sendFcm with uids = [trainerUid] when sender is athleteUid (SCENARIO-629)", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: athleteUid,
      text: "Hola entrenador!",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toEqual(["trainer-token"]);
  });

  it("does NOT include the sender's uid in recipients (SCENARIO-680)", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: athleteUid,
      text: "Mensaje de prueba",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    // athlete-token should NOT be in the token list
    expect(callArg.tokens).not.toContain("athlete-token");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-630 + SCENARIO-666 — body truncation and length cap
// ---------------------------------------------------------------------------
describe("SCENARIO-630 + SCENARIO-666: body truncation at 100 chars, total ≤ 256 chars", () => {
  const chatId = "chat-630";
  const senderUid = "sender-630";
  const recipientUid = "recipient-630";

  beforeEach(async () => {
    await seedUser(senderUid, []);
    await seedUser(recipientUid, ["recipient-token"]);
    await seedUserPublicProfile(senderUid, "Sender Name");
    await seedChat(chatId, [senderUid, recipientUid]);
  });

  afterEach(async () => {
    await cleanup(senderUid, recipientUid);
    await cleanupChat(chatId);
  });

  it("truncates message text at 100 chars with ellipsis (SCENARIO-630)", async () => {
    const mock = makeMockMessaging();
    const longText = "A".repeat(150); // 150 chars — must be truncated
    const messageData = {
      senderId: senderUid,
      text: longText,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    const body = callArg.notification?.body ?? "";
    // Extract the text portion after "Sender Name: "
    const textPart = body.replace(/^[^:]+: /, "");
    expect(textPart.length).toBeLessThanOrEqual(100 + 1); // +1 for ellipsis char
    expect(textPart.endsWith("…")).toBe(true);
  });

  it("total body length is ≤ 256 chars (SCENARIO-666)", async () => {
    const mock = makeMockMessaging();
    const longText = "B".repeat(200);
    const messageData = {
      senderId: senderUid,
      text: longText,
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    const body = callArg.notification?.body ?? "";
    expect(body.length).toBeLessThanOrEqual(256);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-631 — deepLink
// ---------------------------------------------------------------------------
describe("SCENARIO-631: data.deepLink == /coach/chat/{chatId}?other={senderUid}", () => {
  const chatId = "chat-631";
  const senderUid = "sender-631";
  const recipientUid = "recipient-631";

  beforeEach(async () => {
    await seedUser(senderUid, []);
    await seedUser(recipientUid, ["recipient-token"]);
    await seedUserPublicProfile(senderUid, "Sender 631");
    await seedChat(chatId, [senderUid, recipientUid]);
  });

  afterEach(async () => {
    await cleanup(senderUid, recipientUid);
    await cleanupChat(chatId);
  });

  it("sets data.deepLink to /coach/chat/{chatId}?other={senderUid}", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "Mensaje con deeplink",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.data?.deepLink).toBe(
      `/coach/chat/${chatId}?other=${senderUid}`,
    );
  });
});

// ---------------------------------------------------------------------------
// No-op: sender has no other members
// ---------------------------------------------------------------------------
describe("no-op: message in chat where sender is the only member", () => {
  const chatId = "chat-solo";
  const senderUid = "solo-sender";

  beforeEach(async () => {
    await seedUser(senderUid, ["solo-token"]);
    await seedUserPublicProfile(senderUid, "Solo User");
    await seedChat(chatId, [senderUid]); // only the sender
  });

  afterEach(async () => {
    await cleanup(senderUid);
    await cleanupChat(chatId);
  });

  it("does not call sendEachForMulticast when no other members", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "Hola?",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// REQ-CHATMEDIA-012 — media notification bodies
// ---------------------------------------------------------------------------
describe("REQ-CHATMEDIA-012: media message notification bodies", () => {
  const chatId = "chat-media-notify";
  const senderUid = "sender-media";
  const recipientUid = "recipient-media";

  beforeEach(async () => {
    await seedUser(senderUid, []);
    await seedUser(recipientUid, ["recipient-media-token"]);
    await seedUserPublicProfile(senderUid, "Sender");
    await seedChat(chatId, [senderUid, recipientUid]);
  });

  afterEach(async () => {
    await cleanup(senderUid, recipientUid);
    await cleanupChat(chatId);
  });

  it("image-only: body is 'Sender: 📷 Foto'", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "",
      mediaType: "image",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe("Sender: 📷 Foto");
  });

  it("video-only: body is 'Sender: 🎥 Video'", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "",
      mediaType: "video",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe("Sender: 🎥 Video");
  });

  it("caption + image: caption wins over media label", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "Look at this!",
      mediaType: "image",
      createdAt: admin.firestore.Timestamp.now(),
    };

    await notifyOnChatMessageHandler(testApp, chatId, messageData, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe("Sender: Look at this!");
  });

  it("unknown mediaType with empty text: does not throw, body is 'Sender: '", async () => {
    const mock = makeMockMessaging();
    const messageData = {
      senderId: senderUid,
      text: "",
      mediaType: "unknown",
      createdAt: admin.firestore.Timestamp.now(),
    };

    // Must not throw
    await expect(
      notifyOnChatMessageHandler(testApp, chatId, messageData, mock),
    ).resolves.toBeUndefined();

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    // Body should be "Sender: " (senderName + empty displayText) — no crash
    expect(callArg.notification?.body).toBe("Sender: ");
  });
});
