/**
 * Unit + integration tests de la Cloud Function notifyOnFollow.
 *
 * Los unit tests ejercitan los helpers puros `resolveFollowNotif` +
 * `buildFollowCopy` — sin emulador. Cubren toda la tabla de verdad:
 *
 *   before             after                       → resolución
 *   ────────────────── ───────────────────────────  ──────────────────
 *   undefined          undefined                   skip (delete)
 *   undefined          {status:'pending', …}       request-received
 *   undefined          {status:'accepted', …}      auto-followed
 *   pending            accepted                    request-accepted
 *   accepted           accepted (no-op)            skip
 *   pending            pending (no-op)             skip
 *   accepted           pending (downgrade ilegal)  skip
 *   undefined          {sin followerUid}           skip (inválido)
 *   undefined          {sin followeeUid}           skip (inválido)
 *
 * `follow-model` PR3a: las 3 ramas y TODO el copy quedan intactos. Lo único
 * que cambia es de dónde sale la dirección: antes `requesterId` + búsqueda
 * dentro de `members`; ahora `followerUid`/`followeeUid`, explícitos en la
 * arista. El copy del backend ya estaba escrito en clave "seguidor", así que es
 * la única pieza del sistema que no necesitó adaptarse.
 *
 * Los de integración ejercitan `notifyOnFollowHandler` contra el emulador de
 * Firestore para verificar el lookup del displayName + la llamada a sendFcm.
 *
 * REQ: REQ-FOLLOW-014
 */

import * as admin from "firebase-admin";
import {
  buildFollowCopy,
  notifyOnFollowHandler,
  resolveFollowNotif,
} from "../notifications/notify-friendship";

// ─── Unit tests (sin emulador) ─────────────────────────────────────────────

describe("resolveFollowNotif — ramas puras", () => {
  /** Arista dirigida: alice sigue a bob. */
  const edge = (status: string) => ({
    followerUid: "alice",
    followeeUid: "bob",
    status,
  });

  it("skip cuando after es undefined (delete / unfollow)", () => {
    expect(resolveFollowNotif(undefined, undefined)).toEqual({
      kind: "skip",
      reason: "after missing (delete or unfollow)",
    });
  });

  it("skip cuando falta followerUid", () => {
    expect(
      resolveFollowNotif(undefined, { status: "pending", followeeUid: "bob" }),
    ).toEqual({ kind: "skip", reason: "missing required fields" });
  });

  it("skip cuando falta followeeUid", () => {
    expect(
      resolveFollowNotif(undefined, { status: "pending", followerUid: "alice" }),
    ).toEqual({ kind: "skip", reason: "missing required fields" });
  });

  it("skip ante una arista reflexiva (follower == followee)", () => {
    expect(
      resolveFollowNotif(undefined, {
        status: "pending",
        followerUid: "alice",
        followeeUid: "alice",
      }),
    ).toEqual({ kind: "skip", reason: "reflexive edge" });
  });

  it("skip ante la forma LEGACY de friendships (requesterId + members)", () => {
    // Un residuo sin migrar no tiene que resolver "por casualidad": si
    // resolviera, dispararía pushes por relaciones viejas.
    expect(
      resolveFollowNotif(undefined, {
        status: "pending",
        requesterId: "alice",
        members: ["alice", "bob"],
      }),
    ).toEqual({ kind: "skip", reason: "missing required fields" });
  });

  it("create + pending → request-received al DESTINATARIO", () => {
    expect(resolveFollowNotif(undefined, edge("pending"))).toEqual({
      kind: "request-received",
      recipientUid: "bob",
      actorUid: "alice",
    });
  });

  it("create + accepted → auto-followed (camino de perfil público)", () => {
    expect(resolveFollowNotif(undefined, edge("accepted"))).toEqual({
      kind: "auto-followed",
      recipientUid: "bob",
      actorUid: "alice",
    });
  });

  it("pending → accepted → request-accepted al FOLLOWER", () => {
    expect(resolveFollowNotif(edge("pending"), edge("accepted"))).toEqual({
      kind: "request-accepted",
      recipientUid: "alice",
      actorUid: "bob",
    });
  });

  it("la dirección sale de la arista, no del orden alfabético", () => {
    // `zoe` sigue a `alice`: el destinatario es alice y el actor es zoe, aunque
    // alice ordene primero. Mata la mutación de ordenar el par.
    expect(
      resolveFollowNotif(undefined, {
        followerUid: "zoe",
        followeeUid: "alice",
        status: "pending",
      }),
    ).toEqual({
      kind: "request-received",
      recipientUid: "alice",
      actorUid: "zoe",
    });
  });

  it("resuelve sin `members` en el documento", () => {
    // `members` existe para el barrido del borrado de cuenta (LD-01), no para
    // deducir el sentido de la arista.
    expect(resolveFollowNotif(undefined, edge("pending")).kind).toBe(
      "request-received",
    );
  });

  it("skip en un update no-op (pending→pending)", () => {
    expect(resolveFollowNotif(edge("pending"), edge("pending"))).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skip en un update no-op (accepted→accepted)", () => {
    expect(resolveFollowNotif(edge("accepted"), edge("accepted"))).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skip ante un downgrade ilegal accepted → pending", () => {
    // Las rules no permiten este write, pero una llamada mala del Admin SDK
    // podría intentarlo — el resolver se niega a notificar por las dudas.
    expect(resolveFollowNotif(edge("accepted"), edge("pending"))).toEqual({
      kind: "skip",
      reason: "update without pending→accepted transition",
    });
  });

  it("skip en un create con status inesperado", () => {
    expect(resolveFollowNotif(undefined, edge("blocked"))).toEqual({
      kind: "skip",
      reason: "unknown status \"blocked\"",
    });
  });
});

