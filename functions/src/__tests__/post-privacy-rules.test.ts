/**
 * Enforcement real de la privacidad de posts y reacciones — ahora DIRECCIONAL.
 *
 * Origen (QA-FEED-001): `posts/{postId}` read debe aplicar la privacidad
 * SERVER-SIDE, no sólo en el cliente (REQ-PFM-009). Antes del fix `allow read`
 * era efectivamente "cualquier autenticado" y se podían bajar todos los posts
 * `friends`/`gym` por SDK.
 *
 * Cambio de este PR (`follow-model`, PR3a): el tier `friends` deja de
 * preguntar "¿existe una amistad aceptada entre los dos?" — pregunta
 * **"¿el lector sigue al autor?"**, o sea `follows/{lector}_{autor}` con
 * `status=='accepted'`. Es la única forma de expresar el modelo asimétrico:
 * con `friendships` (un doc por par, id ordenado) las dos direcciones colisionan
 * en el mismo documento y "A sigue a B pero B no a A" es irrepresentable.
 *
 * El literal `'friends'` de `resource.data.privacy` NO se toca (LD-05): el
 * rename del tier es sólo del lado del cliente y va por `@JsonValue`.
 *
 * `withSecurityRulesDisabled` se usa SOLO para sembrar el estado previo; toda
 * aserción corre en un contexto de cliente autenticado con las rules aplicadas.
 *
 * Este archivo tiene que estar en el regex de `test:rules` del package.json o
 * no corre en el job `functions-test`.
 *
 * Correr contra el emulador (Java 21):
 *   npm --prefix functions run test:rules:emulator
 *
 * REQ: REQ-FOLLOW-010 · SCENARIO-811/812/813
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";

// projectId propio para que el clearFirestore() de esta suite no pise los
// fixtures de otra suite de rules corriendo contra el mismo emulador.
const PROJECT_ID = "treino-rules-test-feed001";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_FOLLOWS = "follows";

const AUTHOR = "author-uid";
// Sigue a AUTHOR, aceptado → ve sus posts `friends`.
const FOLLOWER = "follower-uid";
// Sigue a AUTHOR pero la solicitud está pendiente → NO ve nada.
const PENDING = "pending-uid";
// AUTHOR lo sigue a ÉL, pero él NO sigue a AUTHOR. Es el caso que el modelo
// viejo no podía ni representar: con `friendships` esta relación y la de
// FOLLOWER eran el MISMO documento.
const FOLLOWED_BY_AUTHOR = "followed-by-author-uid";
// Sin ninguna arista en ninguna dirección.
const STRANGER = "stranger-uid";
const SAME_GYM = "same-gym-uid";
const OTHER_GYM = "other-gym-uid";
const GYM_A = "gym-A";
const GYM_B = "gym-B";

const AT = new Date("2026-08-04T12:00:00.000Z");

/** Doc id de `follows`: dirigido, SIN ordenar. Ahí vive la asimetría. */
const edgeId = (follower: string, followee: string) => `${follower}_${followee}`;

/** Cuerpo canónico de una arista — las 6 keys de la allowlist, nada más. */
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
    createdAt: AT,
  };
}

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

// Grafo compartido, sembrado con rules deshabilitadas antes de cada test.
beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Usuarios con gimnasio (el tier `gym` lee users/{caller}.gymId).
    await db.collection("users").doc(AUTHOR).set({ uid: AUTHOR, gymId: GYM_A });
    await db.collection("users").doc(SAME_GYM).set({ uid: SAME_GYM, gymId: GYM_A });
    await db.collection("users").doc(OTHER_GYM).set({ uid: OTHER_GYM, gymId: GYM_B });
    // FOLLOWER/PENDING/FOLLOWED_BY_AUTHOR/STRANGER a propósito sin doc de gym.

    // Aristas dirigidas.
    await db
      .collection(COL_FOLLOWS)
      .doc(edgeId(FOLLOWER, AUTHOR))
      .set(edgeBody(FOLLOWER, AUTHOR, "accepted"));
    await db
      .collection(COL_FOLLOWS)
      .doc(edgeId(PENDING, AUTHOR))
      .set(edgeBody(PENDING, AUTHOR, "pending"));
    // Dirección OPUESTA: el autor lo sigue a él. No le da acceso al contenido
    // del autor — para eso hace falta la arista {FOLLOWED_BY_AUTHOR}_{AUTHOR}.
    await db
      .collection(COL_FOLLOWS)
      .doc(edgeId(AUTHOR, FOLLOWED_BY_AUTHOR))
      .set(edgeBody(AUTHOR, FOLLOWED_BY_AUTHOR, "accepted"));

    // Posts de AUTHOR, uno por tier.
    await db
      .collection("posts")
      .doc("p-public")
      .set({ authorUid: AUTHOR, privacy: "public", text: "pub" });
    await db
      .collection("posts")
      .doc("p-friends")
      .set({ authorUid: AUTHOR, privacy: "friends", text: "fr" });
    await db
      .collection("posts")
      .doc("p-gym")
      .set({ authorUid: AUTHOR, privacy: "gym", authorGymId: GYM_A, text: "gym" });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function readPost(uid: string | null, postId: string) {
  const ctx =
    uid === null
      ? testEnv.unauthenticatedContext()
      : testEnv.authenticatedContext(uid);
  return ctx.firestore().collection("posts").doc(postId).get();
}

