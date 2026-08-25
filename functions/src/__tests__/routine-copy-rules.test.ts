/**
 * Rules tests para la copia atleta-de-plantilla — #647, "usar como base".
 *
 * POR QUÉ EXISTE ESTE ARCHIVO
 * Hasta este cambio, TODO payload de rutina `user-created` se armaba desde un
 * literal fijo en `_submit()` del editor: `Routine(id: '', name: …, split:
 * null, source: userCreated, …)`. El conjunto de claves era, literalmente,
 * inmutable por construcción.
 *
 * "Usar como base" rompe esa propiedad: es el primer flujo donde el contenido
 * de una rutina del atleta sale de OTRO documento —una plantilla del sistema o
 * una plantilla publicada por un PF— que tiene campos que el atleta no puede
 * poseer (`assignedBy`, `assignedTo`) ni escribir (`ratingAvg`,
 * `ratingsCount`, `summary`).
 *
 * El editor los descarta en el borde: hidrata días/slots/semanas y nada más, y
 * `_submit` reconstruye la rutina desde su propio estado. Pero eso es una
 * garantía del CLIENTE, y un cliente parcheado no la respeta. Estos tests
 * fijan la garantía del SERVIDOR.
 *
 * EL GUARD NUEVO
 * CREATE branch 2 no tenía `keys().hasOnly(...)`; UPDATE path 2 sí. Esa
 * asimetría dejaba crear una rutina con una clave desconocida que después
 * NINGÚN update aceptaba: brick silencioso, permission-denied recién en la
 * primera edición, lejos de la escritura que lo causó. El modo de falla de
 * #563. Las dos ramas comparten ahora `userCreatedRoutineFields()`.
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

const PROJECT_ID = "treino-rules-test-rcopy";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL = "routines";
const ATHLETE = "athlete-copy";
const OTHER_ATHLETE = "athlete-copy-other";
const TRAINER = "trainer-copy";
const CREATED_AT = new Date("2026-08-01T12:00:00Z");

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

/**
 * El payload EXACTO que emite `RoutineRepository.createUserOwned` para una
 * copia: `draft.toJson()` sin `id`/`assignedBy`/`assignedTo`, más los campos
 * que el repo fuerza. Las claves nulas están a propósito — json_serializable
 * emite toda opcional con null explícito, y esa es la forma normal del cable.
 *
 * El contenido (`days`, `numWeeks`) es lo ÚNICO que viaja desde la plantilla.
 */
