/**
 * Enforcement real del gate de relación del chat 1-1.
 *
 * Origen (QA-CHAT-004): un chat sólo puede abrirse entre dos usuarios con una
 * relación real. Antes de ese fix, `chats/create` sólo validaba la forma del
 * doc y cualquier autenticado podía abrir un chat con —y escribirle a—
 * cualquiera.
 *
 * Cambio de producto del 2026-10-21 (PR #1607), que REEMPLAZA a REQ-FOLLOW-012
 * / ADR-FOLLOW-005 (antes: «X le escribe a Y sólo si Y sigue a X», chequeado
 * en cada mensaje):
 *
 *   | situación                                         | abrir chat |
 *   | ------------------------------------------------- | ---------- |
 *   | lo sigo (arista `yo_otro` aceptada), perfil público | sí       |
 *   | lo sigo y me aceptó, perfil privado               | sí         |
 *   | perfil privado con solicitud pendiente            | no         |
 *   | perfil privado sin relación                       | no         |
 *   | perfil público y no lo sigo                       | sí         |
 *
 *   Una vez creado el chat, los DOS miembros escriben sin requisito de follow:
 *   el que recibe responde aunque no siga al otro. Lo único que corta una
 *   conversación abierta es el BLOQUEO, que además gana sobre cualquier rama
 *   al abrirla (vínculo, consulta o follow).
 *
 * Lo que NO cambia: `chats/read`, `messages/read` y `chats/update`
 * (`lastRead`) siguen gateados por membresía, y `linkId` no se puede fraguar.
 *
 * `withSecurityRulesDisabled` se usa SOLO para sembrar; toda aserción corre en
 * un contexto de cliente autenticado con las rules aplicadas.
 *
 * Correr contra el emulador (Java 21):
 *   npm --prefix functions run test:rules:emulator
 *
 * REQ: QA-CHAT-004 · cambio de producto 2026-10-21 (reemplaza REQ-FOLLOW-012)
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
const PROJECT_ID = "treino-rules-test-chat004";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_FOLLOWS = "follows";

// `emulators:exec` exporta FIRESTORE_EMULATOR_HOST; sin él, el 8080 de siempre.
const [EMULATOR_HOST, EMULATOR_PORT] = (() => {
  const [h, p] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");
  return [h, Number(p)] as const;
})();

const ATHLETE = "aaa-athlete";
const TRAINER = "zzz-trainer";
const STRANGER = "mmm-stranger";
// Par social para los casos de asimetría. U1 < U2 alfabéticamente.
const U1 = "aaa-user-one";
const U2 = "bbb-user-two";
// Ajeno a todo chat — ancla de que read/update siguen siendo por membresía.
const OUTSIDER = "qqq-outsider";

const AT = new Date("2026-08-04T12:00:00.000Z");

// chatId es los dos miembros ordenados y unidos con "_".
const sorted = (a: string, b: string) => (a < b ? [a, b] : [b, a]);
const chatIdOf = (a: string, b: string) => sorted(a, b).join("_");

/** Doc id de `follows`: dirigido, SIN ordenar. */
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
      host: EMULATOR_HOST,
      port: EMULATOR_PORT,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

/** Siembra una arista dirigida (rules deshabilitadas, sólo setup). */
async function seedEdge(
  follower: string,
  followee: string,
  status: "pending" | "accepted",
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_FOLLOWS)
      .doc(edgeId(follower, followee))
      .set(edgeBody(follower, followee, status));
  });
}

/** Borra una arista — simula el unfollow (rules deshabilitadas, sólo setup). */
async function removeEdge(follower: string, followee: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_FOLLOWS)
      .doc(edgeId(follower, followee))
      .delete();
  });
}

async function seedLink(
  linkId: string,
  trainerId: string,
  athleteId: string,
  status: string,
): Promise<void> {
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

/**
 * Siembra un chat YA EXISTENTE (rules deshabilitadas), para los casos de
 * `messages/create` y `chats/update` que no pasan por el `create`.
 */
async function seedChat(
  a: string,
  b: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("chats")
      .doc(chatIdOf(a, b))
      .set(chatDoc(a, b, extra));
  });
}

