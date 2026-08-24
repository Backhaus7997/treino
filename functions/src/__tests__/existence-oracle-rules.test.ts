/**
 * QA-SEC-010 — el idiom `resource == null ||` sobre un doc id DETERMINÍSTICO
 * es un oráculo de existencia.
 *
 * Cuatro bloques de `read` de `firestore.rules` arrancaban con
 * `resource == null ||`. En los cuatro el doc id se puede armar desde afuera
 * (`sorted(a,b).join('_')`, `{follower}_{followee}`, `{trainerId}_{athleteId}`)
 * y los dos padrones de uid son enumerables — `userPublicProfiles` y
 * `trainerPublicProfiles` permiten `list` a cualquier autenticado. La
 * combinación deja preguntar "¿existe este documento?" y **leer la respuesta en
 * la forma de la respuesta**:
 *
 *   doc NO existe  -> `resource == null` da true -> snapshot vacío, sin error
 *   doc SÍ existe   -> el gate de dueño da false  -> PERMISSION_DENIED
 *
 * El atacante nunca quiso el contenido: quería saber si el documento está. Por
 * eso **cada bloque se asserta en las DOS direcciones**. Un test que sólo
 * cubriera el caso "existe" pasaría verde con el agujero abierto — que es
 * exactamente lo que venía pasando.
 *
 * Dónde el mismo idiom SÍ es seguro, y por eso NO se toca acá: `routines` y
 * `trainer_links` usan auto-ids de Firestore (20 chars aleatorios), así que no
 * hay par que armar. Su razonamiento está escrito en el comentario de
 * `routines` y sigue siendo correcto — el que se invirtió es el de los doc id
 * determinísticos.
 *
 * Los casos POSITIVOS de este archivo no son decoración: el disyunto existe
 * para que el cliente pueda preguntar "¿ya hay chat / amistad / nota?" y
 * recibir un snapshot vacío en vez de un permission-denied que la UI muestra
 * como error. Si el acote se pasara de rosca y matara también esa lectura,
 * estos `assertSucceeds` se ponen rojos.
 *
 * Correr contra el emulador (Java 21):
 *   npm --prefix functions run test:rules:emulator
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

const PROJECT_ID = "treino-rules-test-oracle";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

// Ordenados alfabéticamente a propósito: `chats` y `friendships` usan el par
// ORDENADO como doc id, así que `A_B` es el id real y `B_A` no existe nunca.
const A = "aaa1oracle";
const B = "bbb2oracle";
// Tercero sin ninguna relación con A ni con B. No es prefijo de ninguno de los
// dos: un prefijo estricto probaría otra cosa (el bug de `startsWith`) y acá lo
// que se mide es el par exacto.
const OUTSIDER = "mmm5oracle";

const AT = new Date("2026-08-24T12:00:00.000Z");

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

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

/** Siembra un doc con las rules DESHABILITADAS — sólo setup, nunca aserción. */
async function seed(col: string, id: string, body: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(col).doc(id).set(body);
  });
}

// ── chats ───────────────────────────────────────────────────────────────────
//
// El más sensible de los cuatro: la pregunta que respondía es "¿estas dos
// personas se escriben?", y se resuelve con UNA sola llamada por par.
describe("chats — el doc id no puede responder si el chat existe", () => {
  const CHAT_ID = `${A}_${B}`;

  const chatBody = () => ({
    chatId: CHAT_ID,
    members: [A, B],
    createdAt: AT,
  });

  it("un tercero NO lee el chat cuando EXISTE", async () => {
    await seed("chats", CHAT_ID, chatBody());
    await assertFails(asUser(OUTSIDER).collection("chats").doc(CHAT_ID).get());
  });

  it("un tercero NO distingue el caso NO EXISTE (era el oráculo)", async () => {
    await assertFails(asUser(OUTSIDER).collection("chats").doc(CHAT_ID).get());
  });

  it("un miembro SÍ resuelve el chat inexistente (getOrCreate)", async () => {
    await assertSucceeds(asUser(A).collection("chats").doc(CHAT_ID).get());
  });

  it("un miembro SÍ lee el chat existente", async () => {
    await seed("chats", CHAT_ID, chatBody());
    await assertSucceeds(asUser(B).collection("chats").doc(CHAT_ID).get());
  });

  // Regresión del `list`: el acote vive dentro del disyunto `resource == null`,
  // que en una query nunca es probablemente-verdadero. Si el acote llegara a
  // envenenar el OR, la lista de chats de la app se cae entera.
  it("la query por membresía sigue funcionando para un miembro", async () => {
    await seed("chats", CHAT_ID, chatBody());
    await assertSucceeds(
      asUser(A).collection("chats").where("members", "array-contains", A).get(),
    );
  });
});

