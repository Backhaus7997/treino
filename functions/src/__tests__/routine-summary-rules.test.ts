/**
 * Rules tests for `summary` on `routines/{routineId}` — #648, slice de
 * resúmenes autorados por el PF.
 *
 * WHY THIS FILE EXISTS
 * Hasta este cambio el campo `summary` llevaba `@JsonKey(includeToJson: false)`
 * en el modelo Dart, y ESA anotación era toda la protección: el cliente nunca
 * lo mandaba en un payload, así que ningún `hasOnly` de firestore.rules tenía
 * que conocerlo. Dos tests en `routine_test.dart` lo pineaban.
 *
 * Habilitar la escritura por parte del PF obligó a sacar la anotación, y con
 * eso `toJson()` empezó a emitir el campo en TODA rutina — incluidas las del
 * atleta, que nunca lo escriben a mano. Si a alguno de los tres paths de update
 * le faltara `summary` en su `keys().hasOnly`, esa rama entera de edición
 * fallaría con permission-denied: el modo de falla de #563, donde el switch de
 * perfil público rompía porque un campo no estaba en el allowlist.
 *
 * O sea: la protección se movió del modelo a las reglas, y este archivo es lo
 * que la sostiene. El caso más importante NO es que el PF pueda escribir — es
 * que el ATLETA siga pudiendo editar una rutina que TIENE summary.
 *
 * El reparto es asimétrico a propósito:
 *   - paths 3 y 4 (PF): `summary` en keys() Y en affectedKeys() → lo escribe.
 *   - path 2 (atleta): SÓLO en keys() → convive con él, no lo cambia.
 *     Mismo criterio que ratingAvg/ratingsCount.
 *
 * Corre contra el emulador de Firestore (Java 21):
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

const PROJECT_ID = "treino-rules-test-rsummary";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL = "routines";
const TRAINER = "trainer-rsummary";
const ATHLETE = "athlete-rsummary";
const CREATED_AT = new Date("2026-08-01T12:00:00Z");

const SUMMARY = "Empujar, tirar y piernas: un tipo de movimiento por día.";

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

function ctxDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

/**
 * El update es `keys().hasOnly()` sobre el documento ENTERO, así que el fixture
 * tiene que ser el doc completo. Uno parcial fallaría por el motivo equivocado
 * y el test no probaría nada.
 */
function athleteRoutine(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    name: "Mi Rutina",
    level: "beginner",
    days: [],
    source: "user-created",
    createdBy: ATHLETE,
    visibility: "private",
    createdAt: CREATED_AT,
    status: "active",
    ...overrides,
  };
}

function trainerRoutine(
  source: "trainer-assigned" | "trainer-template",
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    name: "Plan",
    split: "PPL",
    level: "beginner",
    days: [],
    source,
    assignedBy: TRAINER,
    assignedTo: source === "trainer-assigned" ? ATHLETE : null,
    visibility: "private",
    status: "active",
    createdAt: CREATED_AT,
    ...overrides,
  };
}

async function seed(id: string, doc: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL).doc(id).set(doc);
  });
}

describe("routines summary — el PF escribe, el atleta convive (#648)", () => {
  describe("path 2 — atleta (user-created)", () => {
    it("REGRESIÓN #563: puede editar su rutina AUNQUE tenga summary", async () => {
      // El caso que rompía si `summary` no entraba al keys().hasOnly. Sin esta
      // entrada, un atleta cuya rutina alguna vez recibió un summary no podría
      // volver a editarla NUNCA.
      const id = "r-athlete-with-summary";
      await seed(id, athleteRoutine({ summary: SUMMARY }));

      await assertSucceeds(
        ctxDb(ATHLETE)
          .collection(COL)
          .doc(id)
          .update({ name: "Mi Rutina v2", summary: SUMMARY }),
      );
    });

    it("puede editar su rutina cuando NO tiene summary", async () => {
      const id = "r-athlete-no-summary";
      await seed(id, athleteRoutine());

      await assertSucceeds(
        ctxDb(ATHLETE).collection(COL).doc(id).update({ name: "Otra" }),
      );
    });

    it("NO puede cambiar el summary — no está en su affectedKeys", async () => {
      const id = "r-athlete-mutating-summary";
      await seed(id, athleteRoutine({ summary: SUMMARY }));

      await assertFails(
        ctxDb(ATHLETE)
          .collection(COL)
          .doc(id)
          .update({ summary: "Lo reescribo yo" }),
      );
    });
  });

  describe("path 3 — PF sobre un plan asignado", () => {
    it("puede escribir el summary", async () => {
      const id = "r-assigned";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertSucceeds(
        ctxDb(TRAINER).collection(COL).doc(id).update({ summary: SUMMARY }),
      );
    });

    it("rechaza un summary de más de 280 caracteres", async () => {
      const id = "r-assigned-long";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertFails(
        ctxDb(TRAINER)
          .collection(COL)
          .doc(id)
          .update({ summary: "x".repeat(281) }),
      );
    });

    it("acepta exactamente 280 — el borde es inclusivo", async () => {
      const id = "r-assigned-edge";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertSucceeds(
        ctxDb(TRAINER)
          .collection(COL)
          .doc(id)
          .update({ summary: "x".repeat(280) }),
      );
    });

    it("rechaza un summary que no es string", async () => {
      const id = "r-assigned-type";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertFails(
        ctxDb(TRAINER).collection(COL).doc(id).update({ summary: 42 }),
      );
    });

    it("un PF ajeno no puede escribirlo", async () => {
      const id = "r-assigned-other";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertFails(
        ctxDb("otro-pf").collection(COL).doc(id).update({ summary: SUMMARY }),
      );
    });

    it("el atleta destinatario tampoco puede escribirlo", async () => {
      // El plan es del PF: el alumno lo lee, no lo edita.
      const id = "r-assigned-athlete";
      await seed(id, trainerRoutine("trainer-assigned"));

      await assertFails(
        ctxDb(ATHLETE).collection(COL).doc(id).update({ summary: SUMMARY }),
      );
    });
  });

  describe("path 4 — PF sobre una plantilla propia", () => {
    it("puede escribir el summary", async () => {
      const id = "r-template";
      await seed(id, trainerRoutine("trainer-template"));

      await assertSucceeds(
        ctxDb(TRAINER).collection(COL).doc(id).update({ summary: SUMMARY }),
      );
    });

    it("rechaza un summary de más de 280 caracteres", async () => {
      const id = "r-template-long";
      await seed(id, trainerRoutine("trainer-template"));

      await assertFails(
        ctxDb(TRAINER)
          .collection(COL)
          .doc(id)
          .update({ summary: "x".repeat(281) }),
      );
    });
  });
});
