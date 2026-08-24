/**
 * Chat de PRE-CONSULTA: la TERCERA vía de `chatCreateOk` (#637).
 *
 * Contexto. Hasta este change un chat sólo se abría por dos vías, y ninguna
 * servía para "un atleta quiere preguntarle algo a un PF que no conoce":
 *
 *   · Coach  — `linkId` de un `trainer_links` active/paused. Exige el vínculo
 *              formal, que es justo lo que el atleta todavía no quiere firmar.
 *   · Social — `followAccepted(destinatario, remitente)`. Es DIRECCIONAL a
 *              propósito (REQ-FOLLOW-012 / ADR-FOLLOW-005) y la dirección que
 *              habilita es la contraria: exigiría que el PF siga al atleta
 *              ANTES de que el atleta pueda escribirle.
 *
 * La rama nueva se selecciona con `kind == 'inquiry'` y habilita el chat sólo
 * si el DESTINATARIO es un PF real (`users.role == 'trainer'`, el único hecho
 * no auto-declarable del sistema) que además PUBLICÓ su perfil de discovery
 * (`trainerPublicProfiles/{uid}`) y no cerró la puerta (`acceptsInquiries`).
 *
 * Los dos términos hacen falta y esta suite lo prueba por separado:
 * `trainerPublicProfiles/create` valida dueño y forma pero NO chequea rol, así
 * que cualquier autenticado puede crearse el suyo — gatear sólo por ese doc
 * sería confiar en un PF auto-declarado.
 *
 * Las tres ramas siguen siendo EXCLUYENTES (ternario anidado, no `||`), y esta
 * suite ancla las dos consecuencias de eso:
 *   · un payload con `kind: 'inquiry'` Y `linkId` cae en la rama Coach, o sea
 *     que el `linkId` se sigue validando y un id fraguado no pasa;
 *   · `kind` queda pineado en el `update`, así que ni un chat social se
 *     convierte en consulta ni una consulta escala a chat de Coach.
 *
 * `withSecurityRulesDisabled` se usa SOLO para sembrar; toda aserción corre en
 * un contexto de cliente autenticado con las rules aplicadas.
 *
 * Correr contra el emulador (Java 21):
 *   npm --prefix functions run test:rules:emulator
 *
 * Issue: #637
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

// projectId propio — las suites de rules comparten un emulador + clearFirestore().
const PROJECT_ID = "treino-rules-test-inquiry637";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AT = new Date("2026-08-24T12:00:00.000Z");

// Los uid están elegidos para que el orden alfabético del par sea estable y el
// chatId quede determinístico sin depender del caso.
const ATHLETE = "aaa-athlete";
/** PF real y publicado — el caso feliz. */
const TRAINER = "zzz-trainer";
/** role 'athlete' PERO con un `trainerPublicProfiles` creado por él mismo. */
const SELF_DECLARED = "yyy-self-declared";
/** role 'trainer' de verdad, pero SIN perfil público (no está en el mapa). */
const UNPUBLISHED = "xxx-unpublished";
/** PF publicado que apagó el kill switch. */
const CLOSED = "www-closed";
/** Otro PF publicado — para el caso PF↔PF. */
const PEER_TRAINER = "uuu-peer-trainer";
/** Ajeno a todo — dueño del `trainer_links` que se intenta fraguar. */
const OUTSIDER = "vvv-outsider";

const sorted = (a: string, b: string) => (a < b ? [a, b] : [b, a]);
const chatIdOf = (a: string, b: string) => sorted(a, b).join("_");
const edgeId = (follower: string, followee: string) => `${follower}_${followee}`;

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

// ── Seeding (rules deshabilitadas, sólo setup) ──────────────────────────────

async function seedUser(uid: string, role: "athlete" | "trainer") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("users")
      .doc(uid)
      .set({ uid, role, email: `${uid}@treino.test`, createdAt: AT });
  });
}

async function seedTrainerPublicProfile(
  uid: string,
  extra: Record<string, unknown> = {},
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("trainerPublicProfiles")
      .doc(uid)
      .set({ uid, displayName: "PF de prueba", ...extra });
  });
}

async function seedEdge(follower: string, followee: string) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("follows")
      .doc(edgeId(follower, followee))
      .set({
        id: edgeId(follower, followee),
        followerUid: follower,
        followeeUid: followee,
        status: "accepted",
        members: [follower, followee],
        createdAt: AT,
      });
  });
}

async function seedLink(
  linkId: string,
  trainerId: string,
  athleteId: string,
  status = "active",
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("trainer_links")
      .doc(linkId)
      .set({ trainerId, athleteId, status, requestedAt: 1 });
  });
}

function chatDoc(a: string, b: string, extra: Record<string, unknown> = {}) {
  return {
    chatId: chatIdOf(a, b),
    members: sorted(a, b),
    createdAt: 1,
    ...extra,
  };
}

