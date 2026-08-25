/**
 * Rules tests for `users/{uid}/sessions/{sessionId}/exerciseFeedback/{id}` (#628)
 * — el canal alumno → PF: un comentario o una MOLESTIA anclada al ejercicio y
 * a la serie, escrito DURANTE la sesión.
 *
 * WHY THIS FILE EXISTS
 * Esta subcolección guarda **dato de salud**: `kind: 'discomfort'` es dolor o
 * lesión declarada, y `photoUrl` apunta a una foto de "dónde me duele". Y es,
 * además, el gate REAL de esa foto: la URL que emite `getDownloadURL()` lleva
 * `?alt=media&token=`, es una credencial al portador y NO evalúa
 * `storage.rules` (docs/security.md §3.1, medido contra el emulador). O sea
 * que quien puede LEER este documento puede bajar la foto, pase lo que pase
 * del lado de Storage. Por eso el read es el mismo predicado de dos partes de
 * `setLogs` y no `request.auth != null`.
 *
 * WHAT IS ASSERTED
 *   E1-E8 — los ocho escenarios del change `trainer-athlete-set-logs`,
 *   replicados sobre la subcolección nueva (firestore.rules comenta la lista
 *   sobre el bloque de `setLogs`): PF con grant lee / lista, PF ajeno no, sin
 *   grant no, PF con grant NO escribe, dueño lee y escribe, anónimo nada.
 *   S1-S6 — la validación de forma, que es lo que #508/#447 dicen que se cuela
 *   cuando nadie la testea: tipos, el enum de `kind`, el rango de `setNumber`,
 *   y la regla de negocio "nada de reportes vacíos" (#628) incluida la trampa
 *   de la cadena vacía.
 *
 * Run against the Firestore emulator (Java 21 required):
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

// projectId propio: las suites de reglas comparten un emulador y hacen
// clearFirestore() en afterEach.
const PROJECT_ID = "treino-rules-test-exercise-feedback";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_USERS = "users";
const COL_SESSION_SHARES = "session_shares";

const ATHLETE = "athlete-feedback";
const TRAINER = "trainer-feedback";
const OTHER_TRAINER = "other-trainer-feedback";

const SESSION_ID = "session-feedback-1";
const FEEDBACK_ID = "feedback-1";

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

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

/** Un feedback válido mínimo — comentario con texto, sin foto. */
function validFeedback(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    exerciseId: "ex-press-banca",
    exerciseName: "Press de banca",
    setNumber: 3,
    kind: "comment",
    text: "La barra se me va para la derecha",
    photoUrl: null,
    photoPath: null,
    createdAt: new Date(),
    ...overrides,
  };
}

async function seedGrant(trainerId: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_SESSION_SHARES)
      .doc(ATHLETE)
      .set({ trainerId, updatedAt: new Date() });
  });
}

async function seedFeedback(
  data: Record<string, unknown> = validFeedback(),
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_USERS)
      .doc(ATHLETE)
      .collection("sessions")
      .doc(SESSION_ID)
      .collection("exerciseFeedback")
      .doc(FEEDBACK_ID)
      .set(data);
  });
}

function feedbackCol(uid: string) {
  return ctxDb(uid)
    .collection(COL_USERS)
    .doc(ATHLETE)
    .collection("sessions")
    .doc(SESSION_ID)
    .collection("exerciseFeedback");
}

// ─── E1-E8 — el gate de dos partes, espejo de setLogs ────────────────────────

describe("exerciseFeedback — read gate (E1-E8)", () => {
  beforeEach(async () => {
    await seedFeedback();
  });

  it("E1: el PF con grant vivo LEE el feedback del alumno", async () => {
    await seedGrant(TRAINER);
    await assertSucceeds(feedbackCol(TRAINER).doc(FEEDBACK_ID).get());
  });

  it("E2: el PF con grant vivo LISTA el feedback de la sesión", async () => {
    await seedGrant(TRAINER);
    await assertSucceeds(feedbackCol(TRAINER).get());
  });

  it("E3: un PF que NO es el del grant no lee ni lista", async () => {
    await seedGrant(TRAINER);
    await assertFails(feedbackCol(OTHER_TRAINER).doc(FEEDBACK_ID).get());
    await assertFails(feedbackCol(OTHER_TRAINER).get());
  });

  it("E4: sin documento de grant, ningún PF lee", async () => {
    await assertFails(feedbackCol(TRAINER).doc(FEEDBACK_ID).get());
    await assertFails(feedbackCol(TRAINER).get());
  });

  it("E5: el PF con grant NO escribe — el canal es one-way", async () => {
    await seedGrant(TRAINER);
    // Crear.
    await assertFails(
      feedbackCol(TRAINER).doc("forged").set(validFeedback()),
    );
    // Editar lo que escribió el alumno.
    await assertFails(
      feedbackCol(TRAINER)
        .doc(FEEDBACK_ID)
        .set({ text: "yo no dije eso" }, { merge: true }),
    );
    // Y borrarlo, que es la forma más barata de tapar un reporte de dolor.
    await assertFails(feedbackCol(TRAINER).doc(FEEDBACK_ID).delete());
  });

  it("E6: el dueño lee y lista lo suyo SIN que exista el grant", async () => {
    // Sin este caso el `||` podría estar al revés y nadie se enteraría: el
    // alumno leyendo lo suyo no debe depender de session_shares.
    await assertSucceeds(feedbackCol(ATHLETE).doc(FEEDBACK_ID).get());
    await assertSucceeds(feedbackCol(ATHLETE).get());
  });

  it("E7: el dueño escribe, actualiza y borra lo suyo", async () => {
    await assertSucceeds(feedbackCol(ATHLETE).doc("mine").set(validFeedback()));
    await assertSucceeds(
      feedbackCol(ATHLETE).doc(FEEDBACK_ID).set(validFeedback({ text: "corregido" })),
    );
    await assertSucceeds(feedbackCol(ATHLETE).doc(FEEDBACK_ID).delete());
  });

  it("E8: el anónimo no lee, no lista y no escribe", async () => {
    const anonCol = anonDb()
      .collection(COL_USERS)
      .doc(ATHLETE)
      .collection("sessions")
      .doc(SESSION_ID)
      .collection("exerciseFeedback");
    await assertFails(anonCol.doc(FEEDBACK_ID).get());
    await assertFails(anonCol.get());
    await assertFails(anonCol.doc("anon").set(validFeedback()));
  });

  it("un tercero cualquiera tampoco escribe en la sesión ajena", async () => {
    await assertFails(
      feedbackCol(OTHER_TRAINER).doc("hijack").set(validFeedback()),
    );
  });
});