/** Intento de `chats/create` autenticado como [self]. */
function createChat(self: string, a: string, b: string, extra = {}) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .set(chatDoc(a, b, extra));
}

/** Intento de `messages/create` autenticado como [self]. */
function sendMessage(self: string, a: string, b: string, msgId = "m1") {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .collection("messages")
    .doc(msgId)
    .set({ senderId: self, text: "hola", createdAt: AT });
}

function readChat(self: string, a: string, b: string) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .get();
}

function readMessage(self: string, a: string, b: string, msgId = "seeded") {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .collection("messages")
    .doc(msgId)
    .get();
}

/**
 * `chats/update` con los campos de preview — lo que el cliente escribe en el
 * MISMO batch que el mensaje (`chat_repository.dart:163-167`).
 */
function updatePreview(self: string, a: string, b: string, text = "hola") {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .update({
      lastMessageAt: AT,
      lastMessageText: text,
      lastMessageSenderId: self,
    });
}

/** `chats/update` con `lastRead` — el camino de "marcar como leído". */
function markRead(self: string, a: string, b: string) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .update({ [`lastRead.${self}`]: AT });
}

/** Siembra `userPublicProfiles/{uid}`. `undefined` = perfil viejo sin el campo. */
async function seedProfile(uid: string, isProfilePublic?: boolean): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("userPublicProfiles")
      .doc(uid)
      .set({
        uid,
        displayName: uid,
        ...(isProfilePublic === undefined ? {} : { isProfilePublic }),
      });
  });
}

/** Siembra `blocks/{blocker}_{blocked}` (las rules sólo miran que exista). */
async function seedBlock(blocker: string, blocked: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("blocks")
      .doc(`${blocker}_${blocked}`)
      .set({
        id: `${blocker}_${blocked}`,
        blockerUid: blocker,
        blockedUid: blocked,
        members: [blocker, blocked],
        createdAt: AT,
      });
  });
}

// ── chats/create — una fila de la tabla por caso ───────────────────────────
describe("chats/create — quién puede abrir un chat social", () => {
  it("lo sigo (arista aceptada) y su perfil es público → permite", async () => {
    await seedProfile(U2, true);
    await seedEdge(U1, U2, "accepted");
    await assertSucceeds(createChat(U1, U1, U2));
  });

  it("lo sigo, su perfil es privado y me aceptó → permite", async () => {
    await seedProfile(U2, false);
    await seedEdge(U1, U2, "accepted");
    await assertSucceeds(createChat(U1, U1, U2));
  });

  it("perfil privado con mi solicitud PENDIENTE → DENIEGA", async () => {
    await seedProfile(U2, false);
    await seedEdge(U1, U2, "pending");
    await assertFails(createChat(U1, U1, U2));
  });

  it("perfil privado sin ninguna relación → DENIEGA", async () => {
    await seedProfile(U2, false);
    await assertFails(createChat(U1, U1, U2));
  });

  it("perfil público y no lo sigo → permite", async () => {
    await seedProfile(U2, true);
    await assertSucceeds(createChat(U1, U1, U2));
  });

  it("perfil anterior al campo isProfilePublic cuenta como público", async () => {
    // Mismo default que el auto-accept del `create` de `follows`.
    await seedProfile(U2);
    await assertSucceeds(createChat(U1, U1, U2));
  });

  it("que ÉL me siga no alcanza si su perfil es privado (dirección vieja)", async () => {
    // Antes del 2026-10-21 esto era lo que habilitaba; ahora no.
    await seedProfile(U2, false);
    await seedEdge(U2, U1, "accepted");
    await assertFails(createChat(U1, U1, U2));
  });

  it("sin perfil público (cuenta borrada) ni follow → DENIEGA", async () => {
    await assertFails(createChat(ATHLETE, ATHLETE, STRANGER));
  });

  it("un bloqueo en CUALQUIER dirección gana sobre follow y perfil público", async () => {
    await seedProfile(U2, true);
    await seedEdge(U1, U2, "accepted");
    await seedBlock(U2, U1);
    await assertFails(createChat(U1, U1, U2));

    await testEnv.clearFirestore();
    await seedProfile(U2, true);
    await seedEdge(U1, U2, "accepted");
    await seedBlock(U1, U2);
    await assertFails(createChat(U1, U1, U2));
  });

  it("el bloqueo también gana sobre un trainer_link activo", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedBlock(TRAINER, ATHLETE);
    await assertFails(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" }),
    );
  });
});

