/**
 * Unit + integration tests for notifyOnFriendship Cloud Function.
 *
 * Unit tests exercise the pure `resolveFriendshipNotif` + `buildFriendshipCopy`
 * helpers — no emulator required. They cover every branch of the truth table:
 *
 *   before             after                     → resolution
 *   ────────────────── ─────────────────────────  ──────────────────
 *   undefined          undefined                 skip (delete)
 *   undefined          {status:'pending', …}     request-received
 *   undefined          {status:'accepted', …}    auto-followed
 *   pending            accepted                  request-accepted
 *   accepted           accepted (no-op)          skip
 *   pending            pending (no-op)           skip
 *   accepted           pending (illegal downgrade) skip
 *   undefined          {missing requesterId}     skip (invalid)
 *   undefined          {members: []}             skip (invalid)
 *
 * Integration tests exercise `notifyOnFriendshipHandler` against the
 * Firestore emulator to verify the display-name lookup + sendFcm call.
 *
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running the integration
 * tests. Unit tests run without emulator.
 */

import * as admin from "firebase-admin";
import {
  buildFriendshipCopy,
  notifyOnFriendshipHandler,
  resolveFriendshipNotif,
} from "../notifications/notify-friendship";

// ─── Unit tests (no emulator) ──────────────────────────────────────────────

describe("resolveFriendshipNotif — pure branching", () => {
  const members = ["alice", "bob"];

  it("skips when after is undefined (delete/unfollow)", () => {
    expect(resolveFriendshipNotif(undefined, undefined)).toEqual({
      kind: "skip",
      reason: "after missing (delete or unfollow)",
    });
  });

  it("skips when required fields are missing (no requesterId)", () => {
    const after = { status: "pending", members };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "skip",
      reason: "missing required fields",
    });
  });

  it("skips when members[] does not have exactly 2 entries", () => {
    const after = { status: "pending", requesterId: "alice", members: ["alice"] };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "skip",
      reason: "missing required fields",
    });
  });

  it("skips when the other party cannot be inferred (requester is both)", () => {
    // Corrupt shape: members has 2 entries but they're both the requester.
    const after = {
      status: "pending",
      requesterId: "alice",
      members: ["alice", "alice"],
    };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "skip",
      reason: "cannot infer other party from members",
    });
  });

  it("resolves create + pending as request-received to the target", () => {
    const after = { status: "pending", requesterId: "alice", members };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "request-received",
      recipientUid: "bob",
      actorUid: "alice",
    });
  });

  it("resolves create + accepted as auto-followed (public target path)", () => {
    const after = { status: "accepted", requesterId: "alice", members };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "auto-followed",
      recipientUid: "bob",
      actorUid: "alice",
    });
  });

  it("resolves pending → accepted as request-accepted to the requester", () => {
    const before = { status: "pending", requesterId: "alice", members };
    const after = { status: "accepted", requesterId: "alice", members };
    expect(resolveFriendshipNotif(before, after)).toEqual({
      kind: "request-accepted",
      recipientUid: "alice",
      actorUid: "bob",
    });
  });

  it("skips no-op update where status is unchanged (pending→pending)", () => {
    const before = { status: "pending", requesterId: "alice", members };
    const after = { status: "pending", requesterId: "alice", members };
    expect(resolveFriendshipNotif(before, after)).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skips no-op update where status is unchanged (accepted→accepted)", () => {
    const before = { status: "accepted", requesterId: "alice", members };
    const after = { status: "accepted", requesterId: "alice", members };
    expect(resolveFriendshipNotif(before, after)).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skips illegal downgrade accepted → pending", () => {
    // Rules don't allow this write, but a bad admin-SDK call could try it —
    // resolver defensively refuses to notify.
    const before = { status: "accepted", requesterId: "alice", members };
    const after = { status: "pending", requesterId: "alice", members };
    expect(resolveFriendshipNotif(before, after)).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skips create with unexpected status", () => {
    const after = { status: "blocked", requesterId: "alice", members };
    expect(resolveFriendshipNotif(undefined, after)).toEqual({
      kind: "skip",
      reason: 'unknown status "blocked"',
    });
  });
});