describe("buildFollowCopy — copy es-AR (INTACTO)", () => {
  it("request-received", () => {
    expect(buildFollowCopy("request-received", "Sofía")).toBe(
      "Sofía te envió una solicitud de seguidor",
    );
  });

  it("auto-followed", () => {
    expect(buildFollowCopy("auto-followed", "Sofía")).toBe(
      "Sofía empezó a seguirte",
    );
  });

  it("request-accepted", () => {
    expect(buildFollowCopy("request-accepted", "Sofía")).toBe(
      "Sofía aceptó tu solicitud",
    );
  });
});

// ─── Integration tests (requieren emulador) ────────────────────────────────

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-follow-test",
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

describe("notifyOnFollowHandler — integración", () => {
  const alice = "follow-int-alice";
  const bob = "follow-int-bob";
  /** alice sigue a bob. */
  const edge = (status: string) => ({
    followerUid: alice,
    followeeUid: bob,
    status,
  });

  beforeEach(async () => {
    await seedUser(alice, ["alice-token"]);
    await seedUser(bob, ["bob-token"]);
    await seedPublicProfile(alice, "Alicia");
    await seedPublicProfile(bob, "Bruno");
  });

  afterEach(() => cleanup(alice, bob));

  it("create pending → le llega al destinatario (bob) con el nombre del actor", async () => {
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, undefined, edge("pending"), mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("bob-token");
    expect(callArg.tokens).not.toContain("alice-token");
    expect(callArg.notification?.body).toBe(
      "Alicia te envió una solicitud de seguidor",
    );
    expect(callArg.data?.deepLink).toBe(`/feed/profile/${alice}`);
    expect(callArg.data?.kind).toBe("friend-request");
  });

  it("create accepted (auto) → le llega al destinatario con 'empezó a seguirte'", async () => {
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, undefined, edge("accepted"), mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("bob-token");
    expect(callArg.notification?.body).toBe("Alicia empezó a seguirte");
    expect(callArg.data?.kind).toBe("friend-follow");
  });

  it("pending → accepted → le llega al follower (alice) con 'aceptó tu solicitud'", async () => {
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, edge("pending"), edge("accepted"), mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("alice-token");
    expect(callArg.tokens).not.toContain("bob-token");
    expect(callArg.notification?.body).toBe("Bruno aceptó tu solicitud");
    expect(callArg.data?.deepLink).toBe(`/feed/profile/${bob}`);
    expect(callArg.data?.kind).toBe("friend-accepted");
  });

  it("delete (after undefined) → NO se llama a sendFcm", async () => {
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, undefined, undefined, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("update no-op (mismo status) → NO se llama a sendFcm", async () => {
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, edge("pending"), edge("pending"), mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("actor sin perfil público → cae a 'Alguien'", async () => {
    await cleanup(alice); // se borra el perfil de alice
    await seedUser(alice, ["alice-token"]); // pero se conserva su doc de tokens
    const mock = makeMockMessaging();

    await notifyOnFollowHandler(testApp, undefined, edge("pending"), mock);

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toBe(
      "Alguien te envió una solicitud de seguidor",
    );
  });
});