// ── friendships ─────────────────────────────────────────────────────────────
//
// Colección CONGELADA (ADR-FOLLOW-012): `create`/`update`/`delete` son
// `if false` y el `read` se conserva para el rollback. El oráculo seguía vivo
// igual, sobre la misma data legacy.
describe("friendships — el doc id no puede responder si la amistad existe", () => {
  const PAIR_ID = `${A}_${B}`;

  const friendshipBody = () => ({
    id: PAIR_ID,
    uidA: A,
    uidB: B,
    requesterId: A,
    status: "accepted",
    members: [A, B],
    createdAt: AT,
  });

  it("un tercero NO lee la amistad cuando EXISTE", async () => {
    await seed("friendships", PAIR_ID, friendshipBody());
    await assertFails(
      asUser(OUTSIDER).collection("friendships").doc(PAIR_ID).get(),
    );
  });

  it("un tercero NO distingue el caso NO EXISTE (era el oráculo)", async () => {
    await assertFails(
      asUser(OUTSIDER).collection("friendships").doc(PAIR_ID).get(),
    );
  });

  it("un miembro SÍ resuelve la amistad inexistente (getByPair)", async () => {
    await assertSucceeds(asUser(A).collection("friendships").doc(PAIR_ID).get());
  });

  it("un miembro SÍ lee la amistad existente", async () => {
    await seed("friendships", PAIR_ID, friendshipBody());
    await assertSucceeds(asUser(B).collection("friendships").doc(PAIR_ID).get());
  });
});

// ── follows ─────────────────────────────────────────────────────────────────
//
// Acá el oráculo distinguía "no existe" de "existe y está PENDING", o sea
// exactamente las solicitudes contra cuentas privadas. Una arista `accepted`
// es pública a propósito (alimenta las listas de seguidores) y eso NO cambia.
describe("follows — el doc id no puede responder si la solicitud existe", () => {
  const EDGE_ID = `${A}_${B}`;

  const edgeBody = (status: "pending" | "accepted") => ({
    id: EDGE_ID,
    followerUid: A,
    followeeUid: B,
    status,
    members: [A, B],
    createdAt: AT,
  });

  it("un tercero NO lee una arista PENDING que EXISTE", async () => {
    await seed("follows", EDGE_ID, edgeBody("pending"));
    await assertFails(asUser(OUTSIDER).collection("follows").doc(EDGE_ID).get());
  });

  it("un tercero NO distingue el caso NO EXISTE (era el oráculo)", async () => {
    await assertFails(asUser(OUTSIDER).collection("follows").doc(EDGE_ID).get());
  });

  it("una arista ACCEPTED sigue siendo legible por cualquiera", async () => {
    await seed("follows", EDGE_ID, edgeBody("accepted"));
    await assertSucceeds(
      asUser(OUTSIDER).collection("follows").doc(EDGE_ID).get(),
    );
  });

  it("el follower SÍ resuelve la arista inexistente (¿lo sigo?)", async () => {
    await assertSucceeds(asUser(A).collection("follows").doc(EDGE_ID).get());
  });

  it("el followee SÍ resuelve la arista inexistente (¿me sigue?)", async () => {
    await assertSucceeds(asUser(B).collection("follows").doc(EDGE_ID).get());
  });

  // Regresión de las tres queries que el bloque tiene que seguir probando
  // desde el `where` (ver el comentario largo de la regla).
  it("followingOf / pendingReceivedFor / listas ajenas siguen funcionando", async () => {
    await seed("follows", EDGE_ID, edgeBody("accepted"));
    await assertSucceeds(
      asUser(A).collection("follows").where("followerUid", "==", A).get(),
    );
    await assertSucceeds(
      asUser(B).collection("follows").where("followeeUid", "==", B).get(),
    );
    await assertSucceeds(
      asUser(OUTSIDER)
        .collection("follows")
        .where("status", "==", "accepted")
        .get(),
    );
  });
});

// ── athlete_notes ───────────────────────────────────────────────────────────
//
// Cruzando los dos padrones de uid, este oráculo reconstruía la CARTERA DE
// CLIENTES de cada PF sin leer un solo campo. El acote es por prefijo, igual
// que `storage.rules:athleteFiles`.
describe("athlete_notes — el doc id no puede responder si el PF tiene nota", () => {
  const TRAINER = A;
  const ATHLETE = B;
  const NOTE_ID = `${TRAINER}_${ATHLETE}`;

  const noteBody = () => ({
    trainerId: TRAINER,
    athleteId: ATHLETE,
    note: "nota privada del PF",
  });

  it("otro PF NO lee la nota cuando EXISTE", async () => {
    await seed("athlete_notes", NOTE_ID, noteBody());
    await assertFails(
      asUser(OUTSIDER).collection("athlete_notes").doc(NOTE_ID).get(),
    );
  });

  it("otro PF NO distingue el caso NO EXISTE (era el oráculo)", async () => {
    await assertFails(
      asUser(OUTSIDER).collection("athlete_notes").doc(NOTE_ID).get(),
    );
  });

  it("el alumno de la nota tampoco distingue los dos estados", async () => {
    // El alumno es el SUFIJO del doc id, no el prefijo: la nota es privada del
    // PF y el alumno nunca la ve. Antes del acote, el alumno podía al menos
    // saber si su PF había escrito algo sobre él.
    await assertFails(
      asUser(ATHLETE).collection("athlete_notes").doc(NOTE_ID).get(),
    );
    await seed("athlete_notes", NOTE_ID, noteBody());
    await assertFails(
      asUser(ATHLETE).collection("athlete_notes").doc(NOTE_ID).get(),
    );
  });

  it("el PF dueño SÍ resuelve la nota inexistente (ve «sin nota»)", async () => {
    await assertSucceeds(
      asUser(TRAINER).collection("athlete_notes").doc(NOTE_ID).get(),
    );
  });

  it("el PF dueño SÍ lee su nota existente", async () => {
    await seed("athlete_notes", NOTE_ID, noteBody());
    await assertSucceeds(
      asUser(TRAINER).collection("athlete_notes").doc(NOTE_ID).get(),
    );
  });
});