describe("buildFriendshipCopy — es-AR copy", () => {
  it("es-AR copy for request-received", () => {
    expect(buildFriendshipCopy("request-received", "Sofía")).toBe(
      "Sofía te envió una solicitud de seguidor",
    );
  });

  it("es-AR copy for auto-followed", () => {
    expect(buildFriendshipCopy("auto-followed", "Sofía")).toBe(
      "Sofía empezó a seguirte",
    );
  });

  it("es-AR copy for request-accepted", () => {
    expect(buildFriendshipCopy("request-accepted", "Sofía")).toBe(
      "Sofía aceptó tu solicitud",
    );
  });
});

// ─── Integration tests (require emulator) ──────────────────────────────────

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-friendship-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

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

async function seedUser(uid: string, tokens: string[]): Promise<void> {
  await db().collection("users").doc(uid).set({ uid, fcmTokens: tokens });
}

async function seedPublicProfile(uid: string, displayName: string): Promise<void> {
  await db().collection("userPublicProfiles").doc(uid).set({ uid, displayName });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await db()
      .collection("userPublicProfiles")
      .doc(uid)
      .delete()
      .catch(() => undefined);
  }
}

describe("notifyOnFriendshipHandler — integration", () => {
  const alice = "friend-int-alice";
  const bob = "friend-int-bob";
  const members = [alice, bob];

  beforeEach(async () => {
    await seedUser(alice, ["alice-token"]);
    await seedUser(bob, ["bob-token"]);
    await seedPublicProfile(alice, "Alicia");
    await seedPublicProfile(bob, "Bruno");
  });

  afterEach(() => cleanup(alice, bob));

  it("create pending → sends to target (bob) with actor name (Alicia)", async () => {
    const mock = makeMockMessaging();
    const after = { status: "pending", requesterId: alice, members };

    await notifyOnFriendshipHandler(testApp, undefined, after, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("bob-token");
    expect(callArg.tokens).not.toContain("alice-token");
    expect(callArg.notification?.body).toBe(
      "Alicia te envió una solicitud de seguidor",
    );
    expect(callArg.data?.deepLink).toBe(`/feed/profile/${alice}`);
    expect(callArg.data?.kind).toBe("request-received");
  });

  it("create accepted (auto) → sends to target with 'empezó a seguirte'", async () => {
    const mock = makeMockMessaging();
    const after = { status: "accepted", requesterId: alice, members };

    await notifyOnFriendshipHandler(testApp, undefined, after, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("bob-token");
    expect(callArg.notification?.body).toBe("Alicia empezó a seguirte");
    expect(callArg.data?.kind).toBe("auto-followed");
  });

  it("pending → accepted → sends to requester (alice) with 'aceptó tu solicitud'", async () => {
    const mock = makeMockMessaging();
    const before = { status: "pending", requesterId: alice, members };
    const after = { status: "accepted", requesterId: alice, members };

    await notifyOnFriendshipHandler(testApp, before, after, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("alice-token");
    expect(callArg.tokens).not.toContain("bob-token");
    expect(callArg.notification?.body).toBe("Bruno aceptó tu solicitud");
    expect(callArg.data?.deepLink).toBe(`/profile/${bob}`);
    expect(callArg.data?.kind).toBe("request-accepted");
  });

  it("delete (after undefined) → sendFcm NOT called", async () => {
    const mock = makeMockMessaging();

    await notifyOnFriendshipHandler(testApp, undefined, undefined, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("no-op update (same status) → sendFcm NOT called", async () => {
    const mock = makeMockMessaging();
    const doc = { status: "pending", requesterId: alice, members };

    await notifyOnFriendshipHandler(testApp, doc, doc, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("actor missing public profile → falls back to 'Alguien'", async () => {
    await cleanup(alice); // wipe alice's profile
    await seedUser(alice, ["alice-token"]); // but keep her token doc
    const mock = makeMockMessaging();
    const after = { status: "pending", requesterId: alice, members };

    await notifyOnFriendshipHandler(testApp, undefined, after, mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe(
      "Alguien te envió una solicitud de seguidor",
    );
  });
});
