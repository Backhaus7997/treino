/**
 * Freeze de `friendships/{friendshipId}` (M-03b, ADR-FOLLOW-015).
 *
 * `create`/`update`/`delete` pasan a `if false`: la colección origen queda
 * inmóvil mientras se migra a `follows`, así que un borrado con build vieja
 * ya no puede dejar aristas migradas huérfanas dando acceso (phantom access,
 * LD-04). `read` se CONSERVA sin cambios (ADR-FOLLOW-012): hace falta para
 * el rollback — la reversibilidad la da el dato intacto, no el código — y
 * para que una build vieja que solo lee su lista de amigos no se rompa.
 *
 * Mismo patrón de enforcement real que `follows-rules.test.ts`:
 * `@firebase/rules-unit-testing` con las rules APLICADAS, no el Admin SDK.
 * `withSecurityRulesDisabled` se usa SOLO para sembrar el estado previo.
 *
 * Archivo propio (no se toca `follows-rules.test.ts`) y tiene que estar en
 * el regex de `test:rules` del package.json o no corre en CI.
 *
 * Correr contra el emulador:
 *   npm --prefix functions run test:rules:emulator
 *
 * REQ: REQ-FOLLOW-017 · SCENARIO-822
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

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_FRIENDSHIPS = "friendships";

const AT = new Date("2026-08-04T12:00:00.000Z");

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

afterEach(async () => {
  await testEnv.clearFirestore();
});

/** Cuerpo canónico de una friendship — shape legacy pre-freeze. */
function friendshipBody(
  uidA: string,
  uidB: string,
  requesterId: string,
  status: "pending" | "accepted",
) {
  return {
    id: `${uidA}_${uidB}`,
    uidA,
    uidB,
    requesterId,
    status,
    members: [uidA, uidB],
    createdAt: AT,
  };
}

/** Siembra una friendship ya existente (rules deshabilitadas, solo setup). */
async function seedFriendship(
  uidA: string,
  uidB: string,
  requesterId: string,
  status: "pending" | "accepted",
) {
  const docId = `${uidA}_${uidB}`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_FRIENDSHIPS)
      .doc(docId)
      .set(friendshipBody(uidA, uidB, requesterId, status));
  });
  return docId;
}

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

// ── create ──────────────────────────────────────────────────────────────────
describe("friendships freeze — create", () => {
  // REQ-FOLLOW-017 / SCENARIO-822
  it("deniega crear una friendship nueva, aunque el shape sea válido", async () => {
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FRIENDSHIPS)
        .doc("alice_bob")
        .set(friendshipBody("alice", "bob", "alice", "pending")),
    );
  });
});

// ── update ──────────────────────────────────────────────────────────────────
describe("friendships freeze — update", () => {
  // REQ-FOLLOW-017 / SCENARIO-822 — incluye la escritura legítima pre-freeze:
  // aceptar una solicitud pending.
  it("deniega aceptar una pending (era la escritura legítima pre-freeze)", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "pending");

    await assertFails(
      asUser("bob")
        .collection(COL_FRIENDSHIPS)
        .doc(docId)
        .update({ status: "accepted" }),
    );
  });

  it("deniega cualquier otro update sobre una accepted", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "accepted");

    await assertFails(
      asUser("alice")
        .collection(COL_FRIENDSHIPS)
        .doc(docId)
        .update({ status: "pending" }),
    );
  });
});

// ── delete ──────────────────────────────────────────────────────────────────
describe("friendships freeze — delete", () => {
  // REQ-FOLLOW-017 / SCENARIO-822 — para LOS DOS miembros: antes del freeze
  // cualquiera de los dos podía borrar.
  it("deniega el borrado al miembro uidA", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "accepted");

    await assertFails(
      asUser("alice").collection(COL_FRIENDSHIPS).doc(docId).delete(),
    );
  });

  it("deniega el borrado al miembro uidB", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "accepted");

    await assertFails(
      asUser("bob").collection(COL_FRIENDSHIPS).doc(docId).delete(),
    );
  });
});

// ── read (se conserva — ADR-FOLLOW-012) ─────────────────────────────────────
describe("friendships freeze — read se conserva", () => {
  // REQ-FOLLOW-017 / SCENARIO-822 — este es el que prueba que no rompimos el
  // rollback ni las builds viejas que solo leen su lista de amigos.
  it("un miembro sigue pudiendo leer su friendship", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "accepted");

    await assertSucceeds(
      asUser("alice").collection(COL_FRIENDSHIPS).doc(docId).get(),
    );
  });

  it("un tercero sigue sin poder leer una friendship ajena", async () => {
    const docId = await seedFriendship("alice", "bob", "alice", "accepted");

    await assertFails(
      asUser("mallory").collection(COL_FRIENDSHIPS).doc(docId).get(),
    );
  });
});
