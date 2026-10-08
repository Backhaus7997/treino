/**
 * Tests de enforcement real de las rules de `blocks/{blockId}` y del efecto
 * cruzado de `notBlocked()` en las otras colecciones que lo consumen
 * (mensajes, preview del chat, reacciones, follows, reviews).
 *
 * Mismo criterio que `follows-rules.test.ts`: `@firebase/rules-unit-testing`
 * con `firestore.rules` REAL cargado y APLICADO, no el Admin SDK.
 * `withSecurityRulesDisabled` se usa SOLO para sembrar el estado previo;
 * toda aserción corre en un contexto de cliente autenticado.
 *
 * El foco es NEGATIVO — un `assertSucceeds` prueba que el producto anda, no
 * que la regla proteja. design.md ("El oráculo de existencia, QA-SEC-010"):
 * acá el `read` de `blocks` ni siquiera mira `resource` — sólo el prefijo
 * del id — así que el bloqueado no tiene forma de distinguir "no me
 * bloquearon" de "me bloquearon y no lo sé".
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` (package.json
 * `test:rules`) o no corre en CI.
 *
 * Correr contra el emulador:
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

const PROJECT_ID = "treino-rules-test-blocks";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AT = new Date("2026-09-11T12:00:00.000Z");

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

const blockId = (blocker: string, blocked: string) => `${blocker}_${blocked}`;

/** Cuerpo canónico de un bloqueo — las 4 keys de la allowlist, nada más. */
function blockBody(blocker: string, blocked: string) {
  return {
    blockerUid: blocker,
    blockedUid: blocked,
    members: [blocker, blocked],
    createdAt: AT,
  };
}

/** Siembra un bloqueo ya existente (rules deshabilitadas, solo setup). */
async function seedBlock(blocker: string, blocked: string) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("blocks")
      .doc(blockId(blocker, blocked))
      .set(blockBody(blocker, blocked));
  });
}

// ── create ──────────────────────────────────────────────────────────────────
describe("blocks — create", () => {
  it("el bloqueador crea su propio bloqueo con id determinístico", async () => {
    await assertSucceeds(
      asUser("alice")
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .set(blockBody("alice", "bob")),
    );
  });

  // Caso obligatorio del design: nadie crea un bloqueo con blockerUid ajeno.
  it("deniega crear un bloqueo en nombre de otro (blockerUid ajeno)", async () => {
    await assertFails(
      asUser("mallory")
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .set(blockBody("alice", "bob")),
    );
  });

  it("deniega si el doc id no coincide con blockerUid_blockedUid", async () => {
    await assertFails(
      asUser("alice")
        .collection("blocks")
        .doc("cualquier_cosa")
        .set(blockBody("alice", "bob")),
    );
  });

  // Caso obligatorio del design: nadie se bloquea a sí mismo.
  it("deniega bloquearse a uno mismo", async () => {
    await assertFails(
      asUser("alice")
        .collection("blocks")
        .doc(blockId("alice", "alice"))
        .set(blockBody("alice", "alice")),
    );
  });

  it("deniega un campo fuera de la allowlist de 4 keys", async () => {
    await assertFails(
      asUser("alice")
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .set({ ...blockBody("alice", "bob"), reason: "spam" }),
    );
  });

  it("deniega si falta un campo obligatorio (hasAll)", async () => {
    const body = blockBody("alice", "bob") as Record<string, unknown>;
    delete body.createdAt;
    await assertFails(
      asUser("alice").collection("blocks").doc(blockId("alice", "bob")).set(body),
    );
  });

  it("deniega members que no sea [blocker, blocked]", async () => {
    await assertFails(
      asUser("alice")
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .set({ ...blockBody("alice", "bob"), members: ["bob", "alice"] }),
    );
  });
});