async function seedChat(a: string, b: string, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("chats")
      .doc(chatIdOf(a, b))
      .set(chatDoc(a, b, extra));
  });
}

/** Un PF publicado y contactable: rol real + perfil de discovery. */
async function seedPublishedTrainer(
  uid: string,
  extra: Record<string, unknown> = {},
) {
  await seedUser(uid, "trainer");
  await seedTrainerPublicProfile(uid, extra);
}

// ── Operaciones bajo rules ──────────────────────────────────────────────────

/** `chats/create` — lo que hace el CTA CONSULTAR del perfil del PF. */
function openInquiry(self: string, other: string, extra = {}) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(self, other))
    .set(chatDoc(self, other, { kind: "inquiry", ...extra }));
}

/** `chats/create` sin la marca — cae en la rama social. */
function openPlainChat(self: string, other: string, extra = {}) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(self, other))
    .set(chatDoc(self, other, extra));
}

function sendMessage(self: string, other: string, msgId = "m1") {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(self, other))
    .collection("messages")
    .doc(msgId)
    .set({ senderId: self, text: "¿cuánto sale el mes?", createdAt: AT });
}

function updateChat(self: string, other: string, patch: Record<string, unknown>) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(self, other))
    .update(patch);
}

const previewPatch = (self: string) => ({
  lastMessageAt: AT,
  lastMessageText: "¿cuánto sale el mes?",
  lastMessageSenderId: self,
});

// ── chats/create — lo que la vía nueva DEBE permitir ────────────────────────
describe("chats/create — consulta permitida (#637)", () => {
  it("el atleta abre una consulta con un PF publicado, sin vínculo ni follow", async () => {
    await seedPublishedTrainer(TRAINER);
    await assertSucceeds(openInquiry(ATHLETE, TRAINER));
  });

  it("acceptsInquiries: true explícito también deja abrir la consulta", async () => {
    // El caso de arriba cubre el default: el perfil legacy no trae la clave y
    // la regla la lee con `get('acceptsInquiries', true)`, así que la feature
    // no nace apagada para los perfiles anteriores a este change.
    await seedPublishedTrainer(TRAINER, { acceptsInquiries: true });
    await assertSucceeds(openInquiry(ATHLETE, TRAINER));
  });

  it("un PF puede consultarle a otro PF publicado", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedPublishedTrainer(PEER_TRAINER);
    await assertSucceeds(openInquiry(PEER_TRAINER, TRAINER));
  });
});

// ── chats/create — lo que la vía nueva DEBE denegar ─────────────────────────
describe("chats/create — consulta denegada (#637)", () => {
  // El término `users.role == 'trainer'` es el que sostiene esta celda. Sin
  // él, `trainerPublicProfiles/create` (owner-only, SIN chequeo de rol) le
  // alcanza a cualquiera para volverse "PF" y la rama abriría chat de
  // cualquiera con cualquiera, que es exactamente lo que no puede pasar.
  it("DENIEGA la consulta a un PF AUTO-DECLARADO (perfil público pero role athlete)", async () => {
    await seedUser(SELF_DECLARED, "athlete");
    await seedTrainerPublicProfile(SELF_DECLARED);
    await assertFails(openInquiry(ATHLETE, SELF_DECLARED));
  });

  // El término `exists(trainerPublicProfiles/{other})` es el que sostiene esta
  // celda: un PF que nunca publicó no está en el mapa ni en la búsqueda, así
  // que no debe ser alcanzable por doc id.
  it("DENIEGA la consulta a un PF real que NO publicó su perfil de discovery", async () => {
    await seedUser(UNPUBLISHED, "trainer");
    await assertFails(openInquiry(ATHLETE, UNPUBLISHED));
  });

  it("DENIEGA la consulta si el PF apagó acceptsInquiries", async () => {
    await seedPublishedTrainer(CLOSED, { acceptsInquiries: false });
    await assertFails(openInquiry(ATHLETE, CLOSED));
  });

  it("DENIEGA la consulta a un usuario cualquiera, sin perfil de PF ni rol", async () => {
    await seedUser(OUTSIDER, "athlete");
    await assertFails(openInquiry(ATHLETE, OUTSIDER));
  });

  // Direccionalidad: la rama mira SIEMPRE al otro. Un PF no puede usarla para
  // escribirle en frío a un atleta — la vía nueva es hacia el PF, no desde él.
  it("DENIEGA que un PF abra una consulta CONTRA un atleta (dirección inversa)", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedUser(ATHLETE, "athlete");
    await assertFails(openInquiry(TRAINER, ATHLETE));
  });

  // Sin la marca no hay rama nueva: el chat cae en la social y necesita follow.
  it("DENIEGA abrir el chat con un PF publicado SIN la marca kind: 'inquiry'", async () => {
    await seedPublishedTrainer(TRAINER);
    await assertFails(openPlainChat(ATHLETE, TRAINER));
  });
});