describe("chats/create — rama trainer_link (sin cambios)", () => {
  it("permite un chat coach↔atleta respaldado por un trainer_link activo", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertSucceeds(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" }),
    );
    // ...y el lado del trainer también puede abrirlo.
    await testEnv.clearFirestore();
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertSucceeds(
      createChat(TRAINER, ATHLETE, TRAINER, { linkId: "link-1" }),
    );
  });

  it("DENIEGA un linkId cuyos miembros no coinciden con los del chat", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertFails(
      createChat(ATHLETE, ATHLETE, STRANGER, { linkId: "link-1" }),
    );
  });

  it("DENIEGA un linkId que apunta a un link no activo (pending)", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "pending");
    await assertFails(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" }),
    );
  });

  it("DENIEGA un linkId inexistente", async () => {
    await assertFails(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "does-not-exist" }),
    );
  });
});

// ── messages/create — en un chat existente escriben los dos ─────────────────
describe("messages/create — sin requisito de follow una vez abierto", () => {
  it("el destinatario responde aunque no siga al que abrió el chat", async () => {
    // U1 sigue a U2 (privado, lo aceptó) y abre el chat. U2 no sigue a U1.
    await seedProfile(U2, false);
    await seedEdge(U1, U2, "accepted");
    await assertSucceeds(createChat(U1, U1, U2));

    await assertSucceeds(sendMessage(U1, U1, U2, "from-u1"));
    await assertSucceeds(sendMessage(U2, U1, U2, "from-u2"));
  });

  it("un chat preexistente sin ninguna arista sigue funcionando para los dos", async () => {
    // Antes (SCENARIO-841) quedaba mudo para los dos.
    await seedChat(U1, U2);
    await assertSucceeds(sendMessage(U1, U1, U2, "from-u1"));
    await assertSucceeds(sendMessage(U2, U1, U2, "from-u2"));
  });

  it("dejar de seguir NO corta un chat ya abierto", async () => {
    await seedProfile(U2, false);
    await seedEdge(U1, U2, "accepted");
    await assertSucceeds(createChat(U1, U1, U2));
    await removeEdge(U1, U2);
    await assertSucceeds(sendMessage(U1, U1, U2, "despues"));
  });

  it("un bloqueo corta la escritura de los DOS lados", async () => {
    await seedChat(U1, U2);
    await seedBlock(U2, U1);
    await assertFails(sendMessage(U1, U1, U2, "from-u1"));
    await assertFails(sendMessage(U2, U1, U2, "from-u2"));
  });

  it("los DOS conservan la lectura y el marcar como leído con un bloqueo", async () => {
    await seedChat(U1, U2);
    await seedBlock(U2, U1);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .collection("messages")
        .doc("seeded")
        .set({ senderId: U2, text: "previo", createdAt: AT });
    });
    await assertSucceeds(readChat(U1, U1, U2));
    await assertSucceeds(readMessage(U1, U1, U2));
    await assertSucceeds(markRead(U1, U1, U2));
    await assertSucceeds(markRead(U2, U1, U2));
  });

  it("DENIEGA a un tercero ajeno leer o escribir en el chat", async () => {
    await seedChat(U1, U2);
    await assertFails(readChat(OUTSIDER, U1, U2));
    await assertFails(sendMessage(OUTSIDER, U1, U2, "from-outsider"));
  });

  it("DENIEGA enviar un mensaje firmado con el uid de otro", async () => {
    await seedChat(U1, U2);
    await assertFails(
      testEnv
        .authenticatedContext(U1)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .collection("messages")
        .doc("forged")
        .set({ senderId: U2, text: "suplantado", createdAt: AT }),
    );
  });
});