// ── read ────────────────────────────────────────────────────────────────────
describe("blocks — read", () => {
  it("el bloqueador lee su propio bloqueo", async () => {
    await seedBlock("alice", "bob");
    await assertSucceeds(
      asUser("alice").collection("blocks").doc(blockId("alice", "bob")).get(),
    );
  });

  it("el bloqueador 'pregunta' por un bloqueo inexistente y resuelve, no explota", async () => {
    await assertSucceeds(
      asUser("alice").collection("blocks").doc(blockId("alice", "nadie")).get(),
    );
  });

  // LA query que hace la app, y que ningún test cubría.
  //
  // `BlockRepository.watchBlockedUids` hace exactamente esto:
  // `blocks.where('blockerUid', isEqualTo: uid).snapshots()`. Es lo que
  // alimenta la pestaña SEGUIDORES del feed — sin esta lista no se puede
  // armar el `whereIn` de autores, así que si la query falla se cae el feed
  // entero con «No pudimos cargar tu feed».
  //
  // El `allow read` de `blocks` mira el ID del documento
  // (`blockId.split('_')[0]`). Para un `get` alcanza. Para un LIST no: el
  // motor tiene que probar la condición sobre documentos cuyos IDs todavía
  // no conoce, y no puede — deniega la query completa.
  //
  // Los tests de arriba pasaban porque todos leen POR DOCUMENTO.
  it("el bloqueador LISTA sus propios bloqueos (la query del feed)", async () => {
    await seedBlock("alice", "bob");
    await assertSucceeds(
      asUser("alice")
        .collection("blocks")
        .where("blockerUid", "==", "alice")
        .get(),
    );
  });

  // Control negativo: la lista sigue siendo sólo la propia.
  it("nadie LISTA los bloqueos de otro", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("mallory")
        .collection("blocks")
        .where("blockerUid", "==", "alice")
        .get(),
    );
  });

  // Caso obligatorio del design: un tercero NO lee un bloqueo ajeno.
  it("un tercero NO lee un bloqueo ajeno", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("mallory").collection("blocks").doc(blockId("alice", "bob")).get(),
    );
  });

  // Caso obligatorio del design: el BLOQUEADO no puede leer el doc que lo
  // bloquea — no confirma que lo bloquearon. Junto con el caso anterior y el
  // de "inexistente" de arriba, las tres formas de pregunta (tercero, doc que
  // no existe, doc que existe y me apunta) devuelven la MISMA forma de
  // respuesta para quien no es el bloqueador: eso es lo que tapa el oráculo.
  it("el BLOQUEADO no puede leer el doc que lo bloquea", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("bob").collection("blocks").doc(blockId("alice", "bob")).get(),
    );
  });

  it("un anónimo no lee nada", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .get(),
    );
  });
});

// ── update ──────────────────────────────────────────────────────────────────
describe("blocks — update", () => {
  it("nadie actualiza un bloqueo, ni el propio bloqueador — se borra y se recrea", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("alice")
        .collection("blocks")
        .doc(blockId("alice", "bob"))
        .update({ createdAt: new Date("2020-01-01") }),
    );
  });
});

// ── delete ──────────────────────────────────────────────────────────────────
describe("blocks — delete", () => {
  it("el bloqueador borra su propio bloqueo", async () => {
    await seedBlock("alice", "bob");
    await assertSucceeds(
      asUser("alice").collection("blocks").doc(blockId("alice", "bob")).delete(),
    );
  });

  it("un tercero no puede borrar un bloqueo ajeno", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("mallory").collection("blocks").doc(blockId("alice", "bob")).delete(),
    );
  });

  it("el BLOQUEADO no puede borrar el bloqueo que lo bloquea", async () => {
    await seedBlock("alice", "bob");
    await assertFails(
      asUser("bob").collection("blocks").doc(blockId("alice", "bob")).delete(),
    );
  });
});

