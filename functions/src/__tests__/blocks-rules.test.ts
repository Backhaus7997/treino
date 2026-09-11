/**
 * Tests de enforcement real de las rules de `blocks/{blockId}` y del efecto
 * cruzado de `notBlocked()` en las otras colecciones que lo consumen
 * (mensajes, reacciones, follows, reviews).
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