// ── Exclusividad de las ramas ───────────────────────────────────────────────
describe("chats/create — las tres ramas siguen siendo excluyentes (#637)", () => {
  // La invariante del archivo: un doc de chat sólo lleva `linkId` si nombra un
  // link válido. Si la rama nueva fuese un `|| esConsulta`, este payload haría
  // true la disyunción y el linkId inventado quedaría persistido, regalando
  // escritura permanente vía `senderMayPost`.
  it("DENIEGA kind:'inquiry' + linkId INVENTADO — gana la rama Coach y el link no existe", async () => {
    await seedPublishedTrainer(TRAINER);
    await assertFails(
      openInquiry(ATHLETE, TRAINER, { linkId: "link-que-no-existe" }),
    );
  });

  it("DENIEGA kind:'inquiry' + linkId REAL pero de OTRO par", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedLink("link-ajeno", TRAINER, OUTSIDER);
    await assertFails(openInquiry(ATHLETE, TRAINER, { linkId: "link-ajeno" }));
  });

  it("un chat de Coach legítimo sigue funcionando (regresión de la rama 1)", async () => {
    await seedLink("link-ok", TRAINER, ATHLETE);
    await assertSucceeds(
      openPlainChat(ATHLETE, TRAINER, { linkId: "link-ok" }),
    );
  });

  it("un chat social legítimo sigue funcionando (regresión de la rama 2)", async () => {
    await seedEdge(TRAINER, ATHLETE); // el destinatario sigue a quien abre
    await assertSucceeds(openPlainChat(ATHLETE, TRAINER));
  });
});

// ── chats/update — la marca es inmutable ────────────────────────────────────
describe("chats/update — kind pineado, sin escalada (#637)", () => {
  it("DENIEGA convertir un chat SOCIAL en consulta agregando kind", async () => {
    await seedEdge(TRAINER, ATHLETE);
    await seedChat(ATHLETE, TRAINER);
    await assertFails(updateChat(ATHLETE, TRAINER, { kind: "inquiry" }));
  });

  it("DENIEGA escalar una consulta a chat de Coach agregando linkId", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedLink("link-ok", TRAINER, ATHLETE);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    // Incluso con un link REAL entre los dos: la escalada se hace re-creando
    // el doc, no parcheándolo, o el pin de `linkId` deja de valer nada.
    await assertFails(updateChat(ATHLETE, TRAINER, { linkId: "link-ok" }));
  });

  it("DENIEGA borrar la marca para hacer pasar la consulta por chat social", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    await assertFails(updateChat(ATHLETE, TRAINER, { kind: "coach" }));
  });

  it("PERMITE el update de preview dentro de la consulta (chatWriterOk)", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    await assertSucceeds(updateChat(ATHLETE, TRAINER, previewPatch(ATHLETE)));
  });

  it("DENIEGA el update de preview en un chat social sin follow (no aflojamos nada)", async () => {
    await seedChat(ATHLETE, TRAINER);
    await assertFails(updateChat(ATHLETE, TRAINER, previewPatch(ATHLETE)));
  });
});

// ── messages/create — los dos lados pueden hablar ───────────────────────────
describe("chats/messages — la consulta habilita la conversación (#637)", () => {
  it("el atleta manda el primer mensaje sin vínculo ni follow", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    await assertSucceeds(sendMessage(ATHLETE, TRAINER));
  });

  it("el PF puede contestar la consulta", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    await assertSucceeds(sendMessage(TRAINER, ATHLETE, "m2"));
  });

  it("un tercero ajeno NO puede escribir en la consulta", async () => {
    await seedPublishedTrainer(TRAINER);
    await seedChat(ATHLETE, TRAINER, { kind: "inquiry" });
    await assertFails(
      testEnv
        .authenticatedContext(OUTSIDER)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(ATHLETE, TRAINER))
        .collection("messages")
        .doc("m3")
        .set({ senderId: OUTSIDER, text: "hola", createdAt: AT }),
    );
  });

  it("un chat social sin follow sigue sin poder mandar mensajes (regresión)", async () => {
    await seedChat(ATHLETE, TRAINER);
    await assertFails(sendMessage(ATHLETE, TRAINER));
  });
});

// ── Anti-spam estructural ───────────────────────────────────────────────────
describe("chats/create — un solo chat de consulta por par (#637)", () => {
  // El tope es estructural, no una regla: el doc id es `sortedUids.join('_')`,
  // así que el par no puede tener dos consultas abiertas. El segundo `create`
  // sobre el mismo id es un update encubierto y lo agarra el pin de `kind`.
  it("el segundo create sobre el mismo par no puede reabrir la consulta con otra forma", async () => {
    await seedPublishedTrainer(TRAINER);
    await assertSucceeds(openInquiry(ATHLETE, TRAINER));
    // Re-crear con linkId fraguado: `set` sobre un doc existente es un update,
    // y el pin de `linkId`/`kind` lo deniega.
    await assertFails(
      openInquiry(ATHLETE, TRAINER, { linkId: "link-que-no-existe" }),
    );
  });
});