/** Crea la reacción de [uid] sobre [postId]. El doc id ES el uid del reactor. */
function reactTo(uid: string, postId: string) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection("posts")
    .doc(postId)
    .collection("reactions")
    .doc(uid)
    .set({ type: "like", createdAt: AT });
}

/** Lee la reacción de [reactorUid] sobre [postId], autenticado como [uid]. */
function readReaction(uid: string, postId: string, reactorUid: string) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection("posts")
    .doc(postId)
    .collection("reactions")
    .doc(reactorUid)
    .get();
}

describe("posts/{postId} read — privacidad server-side (QA-FEED-001)", () => {
  it("DENIEGA la lectura no autenticada de un post público", async () => {
    await assertFails(readPost(null, "p-public"));
  });

  it("permite a cualquier autenticado leer un post público", async () => {
    await assertSucceeds(readPost(STRANGER, "p-public"));
  });

  it("deja al autor leer su propio post de seguidores", async () => {
    await assertSucceeds(readPost(AUTHOR, "p-friends"));
  });

  it("deja al autor leer su propio post de gimnasio", async () => {
    await assertSucceeds(readPost(AUTHOR, "p-gym"));
  });
});

describe("posts tier seguidores — gate DIRECCIONAL (REQ-FOLLOW-010)", () => {
  // SCENARIO-812
  it("permite leer a quien SIGUE al autor con arista aceptada", async () => {
    await assertSucceeds(readPost(FOLLOWER, "p-friends"));
  });

  // SCENARIO-811 — el caso que el modelo viejo no podía representar.
  it("DENIEGA a quien el autor sigue pero que NO sigue al autor", async () => {
    // Existe follows/{AUTHOR}_{FOLLOWED_BY_AUTHOR} aceptada, pero la arista que
    // el gate mira es la contraria: follows/{FOLLOWED_BY_AUTHOR}_{AUTHOR}.
    await assertFails(readPost(FOLLOWED_BY_AUTHOR, "p-friends"));
  });

  it("DENIEGA a un desconocido sin ninguna arista", async () => {
    await assertFails(readPost(STRANGER, "p-friends"));
  });

  it("DENIEGA cuando la solicitud está pendiente y no aceptada", async () => {
    await assertFails(readPost(PENDING, "p-friends"));
  });
});

describe("posts tier gimnasio — sin cambios", () => {
  it("permite a alguien del mismo gimnasio leer un post de gimnasio", async () => {
    await assertSucceeds(readPost(SAME_GYM, "p-gym"));
  });

  it("DENIEGA a alguien de otro gimnasio", async () => {
    await assertFails(readPost(OTHER_GYM, "p-gym"));
  });

  it("DENIEGA a alguien sin gimnasio", async () => {
    await assertFails(readPost(STRANGER, "p-gym"));
  });

  it("DENIEGA a un seguidor aceptado sin gimnasio compartido", async () => {
    // Los tiers son independientes: seguir al autor da acceso al tier
    // seguidores, no al de gimnasio.
    await assertFails(readPost(FOLLOWER, "p-gym"));
  });
});

// SCENARIO-813 — el gate de reacciones espeja exactamente el de posts. Si no
// lo espejara, la reacción sería un canal lateral para confirmar la existencia
// y el contenido de un post que no se puede leer.
describe("reactions — espejan el gate direccional (REQ-FOLLOW-010)", () => {
  it("permite reaccionar a quien SIGUE al autor", async () => {
    await assertSucceeds(reactTo(FOLLOWER, "p-friends"));
  });

  it("DENIEGA reaccionar a quien el autor sigue pero que NO sigue al autor", async () => {
    await assertFails(reactTo(FOLLOWED_BY_AUTHOR, "p-friends"));
  });

  it("DENIEGA reaccionar a un desconocido", async () => {
    await assertFails(reactTo(STRANGER, "p-friends"));
  });

  it("DENIEGA reaccionar con la solicitud pendiente", async () => {
    await assertFails(reactTo(PENDING, "p-friends"));
  });

  it("permite reaccionar a cualquiera sobre un post público", async () => {
    await assertSucceeds(reactTo(STRANGER, "p-public"));
  });

  it("permite LEER la reacción a quien sigue al autor", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("posts")
        .doc("p-friends")
        .collection("reactions")
        .doc(AUTHOR)
        .set({ type: "fire", createdAt: AT });
    });
    await assertSucceeds(readReaction(FOLLOWER, "p-friends", AUTHOR));
  });

  it("DENIEGA LEER la reacción a quien no sigue al autor", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("posts")
        .doc("p-friends")
        .collection("reactions")
        .doc(AUTHOR)
        .set({ type: "fire", createdAt: AT });
    });
    await assertFails(readReaction(FOLLOWED_BY_AUTHOR, "p-friends", AUTHOR));
  });
});
