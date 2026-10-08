/**
 * `moderation_quarantine` esta cerrada a todo cliente, en las dos direcciones.
 *
 * La escribe el Admin SDK desde `moderation/quarantine-vetted-content.ts`, que
 * ignora las rules. Para un cliente no existe.
 *
 * Poder LEERLA seria un canal de evasion: dice exactamente que documentos cazo
 * el filtro y cuales no, o sea que convierte la coleccion en el oraculo que el
 * mensaje generico del cliente existe para no ser. Poder escribirla seria peor:
 * cualquiera podria marcar contenido ajeno como cazado.
 *
 * El foco es NEGATIVO, y por eso hay un control POSITIVO al final: un
 * `assertFails` puede pasar por el motivo equivocado —una request mal armada,
 * un contexto sin auth— y verse identico a una regla que funciona. El control
 * prueba que este mismo cliente, en este mismo entorno, SI puede hacer algo
 * que las rules le permiten.
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` (package.json
 * `test:rules`) o no corre en CI.
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

const PROJECT_ID = "treino-rules-test-quarantine";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

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

describe("moderation_quarantine", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("moderation_quarantine/posts__p1").set({
        path: "posts/p1",
        field: "text",
        kind: "post",
        verdict: "block",
        authorUid: "u1",
        redacted: true,
        at: new Date(),
      });
    });
  });

  it("un cliente autenticado NO puede leer un registro", async () => {
    await assertFails(
      asUser("u1").doc("moderation_quarantine/posts__p1").get(),
    );
  });

  it("ni siquiera su propio autor puede leerlo", async () => {
    // El `authorUid` del registro es `u1`. Que sea suyo no lo habilita: lo que
    // el registro revela no es contenido del usuario, es el estado del filtro.
    await assertFails(
      asUser("u1").doc("moderation_quarantine/posts__p1").get(),
    );
  });

  it("un cliente NO puede listar la coleccion", async () => {
    await assertFails(asUser("u1").collection("moderation_quarantine").get());
  });

  it("un cliente NO puede crear un registro", async () => {
    await assertFails(
      asUser("u2").doc("moderation_quarantine/posts__p2").set({
        path: "posts/p2",
        verdict: "block",
      }),
    );
  });

  it("un cliente NO puede borrar un registro", async () => {
    // Borrarlo seria sacar de la cola de moderacion lo propio.
    await assertFails(
      asUser("u1").doc("moderation_quarantine/posts__p1").delete(),
    );
  });

  it("CONTROL POSITIVO: este mismo cliente si puede leer lo que le corresponde",
    async () => {
      // Sin esto, los cinco `assertFails` de arriba pasarian igual con el
      // emulador mal configurado, con un contexto sin auth, o con cualquier
      // otro motivo que no sea la regla. Un assertFails que falla por el
      // motivo equivocado se lee exactamente igual que uno que funciona.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("userPublicProfiles/u1").set({
          uid: "u1",
          displayName: "Test",
        });
      });
      await assertSucceeds(asUser("u1").doc("userPublicProfiles/u1").get());
    });
});
