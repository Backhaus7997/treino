/**
 * Unit + integration tests de maintainFollowCounters.
 *
 * Los unit tests ejercitan el `resolveCounterDelta` puro — la tabla de
 * transiciones completa, sin emulador.
 *
 * Los de integración ejercitan `maintainFollowCountersHandler` contra el
 * emulador de Firestore para verificar la actualización transaccional de los
 * dos lados, la guarda de perfil faltante y la simetría (el bug que motivó
 * esta CF: el delete dejaba un seguidor fantasma).
 *
 * `follow-model` PR3a: la fuente de verdad pasa de `friendships` a `follows`.
 * La tabla de transiciones NO cambia. Cambian dos cosas:
 *   a) `partiesOf` deja de INFERIR la dirección buscando dentro de `members` —
 *      la lee directo de `followerUid`/`followeeUid`.
 *   b) `countAcceptedFor` pasa de 1 query + split en memoria a 2 queries
 *      direccionales, porque en el modelo dirigido ya no hay ningún campo que
 *      permita deducir el sentido de una arista desde un único resultado.
 *
 * REQ: REQ-FOLLOW-013 · SCENARIO-816/817
 */

import * as admin from "firebase-admin";
import {
  maintainFollowCountersHandler,
  resolveCounterDelta,
} from "../social/maintain-follow-counters";

const accepted = {
  followerUid: "req",
  followeeUid: "other",
  status: "accepted",
};
const pending = {
  followerUid: "req",
  followeeUid: "other",
  status: "pending",
};

// ─── Unit tests (sin emulador) ─────────────────────────────────────────────

describe("resolveCounterDelta — tabla de transiciones", () => {
  it("∅ → accepted (auto-accept) aplica +1 a los dos", () => {
    expect(resolveCounterDelta(undefined, accepted)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: 1,
    });
  });

  it("pending → accepted (accept manual) aplica +1 a los dos", () => {
    expect(resolveCounterDelta(pending, accepted)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: 1,
    });
  });

  it("accepted → ∅ (unfollow / delete) aplica -1 a los dos", () => {
    expect(resolveCounterDelta(accepted, undefined)).toEqual({
      kind: "apply",
      requesterUid: "req",
      otherUid: "other",
      delta: -1,
    });
  });

  it("∅ → pending es noop (todavía no sigue)", () => {
    expect(resolveCounterDelta(undefined, pending)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });

  it("pending → ∅ (cancelar solicitud) es noop (nunca se contó)", () => {
    expect(resolveCounterDelta(pending, undefined)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });

  it("accepted → accepted (write no-op) es noop", () => {
    expect(resolveCounterDelta(accepted, accepted)).toEqual({
      kind: "noop",
      reason: "accepted-state unchanged",
    });
  });
});

// REQ-FOLLOW-013 — `partiesOf` LEE la dirección, no la deduce.
describe("resolveCounterDelta — la dirección sale de la arista, no de members", () => {
  it("resuelve sin `members` en el documento", () => {
    // El campo `members` existe para que el barrido del borrado de cuenta use
    // una sola query (LD-01), NO para deducir el sentido. Si la CF lo
    // necesitara para saber quién sigue a quién, una arista sin él —escrita
    // por Admin SDK, por ejemplo— dejaría los contadores mudos en silencio.
    expect(
      resolveCounterDelta(undefined, {
        followerUid: "alice",
        followeeUid: "bob",
        status: "accepted",
      }),
    ).toEqual({
      kind: "apply",
      requesterUid: "alice",
      otherUid: "bob",
      delta: 1,
    });
  });

  it("respeta la dirección de la arista y no el orden alfabético", () => {
    // `zoe` sigue a `alice`: quien suma following es zoe, no la primera
    // alfabéticamente. Mata la mutación de ordenar el par.
    expect(
      resolveCounterDelta(undefined, {
        followerUid: "zoe",
        followeeUid: "alice",
        status: "accepted",
      }),
    ).toEqual({
      kind: "apply",
      requesterUid: "zoe",
      otherUid: "alice",
      delta: 1,
    });
  });

  it("noop si falta followeeUid", () => {
    expect(
      resolveCounterDelta(undefined, {
        followerUid: "alice",
        status: "accepted",
      }),
    ).toEqual({ kind: "noop", reason: "after: malformed parties" });
  });

  it("noop si falta followerUid", () => {
    expect(
      resolveCounterDelta(
        { followeeUid: "bob", status: "accepted" },
        undefined,
      ),
    ).toEqual({ kind: "noop", reason: "before: malformed parties" });
  });

  it("noop ante una arista reflexiva (follower == followee)", () => {
    // Las rules lo prohíben, pero el Admin SDK las saltea.
    expect(
      resolveCounterDelta(undefined, {
        followerUid: "alice",
        followeeUid: "alice",
        status: "accepted",
      }),
    ).toEqual({ kind: "noop", reason: "after: malformed parties" });
  });

  it("noop ante la forma LEGACY de friendships (requesterId + members)", () => {
    // Un doc con la forma vieja no tiene que resolver "por casualidad": si
    // resolviera, un residuo sin migrar movería contadores en silencio.
    expect(
      resolveCounterDelta(undefined, {
        requesterId: "req",
        members: ["req", "other"],
        status: "accepted",
      }),
    ).toEqual({ kind: "noop", reason: "after: malformed parties" });
  });
});

// ─── Integration tests (requieren emulador) ────────────────────────────────

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "maintain-follow-counters-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

async function seedProfile(
  uid: string,
  counters: { followersCount?: number; followingCount?: number } = {},
): Promise<void> {
  await db().collection("userPublicProfiles").doc(uid).set({ uid, ...counters });
}