// ── `linkId` no se puede fraguar ────────────────────────────────────────────
// Invariante: un doc de chat sólo lleva `linkId` si nombra un link válido. La
// app usa esa clave para tratar al chat como de Coach.
describe("chats — `linkId` no se puede fraguar", () => {
  it("DENIEGA crear un chat social con un linkId inventado", async () => {
    // Si la rama social fuera un `||` con la del link, el linkId del payload
    // nunca se validaría y quedaría persistido.
    await seedProfile(U2, true);
    await seedEdge(U1, U2, "accepted");
    await assertFails(createChat(U1, U1, U2, { linkId: "inventado" }));
  });

  it("DENIEGA agregarle un linkId a un chat social ya existente", async () => {
    await seedChat(U1, U2);
    await assertFails(
      testEnv
        .authenticatedContext(U1)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .update({ linkId: "inventado" }),
    );
  });

  it("DENIEGA borrar el linkId de un chat de trainer_link", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedChat(ATHLETE, TRAINER, { linkId: "link-1" });
    await assertFails(
      testEnv
        .authenticatedContext(ATHLETE)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(ATHLETE, TRAINER))
        .update({ linkId: null }),
    );
  });
});

// ── El preview del chat sigue al mismo permiso que el mensaje ───────────────
// Sin esto, el bloqueado no logra escribir el mensaje pero SÍ `lastMessageText`
// en el doc del chat, que es lo que la otra persona ve en su lista, con badge.
describe("chats/update — el preview sigue al permiso de escritura", () => {
  beforeEach(async () => {
    await seedChat(U1, U2);
  });

  it("sin bloqueo, los dos actualizan el preview sin ninguna arista", async () => {
    await assertSucceeds(updatePreview(U1, U1, U2));
    await assertSucceeds(updatePreview(U2, U1, U2));
  });

  it("DENIEGA al lado bloqueado empujar texto al preview del otro", async () => {
    await seedBlock(U2, U1);
    await assertFails(updatePreview(U1, U1, U2, "texto no deseado"));
  });

  it("DENIEGA al lado bloqueado agregar cualquier otro campo", async () => {
    // Allowlist: si mañana se agrega otro campo al doc, queda denegado por
    // defecto en vez de colarse.
    await seedBlock(U2, U1);
    await assertFails(
      testEnv
        .authenticatedContext(U1)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .update({ campoNuevo: "x" }),
    );
  });

  it("en un chat de Coach los dos actualizan el preview", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedChat(ATHLETE, TRAINER, { linkId: "link-1" });
    await assertSucceeds(updatePreview(ATHLETE, ATHLETE, TRAINER));
    await assertSucceeds(updatePreview(TRAINER, ATHLETE, TRAINER));
  });
});

describe("messages/create — la rama trainer_link queda intacta (SCENARIO-842)", () => {
  it("con linkId y CERO aristas follows, los dos envían", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedChat(ATHLETE, TRAINER, { linkId: "link-1" });

    await assertSucceeds(sendMessage(ATHLETE, ATHLETE, TRAINER, "from-athlete"));
    await assertSucceeds(sendMessage(TRAINER, ATHLETE, TRAINER, "from-trainer"));
  });

  it("DENIEGA igual a un tercero ajeno al chat de trainer_link", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedChat(ATHLETE, TRAINER, { linkId: "link-1" });

    await assertFails(sendMessage(OUTSIDER, ATHLETE, TRAINER, "from-outsider"));
  });
});