// ─── S1-S6 — validación de forma (#508 / #447) ───────────────────────────────

describe("exerciseFeedback — validación de forma en create", () => {
  it("S1: acepta el reporte con texto y sin foto", async () => {
    await assertSucceeds(feedbackCol(ATHLETE).doc("s1").set(validFeedback()));
  });

  it("S1b: acepta el reporte con foto y sin texto", async () => {
    await assertSucceeds(
      feedbackCol(ATHLETE).doc("s1b").set(
        validFeedback({
          text: null,
          photoUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=z",
          photoPath: `sessionFeedback/${ATHLETE}/${SESSION_ID}/s1b.jpg`,
        }),
      ),
    );
  });

  it("S2: DENIEGA el reporte vacío — ni texto ni foto", async () => {
    await assertFails(
      feedbackCol(ATHLETE).doc("s2").set(validFeedback({ text: null })),
    );
  });

  it("S2b: DENIEGA la cadena vacía disfrazada de texto", async () => {
    // `optStrMaxLen` acepta '' feliz. Sin el chequeo de `.size() > 0` este
    // reporte pasaba y —si fuera 'discomfort'— le vibraba el teléfono al PF
    // por un documento sin una sola palabra.
    await assertFails(
      feedbackCol(ATHLETE).doc("s2b").set(validFeedback({ text: "" })),
    );
    await assertFails(
      feedbackCol(ATHLETE)
        .doc("s2b2")
        .set(validFeedback({ text: "", photoUrl: "" })),
    );
  });

  it("S3: DENIEGA un `kind` fuera del enum", async () => {
    await assertFails(
      feedbackCol(ATHLETE).doc("s3").set(validFeedback({ kind: "injury" })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s3b").set(validFeedback({ kind: 7 })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s3c").set(validFeedback({ kind: null })),
    );
  });

  it("S4: DENIEGA tipos equivocados en los campos requeridos", async () => {
    await assertFails(
      feedbackCol(ATHLETE).doc("s4").set(validFeedback({ exerciseId: 42 })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s4b").set(validFeedback({ exerciseId: "" })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s4c").set(validFeedback({ exerciseName: 42 })),
    );
    await assertFails(
      feedbackCol(ATHLETE)
        .doc("s4d")
        .set(validFeedback({ createdAt: "2026-08-24" })),
    );
  });

  it("S5: `setNumber` es opcional pero acotado", async () => {
    // null = comentario a nivel ejercicio, sin serie. Es válido.
    await assertSucceeds(
      feedbackCol(ATHLETE).doc("s5").set(validFeedback({ setNumber: null })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s5b").set(validFeedback({ setNumber: 0 })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s5c").set(validFeedback({ setNumber: 500 })),
    );
    await assertFails(
      feedbackCol(ATHLETE).doc("s5d").set(validFeedback({ setNumber: "3" })),
    );
  });

  it("S6: DENIEGA textos y paths desmedidos", async () => {
    await assertFails(
      feedbackCol(ATHLETE)
        .doc("s6")
        .set(validFeedback({ text: "x".repeat(2001) })),
    );
    await assertFails(
      feedbackCol(ATHLETE)
        .doc("s6b")
        .set(validFeedback({ exerciseName: "x".repeat(201) })),
    );
    await assertFails(
      feedbackCol(ATHLETE)
        .doc("s6c")
        .set(
          validFeedback({
            text: null,
            photoUrl: `https://x/${"y".repeat(2001)}`,
            photoPath: "sessionFeedback/a/b/c.jpg",
          }),
        ),
    );
  });

  it("S7: la validación también corre en update, no sólo en create", async () => {
    // Un create válido seguido de un update que vacía el reporte dejaría el
    // documento en un estado que el create rechaza. Mismo predicado en los dos.
    await seedFeedback();
    await assertFails(
      feedbackCol(ATHLETE)
        .doc(FEEDBACK_ID)
        .set(validFeedback({ text: null, photoUrl: null })),
    );
    await assertFails(
      feedbackCol(ATHLETE)
        .doc(FEEDBACK_ID)
        .set(validFeedback({ kind: "whatever" })),
    );
  });
});

// ─── El grant es lo que abre la puerta, y revocarlo la cierra ────────────────

describe("exerciseFeedback — revocar el grant cierra el acceso del PF", () => {
  it("el PF deja de leer el feedback en cuanto el alumno revoca", async () => {
    await seedFeedback();
    await seedGrant(TRAINER);
    await assertSucceeds(feedbackCol(TRAINER).doc(FEEDBACK_ID).get());

    await assertSucceeds(
      ctxDb(ATHLETE).collection(COL_SESSION_SHARES).doc(ATHLETE).delete(),
    );

    await assertFails(feedbackCol(TRAINER).doc(FEEDBACK_ID).get());
  });
});