async function counters(
  uid: string,
): Promise<{ followers: number; following: number }> {
  const snap = await db().collection("userPublicProfiles").doc(uid).get();
  const d = snap.data() ?? {};
  return {
    followers: (d.followersCount as number | undefined) ?? 0,
    following: (d.followingCount as number | undefined) ?? 0,
  };
}

async function cleanupProfiles(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db()
      .collection("userPublicProfiles")
      .doc(uid)
      .delete()
      .catch(() => undefined);
  }
}

// QA-507: el handler no aplica un delta ciego — RECOMPUTA desde `follows`. El
// trigger corre DESPUÉS de que el write commitea, así que estos helpers dejan
// la colección en el estado FINAL que el handler va a ver.
const edgeId = (follower: string, followee: string) => `${follower}_${followee}`;

function edgeBody(
  follower: string,
  followee: string,
  status: "pending" | "accepted",
) {
  return {
    id: edgeId(follower, followee),
    followerUid: follower,
    followeeUid: followee,
    status,
    members: [follower, followee],
    createdAt: new Date("2026-08-04T12:00:00.000Z"),
  };
}

const seededEdges: string[] = [];

async function seedEdge(
  follower: string,
  followee: string,
  status: "pending" | "accepted",
): Promise<void> {
  const id = edgeId(follower, followee);
  seededEdges.push(id);
  await db().collection("follows").doc(id).set(edgeBody(follower, followee, status));
}

async function removeEdges(): Promise<void> {
  while (seededEdges.length > 0) {
    const id = seededEdges.pop() as string;
    await db()
      .collection("follows")
      .doc(id)
      .delete()
      .catch(() => undefined);
  }
}

describe("maintainFollowCountersHandler — integración", () => {
  const req = "mfc-req";
  const other = "mfc-other";
  const third = "mfc-third";
  const acceptedDoc = edgeBody(req, other, "accepted");
  const pendingDoc = edgeBody(req, other, "pending");

  beforeEach(async () => {
    await removeEdges(); // pizarra limpia para el recompute
    await seedProfile(req, { followingCount: 0, followersCount: 0 });
    await seedProfile(other, { followingCount: 0, followersCount: 0 });
    await seedProfile(third, { followingCount: 0, followersCount: 0 });
  });

  afterEach(async () => {
    await removeEdges();
    await cleanupProfiles(req, other, third);
  });

  // SCENARIO-816
  it("aceptar incrementa el following del follower y el followers del followee", async () => {
    await seedEdge(req, other, "accepted");
    await maintainFollowCountersHandler(testApp, pendingDoc, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  // SCENARIO-817
  it("dejar de seguir decrementa LOS DOS lados — sin seguidor fantasma", async () => {
    await seedProfile(req, { followingCount: 1, followersCount: 0 });
    await seedProfile(other, { followingCount: 0, followersCount: 1 });

    // accepted → borrado. La arista ya no está en `follows`.
    await maintainFollowCountersHandler(testApp, acceptedDoc, undefined);

    expect(await counters(req)).toEqual({ followers: 0, following: 0 });
    expect(await counters(other)).toEqual({ followers: 0, following: 0 });
  });

  // REQ-FOLLOW-013 — la razón de ser de las DOS queries direccionales.
  it("cuenta por SEPARADO las aristas salientes y las entrantes del mismo uid", async () => {
    // req sigue a other, y third sigue a req. Con una sola query
    // `members array-contains req` los dos documentos vuelven juntos y no hay
    // forma de saber cuál es cuál: `follows` no tiene `requesterId`, así que el
    // split en memoria del modelo viejo mandaría TODO a un solo contador.
    // Éste es el test que obliga a las dos queries direccionales.
    await seedEdge(req, other, "accepted");
    await seedEdge(third, req, "accepted");

    await maintainFollowCountersHandler(testApp, pendingDoc, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 1, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  it("las aristas pendientes no cuentan para ningún lado", async () => {
    await seedEdge(req, other, "pending");
    await seedEdge(third, req, "pending");
    await seedEdge("mfc-extra", req, "accepted");

    await maintainFollowCountersHandler(testApp, undefined, acceptedDoc);

    // Sólo cuenta la aceptada: las dos pendientes no suman de ningún lado.
    expect(await counters(req)).toEqual({ followers: 1, following: 0 });
  });

  it("auto-accept (create accepted) incrementa los dos", async () => {
    await seedEdge(req, other, "accepted");
    await maintainFollowCountersHandler(testApp, undefined, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  it("un create pending no toca los contadores", async () => {
    await maintainFollowCountersHandler(testApp, undefined, pendingDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 0 });
    expect(await counters(other)).toEqual({ followers: 0, following: 0 });
  });

  // QA-507: Eventarc entrega at-least-once. Antes, reprocesar el MISMO evento
  // sumaba +1 otra vez y dejaba los contadores inflados de forma permanente.
  it("es idempotente ante una reentrega del mismo evento", async () => {
    await seedEdge(req, other, "accepted");

    await maintainFollowCountersHandler(testApp, pendingDoc, acceptedDoc);
    await maintainFollowCountersHandler(testApp, pendingDoc, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    expect(await counters(other)).toEqual({ followers: 1, following: 0 });
  });

  it("saltea un perfil inexistente sin tirar error", async () => {
    await cleanupProfiles(other); // other no tiene perfil público
    await seedEdge(req, other, "accepted");
    await maintainFollowCountersHandler(testApp, undefined, acceptedDoc);

    expect(await counters(req)).toEqual({ followers: 0, following: 1 });
    const otherSnap = await db()
      .collection("userPublicProfiles")
      .doc(other)
      .get();
    expect(otherSnap.exists).toBe(false); // no se resucita
  });
});