// ── notBlocked(): efecto cruzado en otras colecciones ───────────────────────
//
// Caso obligatorio del design: "El bloqueado no manda mensaje, no reacciona,
// no sigue, no reseña al bloqueador." Cada negativo siembra el estado que
// HARÍA SUCEDER a la escritura si no hubiera bloqueo (chat inquiry, post
// público, follow pending, trainer_link activo) para aislar que lo que
// deniega es específicamente `notBlocked()` y no otra rama de la regla. Cada
// uno lleva al lado un positivo con un par SIN bloqueo que prueba la misma
// escritura con el mismo seed — sin ese control, un negativo que fallara por
// cualquier otro motivo (shape, relación inexistente) pasaría en falso.
describe("blocks — notBlocked() corta la escritura en otras colecciones", () => {
  it("el bloqueado no manda mensaje al bloqueador", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("chats")
        .doc("alice_bob")
        .set({ members: ["alice", "bob"], kind: "inquiry" });
    });

    await assertFails(
      asUser("bob")
        .collection("chats")
        .doc("alice_bob")
        .collection("messages")
        .doc("m1")
        .set({ senderId: "bob", text: "hola", createdAt: AT }),
    );
  });

  it("control: sin bloqueo, el mismo mensaje se manda", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("chats")
        .doc("carol_dave")
        .set({ members: ["carol", "dave"], kind: "inquiry" });
    });

    await assertSucceeds(
      asUser("dave")
        .collection("chats")
        .doc("carol_dave")
        .collection("messages")
        .doc("m1")
        .set({ senderId: "dave", text: "hola", createdAt: AT }),
    );
  });

  it("el bloqueado no reacciona a un post público del bloqueador", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("posts").doc("p1").set({
        authorUid: "alice",
        privacy: "public",
        text: "hola",
        createdAt: AT,
      });
    });

    await assertFails(
      asUser("bob")
        .collection("posts")
        .doc("p1")
        .collection("reactions")
        .doc("bob")
        .set({ type: "like", createdAt: AT }),
    );
  });

  it("control: sin bloqueo, la misma reacción se crea", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("posts").doc("p2").set({
        authorUid: "carol",
        privacy: "public",
        text: "hola",
        createdAt: AT,
      });
    });

    await assertSucceeds(
      asUser("dave")
        .collection("posts")
        .doc("p2")
        .collection("reactions")
        .doc("dave")
        .set({ type: "like", createdAt: AT }),
    );
  });

  it("el bloqueado no sigue al bloqueador", async () => {
    await seedBlock("alice", "bob");

    await assertFails(
      asUser("bob")
        .collection("follows")
        .doc("bob_alice")
        .set({
          id: "bob_alice",
          followerUid: "bob",
          followeeUid: "alice",
          status: "pending",
          members: ["bob", "alice"],
          createdAt: AT,
        }),
    );
  });

  it("control: sin bloqueo, el mismo follow se crea", async () => {
    await assertSucceeds(
      asUser("dave")
        .collection("follows")
        .doc("dave_carol")
        .set({
          id: "dave_carol",
          followerUid: "dave",
          followeeUid: "carol",
          status: "pending",
          members: ["dave", "carol"],
          createdAt: AT,
        }),
    );
  });

  // ── preview del chat (doc padre) ──────────────────────────────────────────
  //
  // El gate de `messages/create` no alcanza solo: el doc PADRE tiene su propia
  // regla de update y por ahí se escribe `lastMessageText`, que es el texto que
  // la otra persona ve en su lista de chats, con badge de no-leído. Un cliente
  // modificado que no logra crear el mensaje igual podía plantar texto ahí.
  // Estos tres casos son los que distinguen "no te puede escribir" de "no te
  // puede escribir el mensaje, pero sí el renglón que vos leés".
  it("el bloqueado no actualiza el preview del chat (lastMessageText)", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("chats").doc("alice_bob").set({
        members: ["alice", "bob"],
        kind: "inquiry",
        createdAt: AT,
        lastMessageText: "hola",
        lastMessageSenderId: "alice",
        lastMessageAt: AT,
      });
    });

    await assertFails(
      asUser("bob").collection("chats").doc("alice_bob").update({
        lastMessageText: "te sigo escribiendo igual",
        lastMessageSenderId: "bob",
        lastMessageAt: AT,
      }),
    );
  });

  it("control: sin bloqueo, el mismo update del preview pasa", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("chats").doc("carol_dave").set({
        members: ["carol", "dave"],
        kind: "inquiry",
        createdAt: AT,
        lastMessageText: "hola",
        lastMessageSenderId: "carol",
        lastMessageAt: AT,
      });
    });

    await assertSucceeds(
      asUser("dave").collection("chats").doc("carol_dave").update({
        lastMessageText: "te contesto",
        lastMessageSenderId: "dave",
        lastMessageAt: AT,
      }),
    );
  });

  // El otro lado de la misma regla, y la razón por la que `notBlocked()` no va
  // al principio del `allow update`: el bloqueado tiene que poder seguir
  // marcando como leído o el badge de no-leídos se le clava para siempre
  // (design §3.3.4). Ese disyunto corta antes y ni siquiera paga las lecturas.
  it("el bloqueado SÍ puede seguir marcando lastRead", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("chats").doc("alice_bob").set({
        members: ["alice", "bob"],
        kind: "inquiry",
        createdAt: AT,
        lastMessageText: "hola",
        lastMessageSenderId: "alice",
        lastMessageAt: AT,
        lastRead: {},
      });
    });

    await assertSucceeds(
      asUser("bob")
        .collection("chats")
        .doc("alice_bob")
        .update({ lastRead: { bob: AT } }),
    );
  });

  // ── reseñas ya existentes ─────────────────────────────────────────────────
  //
  // El id de la reseña es determinístico (`linkId_athleteId`) y
  // `ReviewRepository.upsert()` reescribe el doc que ya está, o sea por el
  // `allow update`. Gatear sólo el `create` dejaba abierto el único caso que
  // importa: la reseña que ya existía ANTES del bloqueo.
  it("el bloqueado no edita la reseña que ya había dejado", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("trainer_links").doc("link3").set({
        athleteId: "bob",
        trainerId: "alice",
        status: "active",
      });
      await ctx.firestore().collection("reviews").doc("link3_bob").set({
        id: "link3_bob",
        linkId: "link3",
        athleteId: "bob",
        trainerId: "alice",
        rating: 5,
        comment: "muy bueno",
        createdAt: AT,
      });
    });

    await assertFails(
      asUser("bob")
        .collection("reviews")
        .doc("link3_bob")
        .update({ comment: "texto de acoso", updatedAt: AT }),
    );
  });

  it("control: sin bloqueo, la misma edición de reseña pasa", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("trainer_links").doc("link4").set({
        athleteId: "dave",
        trainerId: "carol",
        status: "active",
      });
      await ctx.firestore().collection("reviews").doc("link4_dave").set({
        id: "link4_dave",
        linkId: "link4",
        athleteId: "dave",
        trainerId: "carol",
        rating: 5,
        comment: "muy bueno",
        createdAt: AT,
      });
    });

    await assertSucceeds(
      asUser("dave")
        .collection("reviews")
        .doc("link4_dave")
        .update({ comment: "lo corrijo", updatedAt: AT }),
    );
  });

  it("el bloqueado no reseña al bloqueador", async () => {
    await seedBlock("alice", "bob");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("trainer_links").doc("link1").set({
        athleteId: "bob",
        trainerId: "alice",
        status: "active",
      });
    });

    await assertFails(
      asUser("bob")
        .collection("reviews")
        .doc("link1_bob")
        .set({
          id: "link1_bob",
          linkId: "link1",
          athleteId: "bob",
          trainerId: "alice",
          rating: 5,
          createdAt: AT,
        }),
    );
  });

  it("control: sin bloqueo, la misma reseña se crea", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("trainer_links").doc("link2").set({
        athleteId: "dave",
        trainerId: "carol",
        status: "active",
      });
    });

    await assertSucceeds(
      asUser("dave")
        .collection("reviews")
        .doc("link2_dave")
        .set({
          id: "link2_dave",
          linkId: "link2",
          athleteId: "dave",
          trainerId: "carol",
          rating: 5,
          createdAt: AT,
        }),
    );
  });
});