function copyPayload(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    name: "Push Pull Legs — Principiante (mi versión)",
    // Fijos del modo atleta (ADR-RER-04): la plantilla puede traer 'PPL'.
    split: null,
    level: "beginner",
    // Contenido copiado: 2 semanas, un slot con prescripción por semana.
    days: [
      {
        dayNumber: 1,
        name: "Empuje",
        estimatedMinutes: null,
        slots: [
          {
            exerciseId: "bench-press",
            exerciseName: "Press de Banca",
            muscleGroup: "chest",
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 12,
            restSeconds: 90,
            targetWeightKg: null,
            notes: "RIR 2",
            supersetGroup: null,
            targetReps: [],
            durationSeconds: null,
            exerciseMode: "reps",
            repMode: "range",
            sets: [],
            weeklySets: [
              { sets: [{ repsMin: 8, repsMax: 12 }] },
              { sets: [{ repsMin: 6, repsMax: 10 }] },
            ],
            activeWeeks: [],
          },
        ],
      },
    ],
    numWeeks: 2,
    // Metadata de la plantilla que NO viaja — el editor no la re-emite.
    estimatedMinutesPerDay: null,
    imageUrl: null,
    summary: null,
    // Forzados por createUserOwned.
    source: "user-created",
    createdBy: ATHLETE,
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

describe("copia de plantilla → rutina del atleta (#647)", () => {
  describe("CREATE — la copia se acepta", () => {
    it("acepta el payload de createUserOwned para una copia", async () => {
      await assertSucceeds(
        asUser(ATHLETE).collection(COL).doc("copy-ok").set(copyPayload()),
      );
    });

    it("acepta la copia compartida en el perfil (visibility public)", async () => {
      // El atleta puede optar por publicarla; el toggle vive en el editor.
      await assertSucceeds(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-public")
          .set(copyPayload({ visibility: "public" })),
      );
    });
  });

  describe("CREATE — lo que la copia NO puede arrastrar", () => {
    it("DENIEGA spoofear createdBy con el uid de otro atleta", async () => {
      // El caller es OTHER_ATHLETE pero firma la copia como ATHLETE.
      await assertFails(
        asUser(OTHER_ATHLETE)
          .collection(COL)
          .doc("copy-spoof")
          .set(copyPayload()),
      );
    });

    it("DENIEGA una copia con assignedBy (el PF dueño del original)", async () => {
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-assignedby")
          .set(copyPayload({ assignedBy: TRAINER })),
      );
    });

    it("DENIEGA una copia con assignedTo, aunque sea null", async () => {
      // Ausencia, no nulidad: `!('assignedTo' in data)`. json_serializable
      // emite la clave con null, y por eso createUserOwned la borra a mano.
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-assignedto")
          .set(copyPayload({ assignedTo: null })),
      );
    });

    it("DENIEGA una copia que arrastra la reputación del original", async () => {
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-rating")
          .set(copyPayload({ ratingAvg: 4.8, ratingsCount: 37 })),
      );
    });

    it("DENIEGA una copia con createdAt que no es timestamp", async () => {
      // Copiar el doc tal cual traería el createdAt del original; el repo lo
      // pisa con serverTimestamp. Un cliente parcheado podría mandar basura.
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-createdat")
          .set(copyPayload({ createdAt: "2026-08-01" })),
      );
    });

    it("DENIEGA visibility 'shared' — es del carril del PF", async () => {
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-shared")
          .set(copyPayload({ visibility: "shared" })),
      );
    });

    it("DENIEGA una clave desconocida en el create (guard nuevo)", async () => {
      // Sin `keys().hasOnly` en el create, esto pasaba — y después NINGÚN
      // update la aceptaba: la rutina quedaba imposible de editar para
      // siempre, con el permission-denied apareciendo recién en la primera
      // edición. Modo de falla de #563.
      await assertFails(
        asUser(ATHLETE)
          .collection(COL)
          .doc("copy-unknown")
          .set(copyPayload({ copiedFrom: "ppl-principiante" })),
      );
    });
  });

  describe("La copia queda editable — el loop que cierra #563", () => {
    it("el dueño puede editar contenido de su copia recién creada", async () => {
      const id = "copy-editable";
      await seed(id, copyPayload());

      await assertSucceeds(
        asUser(ATHLETE).collection(COL).doc(id).update({
          name: "Mi PPL",
          level: "beginner",
          days: [],
          numWeeks: 1,
          visibility: "private",
        }),
      );
    });

    it("sigue editable aunque el doc tenga summary", async () => {
      // `summary` está en el allowlist compartido, así que el guard NUEVO del
      // create no lo rechaza y el `hasOnly` del update lo tolera. No está en
      // el affectedKeys: convive, no se cambia.
      const id = "copy-with-summary";
      await seed(id, copyPayload({ summary: "Empujar, tirar y piernas." }));

      await assertSucceeds(
        asUser(ATHLETE).collection(COL).doc(id).update({ name: "Mi PPL" }),
      );
    });

    it("un tercero no puede editar la copia", async () => {
      const id = "copy-foreign-edit";
      await seed(id, copyPayload());

      await assertFails(
        asUser(OTHER_ATHLETE)
          .collection(COL)
          .doc(id)
          .update({ name: "Te la robo" }),
      );
    });
  });
});
