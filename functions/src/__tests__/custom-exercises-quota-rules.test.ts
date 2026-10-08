/**
 * Firestore security-rules enforcement tests for
 * `users/{uid}/customExercises/{exId}` — el tope de ejercicios propios del
 * PF por plan (limite-ejercicios-pf.md §3 PR2).
 *
 * `customExerciseQuotaOk`, en `firestore.rules`, corta SOLO el `create`:
 *
 *   - Un alumno (o cualquier rol que no sea `trainer`) nunca gatea (E4).
 *   - `planLimits.customExercises` en `null` o ausente es SIN TOPE — falla
 *     abierta, igual que el resto del interruptor de PR1.
 *   - `count < limit`, no `<=` (E6): con límite 60 se pueden TENER 60.
 *   - `update`/`delete` NUNCA miran la cuota (E3): bajar de plan congela la
 *     creación y no borra ni bloquea nada de lo que ya existe.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (mismo patrón que
 * users-subscription-rules.test.ts).
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand custom-exercises-quota-rules"
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

const COL_USERS = "users";

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

interface UserFixture {
  uid: string;
  role: "athlete" | "trainer";
  email: string;
  createdAt: number;
  planLimits?: Record<string, unknown> | null;
  customExerciseUsage?: Record<string, unknown> | null;
}

/** Seed a users/{uid} doc via an Admin-privileged context (rules disabled). */
async function seedUser(fixture: UserFixture): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL_USERS).doc(fixture.uid).set(fixture);
  });
}

/** Seed a pre-existing customExercises/{exId} doc via the Admin SDK. */
async function seedExercise(uid: string, exId: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_USERS)
      .doc(uid)
      .collection("customExercises")
      .doc(exId)
      .set({ name: "Sentadilla" });
  });
}

function exercisesRef(uid: string) {
  const client = testEnv.authenticatedContext(uid);
  return client
    .firestore()
    .collection(COL_USERS)
    .doc(uid)
    .collection("customExercises");
}

// ---------------------------------------------------------------------------
// 1. Bajo el tope, en el tope, y por encima (post-downgrade).
// ---------------------------------------------------------------------------
describe("customExercises quota — bajo/en/sobre el tope (E6)", () => {
  it("un PF bajo el tope crea", async () => {
    const uid = "trainer-bajo-tope";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 19 },
    });

    await assertSucceeds(
      exercisesRef(uid).add({ name: "Press de banca" }),
    );
  });

  it("un PF exactamente EN el tope no crea (count == limit, no <=)", async () => {
    const uid = "trainer-en-tope";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 20 },
    });

    await assertFails(exercisesRef(uid).add({ name: "Peso muerto" }));
  });

  it("un PF que quedó POR ENCIMA del tope (bajó de plan) no crea", async () => {
    const uid = "trainer-sobre-tope";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 35 },
    });

    await assertFails(exercisesRef(uid).add({ name: "Remo con barra" }));
  });

  it("el mismo PF sobre el tope SÍ puede editar lo que ya tiene (E3)", async () => {
    const uid = "trainer-sobre-tope-edita";
    const exId = "ex-existente";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 35 },
    });
    await seedExercise(uid, exId);

    await assertSucceeds(
      exercisesRef(uid).doc(exId).update({ name: "Sentadilla (editado)" }),
    );
  });

  it("el mismo PF sobre el tope SÍ puede borrar lo que ya tiene (E3)", async () => {
    const uid = "trainer-sobre-tope-borra";
    const exId = "ex-existente";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 35 },
    });
    await seedExercise(uid, exId);

    await assertSucceeds(exercisesRef(uid).doc(exId).delete());
  });
});

// ---------------------------------------------------------------------------
// 2. Sin tope: null explícito, ausente, y sin customExerciseUsage.
// ---------------------------------------------------------------------------
describe("customExercises quota — sin tope, falla abierta (PR1)", () => {
  it("planLimits.customExercises en null crea sin límite", async () => {
    const uid = "trainer-sin-tope-null";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: null },
      customExerciseUsage: { count: 9999 },
    });

    await assertSucceeds(exercisesRef(uid).add({ name: "Plan 3" }));
  });

  it("planLimits AUSENTE crea (interruptor apagado / sin primer sync)", async () => {
    const uid = "trainer-sin-plan-limits";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
    });

    await assertSucceeds(exercisesRef(uid).add({ name: "Sin sync" }));
  });

  it("customExerciseUsage AUSENTE con tope activo cuenta como 0 y crea", async () => {
    const uid = "trainer-sin-usage";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: 20 },
    });

    await assertSucceeds(exercisesRef(uid).add({ name: "Primer ejercicio" }));
  });
});

// ---------------------------------------------------------------------------
// 3. El alumno nunca gatea (E4) — el editor es compartido.
// ---------------------------------------------------------------------------
describe("customExercises quota — el alumno nunca gatea (E4)", () => {
  it("un alumno crea aunque el tope/contador digan que está sobre el límite", async () => {
    const uid = "athlete-nunca-gatea";
    await seedUser({
      uid,
      role: "athlete",
      email: `${uid}@example.test`,
      createdAt: 0,
      // Campos de PF sembrados a mano: si `customExerciseQuotaOk` no cortara
      // por rol PRIMERO, esto denegaría igual que a un trainer sobre el tope.
      planLimits: { customExercises: 1 },
      customExerciseUsage: { count: 999 },
    });

    await assertSucceeds(exercisesRef(uid).add({ name: "Alumno crea" }));
  });
});

// ---------------------------------------------------------------------------
// 4. Dato corrupto: el límite no es un número — falla CERRADO, no revienta.
// ---------------------------------------------------------------------------
describe("customExercises quota — planLimits.customExercises no numérico", () => {
  it("con el límite como string, la comparación tira y la regla deniega (fail-closed)", async () => {
    const uid = "trainer-limite-corrupto";
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      planLimits: { customExercises: "20" as unknown as number },
      customExerciseUsage: { count: 1 },
    });

    await assertFails(exercisesRef(uid).add({ name: "Dato corrupto" }));
  });
});

// ---------------------------------------------------------------------------
// 5. Regresión: read sigue intacto (auth-only, no owner-only).
// ---------------------------------------------------------------------------
describe("customExercises quota — regresión de read", () => {
  it("cualquier usuario autenticado sigue pudiendo leer el ejercicio de otro PF", async () => {
    const ownerUid = "trainer-dueño-lectura";
    const readerUid = "athlete-lector";
    const exId = "ex-leible";
    await seedUser({
      uid: ownerUid,
      role: "trainer",
      email: `${ownerUid}@example.test`,
      createdAt: 0,
    });
    await seedExercise(ownerUid, exId);

    const reader = testEnv.authenticatedContext(readerUid);
    await assertSucceeds(
      reader
        .firestore()
        .collection(COL_USERS)
        .doc(ownerUid)
        .collection("customExercises")
        .doc(exId)
        .get(),
    );
  });
});
