/**
 * Enforcement real del gate de relación del chat 1-1 — ahora DIRECCIONAL y en
 * DOS superficies.
 *
 * Origen (QA-CHAT-004): un chat sólo podía abrirse entre dos usuarios con una
 * relación real — amistad ACEPTADA o `trainer_link` activo verificado. Antes de
 * ese fix, `chats/create` sólo validaba la forma del doc y cualquier
 * autenticado podía abrir un chat con —y escribirle a— cualquiera.
 *
 * Cambio de este PR (`follow-model`, PR3a, LD-08 / ADR-FOLLOW-005):
 *
 *   **X le puede escribir a Y sólo si Y sigue a X.** El permiso de ESCRITURA lo
 *   da la arista ENTRANTE: `follows/{destinatario}_{remitente}` aceptada.
 *
 * Y —esto es lo que obliga a tocar dos reglas— el gate se muda a `messages`:
 *
 *   VERIFICADO EN EL CÓDIGO ANTES DE ESCRIBIR ESTO: hoy `chatRelationshipOk` se
 *   invoca en UN solo lugar (`chats/create`), `messages/create` gatea SÓLO por
 *   membresía, y borrar la amistad no toca el chat. O sea que **hoy eliminar
 *   una amistad NO corta un chat que ya existe**: los dos se siguen escribiendo
 *   indefinidamente y lo único que se rompe es abrir un chat NUEVO.
 *
 *   Por lo tanto esto es una restricción NUEVA, no la conservación de una
 *   vigente. Y es la única forma de expresarla: la asimetría es DENTRO del
 *   mismo chat (uno escribe, el otro no), y una regla que corre una sola vez
 *   —al crear el doc— no puede producir dos permisos distintos para el mismo
 *   documento.
 *
 * Lo que NO cambia, y se testea explícitamente para que nadie lo apriete de
 * rebote: `chats/read`, `messages/read` y `chats/update` (`lastRead`) siguen
 * gateados por membresía. El lado que perdió la escritura CONSERVA la lectura
 * completa de la conversación y puede marcarla como leída.
 *
 * `withSecurityRulesDisabled` se usa SOLO para sembrar; toda aserción corre en
 * un contexto de cliente autenticado con las rules aplicadas.
 *
 * Correr contra el emulador (Java 21):
 *   npm --prefix functions run test:rules:emulator
 *
 * REQ: REQ-FOLLOW-012 · SCENARIO-815/839/841/842
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
 * Siembra un chat YA EXISTENTE (rules deshabilitadas). Necesario para los casos
 * de `messages/create`: sin esto no se puede probar la asimetría dentro de un
 * chat, que es justo lo que este PR agrega.
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

// ── chats/create ────────────────────────────────────────────────────────────
describe("chats/create — gate direccional (REQ-FOLLOW-012)", () => {
  // El destinatario me sigue → puedo abrir el chat, porque abrir un chat es
  // poder mandar el primer mensaje.
  it("permite abrir el chat cuando el DESTINATARIO sigue al que lo abre", async () => {
    await seedEdge(U2, U1, "accepted"); // U2 sigue a U1
    await assertSucceeds(createChat(U1, U1, U2));
  });

  // SCENARIO-815 (superficie create). Mata dos mutaciones a la vez: el id
  // ORDENADO (sorted(U1,U2) === edgeId(U1,U2), o sea que un lookup ordenado
  // encontraría esta arista) y el OR de las dos direcciones.
  it("DENIEGA abrir el chat con sólo la arista SALIENTE (yo lo sigo, él no a mí)", async () => {
    await seedEdge(U1, U2, "accepted"); // U1 sigue a U2, U2 NO sigue a U1
    await assertFails(createChat(U1, U1, U2));
  });

  it("DENIEGA cuando la arista entrante está pendiente y no aceptada", async () => {
    await seedEdge(U2, U1, "pending");
    await assertFails(createChat(U1, U1, U2));
  });

  it("DENIEGA entre desconocidos sin ninguna arista", async () => {
    await assertFails(createChat(ATHLETE, ATHLETE, STRANGER));
  });

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

// ── messages/create — el gate NUEVO ─────────────────────────────────────────
describe("messages/create — asimetría dentro del mismo chat (SCENARIO-815)", () => {
  beforeEach(async () => {
    await seedChat(U1, U2);
    // U1 sigue a U2. U2 NO sigue a U1.
    await seedEdge(U1, U2, "accepted");
  });

  it("permite enviar a U2, porque su destinatario U1 lo sigue", async () => {
    await assertSucceeds(sendMessage(U2, U1, U2, "from-u2"));
  });

  it("DENIEGA enviar a U1, porque su destinatario U2 no lo sigue", async () => {
    await assertFails(sendMessage(U1, U1, U2, "from-u1"));
  });

  it("los DOS siguen leyendo el chat y sus mensajes", async () => {
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
    await assertSucceeds(readChat(U2, U1, U2));
    await assertSucceeds(readMessage(U1, U1, U2));
    await assertSucceeds(readMessage(U2, U1, U2));
  });

  it("el lado bloqueado igual puede marcar como leído", async () => {
    // Si `lastRead` colgara del permiso de escritura, el badge de no-leídos le
    // quedaría clavado para siempre al lado bloqueado.
    await assertSucceeds(markRead(U1, U1, U2));
  });

  it("DENIEGA a un tercero ajeno leer o escribir en el chat", async () => {
    await assertFails(readChat(OUTSIDER, U1, U2));
    await assertFails(sendMessage(OUTSIDER, U1, U2, "from-outsider"));
  });

  it("DENIEGA enviar un mensaje firmado con el uid de otro", async () => {
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

describe("messages/create — par migrado mutuo (SCENARIO-839)", () => {
  it("los DOS envían cuando existen las dos aristas aceptadas", async () => {
    // Es exactamente lo que produce la migración sobre una amistad `accepted`
    // (REQ-FOLLOW-015): dos aristas. Garantiza que el chat de un par migrado
    // queda igual que antes del flip — nadie pierde la palabra el día 1.
    await seedChat(U1, U2);
    await seedEdge(U1, U2, "accepted");
    await seedEdge(U2, U1, "accepted");

    await assertSucceeds(sendMessage(U1, U1, U2, "from-u1"));
    await assertSucceeds(sendMessage(U2, U1, U2, "from-u2"));
  });
});

describe("messages/create — chat preexistente sin aristas (SCENARIO-841)", () => {
  // REGRESIÓN ACEPTADA EXPLÍCITAMENTE POR EL DUEÑO (R12 / A14), testeada a
  // propósito y no descubierta en producción: hoy este chat funciona para los
  // dos, porque el gate no corre en `messages`. Después del flip queda MUDO
  // para los dos y LEGIBLE para los dos.
  beforeEach(async () => {
    await seedChat(U1, U2);
  });

  it("DENIEGA enviar a los dos lados", async () => {
    await assertFails(sendMessage(U1, U1, U2, "from-u1"));
    await assertFails(sendMessage(U2, U1, U2, "from-u2"));
  });

  it("los DOS conservan la lectura del chat", async () => {
    await assertSucceeds(readChat(U1, U1, U2));
    await assertSucceeds(readChat(U2, U1, U2));
  });

  it("los DOS conservan el marcar como leído", async () => {
    await assertSucceeds(markRead(U1, U1, U2));
    await assertSucceeds(markRead(U2, U1, U2));
  });
});

// ── `linkId` NO es una puerta trasera ───────────────────────────────────────
// `senderMayPost` escapa por `'linkId' in chat`, que es SÓLO presencia de la
// clave: no verifica el link. Y `linkId` lo escribe el CLIENTE
// (`chat_repository.dart:80`). Si un miembro puede plantar la clave, se
// auto-otorga escritura permanente y el gate direccional entero queda
// decorativo — justo lo que REQ-FOLLOW-012 declara que NO puede pasar.
//
// El agujero tiene dos vías, y las dos se cierran en el momento de la ESCRITURA
// del doc de chat, no en `senderMayPost`: así el chat del Coach sigue costando
// una sola llamada de acceso, que es lo que el diseño pide.
describe("chats — `linkId` no se puede fraguar (REQ-FOLLOW-012)", () => {
  it("DENIEGA crear un chat social con un linkId inventado", async () => {
    // Vía 1: el OR de chatCreateOk cortocircuitaba. Si la rama social daba
    // true, el linkId del payload NUNCA se validaba y quedaba persistido.
    await seedEdge(U2, U1, "accepted"); // U2 sigue a U1 → la rama social pasa
    await assertFails(createChat(U1, U1, U2, { linkId: "inventado" }));
  });

  it("DENIEGA agregarle un linkId a un chat social ya existente", async () => {
    // Vía 2: `chats/update` no tenía allowlist de claves ni pin sobre linkId,
    // así que cualquier miembro se lo agregaba con un update de una línea.
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

  it("EXPLOIT COMPLETO: dejar de seguir corta la escritura de verdad", async () => {
    // La cadena que el hallazgo describía de punta a punta. Si alguna de las
    // dos vías queda abierta, el último assert se pone verde y el requisito
    // entero del change es decorativo.
    await seedEdge(U2, U1, "accepted"); // U2 sigue a U1 → U1 puede abrir y escribir
    await assertSucceeds(createChat(U1, U1, U2));
    await assertSucceeds(sendMessage(U1, U1, U2, "antes"));

    // U1 intenta plantarse la puerta trasera por las dos vías.
    await assertFails(
      testEnv
        .authenticatedContext(U1)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .update({ linkId: "inventado" }),
    );

    // U2 deja de seguir a U1.
    await removeEdge(U2, U1);

    // Una sola acción de U2 tiene que alcanzar para callarlo.
    await assertFails(sendMessage(U1, U1, U2, "despues"));
  });

  it("un chat de Coach entre dos que ADEMÁS se siguen sigue funcionando", async () => {
    // Guarda contra arreglar de más: el link válido manda, exista o no arista.
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedEdge(TRAINER, ATHLETE, "accepted");
    await seedEdge(ATHLETE, TRAINER, "accepted");

    await assertSucceeds(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" }),
    );
    await assertSucceeds(sendMessage(ATHLETE, ATHLETE, TRAINER, "m-athlete"));
  });

  it("el `lastRead` del lado bloqueado sigue funcionando tras el pin de linkId", async () => {
    // El pin nuevo no puede romper "marcar como leído", que es lo único que el
    // lado sin escritura conserva sobre el doc del chat (design §3.3.4).
    await seedChat(U1, U2);
    await assertSucceeds(markRead(U1, U1, U2));
    await assertSucceeds(markRead(U2, U1, U2));
  });
});

// ── El preview del chat sigue al mismo permiso que el mensaje ───────────────
// Sin esto, el gate de `messages/create` se puede rodear por el costado: el
// lado bloqueado no logra escribir el mensaje, pero SÍ escribe
// `lastMessageText` en el doc del chat, que es el texto que la otra persona ve
// en su lista de chats — con badge de no-leído incluido. O sea que "no te puede
// escribir" era falso: no te puede escribir EN LA CONVERSACIÓN, pero te hace
// aparecer texto arbitrario en la pantalla que mirás primero.
//
// Por la app no pasa (el cliente manda mensaje y preview en el mismo batch, y
// si el mensaje se deniega cae el batch entero), pero por SDK crudo sí, que es
// justo el modelo de amenaza que las rules existen para cubrir.
//
// DESVÍO DELIBERADO de design §3.3.4, que decía "`chats/update`: membresía, SIN
// CAMBIOS". El motivo que da esa sección —que el lado bloqueado tiene que poder
// marcar como leído— se conserva intacto y va anclado en un test: lo único que
// se restringe es cambiar CUALQUIER cosa que no sea `lastRead`.
describe("chats/update — el preview sigue al permiso de escritura", () => {
  beforeEach(async () => {
    await seedChat(U1, U2);
    // U1 sigue a U2. U2 NO sigue a U1 → sólo U2 puede escribir.
    await seedEdge(U1, U2, "accepted");
  });

  it("DENIEGA al lado bloqueado empujar texto al preview del otro", async () => {
    await assertFails(updatePreview(U1, U1, U2, "texto no deseado"));
  });

  it("permite al lado habilitado actualizar el preview", async () => {
    await assertSucceeds(updatePreview(U2, U1, U2));
  });

  it("el lado bloqueado CONSERVA marcar como leído", async () => {
    // Es la razón por la que design §3.3.4 pedía no tocar esta regla. Se
    // respeta: `lastRead` sigue siendo libre para cualquier miembro.
    await assertSucceeds(markRead(U1, U1, U2));
  });

  it("DENIEGA al lado bloqueado agregar cualquier otro campo", async () => {
    // La restricción es una allowlist (`hasOnly(['lastRead'])`), no una lista
    // de campos de preview enumerados: si mañana se agrega otro campo al doc,
    // queda denegado por defecto en vez de colarse.
    await assertFails(
      testEnv
        .authenticatedContext(U1)
        .firestore()
        .collection("chats")
        .doc(chatIdOf(U1, U2))
        .update({ campoNuevo: "x" }),
    );
  });

  it("en un chat de Coach los dos actualizan el preview sin ninguna arista", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await seedChat(ATHLETE, TRAINER, { linkId: "link-1" });

    await assertSucceeds(updatePreview(ATHLETE, ATHLETE, TRAINER));
    await assertSucceeds(updatePreview(TRAINER, ATHLETE, TRAINER));
  });

  it("un chat mutuo deja actualizar el preview a los dos", async () => {
    await seedEdge(U2, U1, "accepted"); // ahora es mutuo
    await assertSucceeds(updatePreview(U1, U1, U2));
    await assertSucceeds(updatePreview(U2, U1, U2));
  });
});

describe("messages/create — la rama trainer_link queda intacta (SCENARIO-842)", () => {
  it("con linkId y CERO aristas follows, los dos envían", async () => {
    // Ancla de que el Coach no se aprieta de rebote: si la rama `linkId` de
    // `senderMayPost` se perdiera, esto se pone rojo.
    //
    // Lo que este test NO prueba —y el comentario anterior afirmaba de más— es
    // el ORDEN de las ramas. `'linkId' in chat || followAccepted(...)` da lo
    // mismo invertido: con cero aristas `followAccepted` es false y el OR
    // termina en la rama del link igual. El orden es una decisión de COSTO (que
    // el Coach no pague llamadas de acceso extra), y el costo no se puede
    // afirmar desde un test de comportamiento — sólo se verifica que no se
    // pase del techo de 10, cosa que un assertSucceeds ya demuestra.
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
