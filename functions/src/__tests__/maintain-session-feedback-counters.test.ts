/**
 * Tests de `maintainSessionFeedbackCounters` — la agregación pura y el handler
 * contra un emulador de Firestore REAL.
 *
 * ## Por qué NO alcanza con testear la función pura
 *
 * El gemelo de este archivo (`maintain-reaction-counters.test.ts`) testea sólo
 * `aggregateReactionCounts`, y esa mitad no puede ver lo único que justifica
 * todo el diseño: que **recontar es idempotente y un `FieldValue.increment()`
 * no lo sería**. Una suite que sólo ejercite la función pura queda igual de
 * verde con un increment ingenuo puesto en el handler — o sea que no prueba la
 * decisión que el header del archivo explica en veinte líneas.
 *
 * Por eso acá el caso central es **llamar al handler dos veces con los mismos
 * datos** y afirmar que el contador NO se movió. Eventarc entrega
 * at-least-once: esa segunda llamada no es hipotética, es el martes.
 *
 * Requiere el emulador de Firestore (Java 21+). Corre en CI vía:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand"
 *
 * `--runInBand` importa: estos tests afirman estado ABSOLUTO sobre un mismo doc
 * de sesión a lo largo de una secuencia de llamadas. El uid es propio de esta
 * suite para que ningún otro archivo escriba el mismo doc.
 *
 * Patrón espejado de `sync-session-share.emulator.test.ts`.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp(
    { projectId: "treino-dev" },
    "maintain-session-feedback-counters-test",
  );
});

afterAll(async () => {
  await deleteApp(testApp);
});

import {
  aggregateFeedbackCounts,
  maintainSessionFeedbackCountersHandler,
} from "../notifications/maintain-session-feedback-counters";

const db = () => getFirestore(testApp);

const ATHLETE = "athlete-feedback-counters";
const SESSION = "session-feedback-counters";

const sessionRef = () =>
  db().collection("users").doc(ATHLETE).collection("sessions").doc(SESSION);

const feedbackRef = (id: string) =>
  sessionRef().collection("exerciseFeedback").doc(id);

async function seedSession(): Promise<void> {
  await sessionRef().set({
    uid: ATHLETE,
    routineId: "r1",
    routineName: "Pecho y tríceps",
    durationMin: 45,
    totalVolumeKg: 1800,
    status: "finished",
    wasFullyCompleted: true,
  });
}

async function seedFeedback(id: string, kind: string): Promise<void> {
  await feedbackRef(id).set({
    kind,
    exerciseId: "e1",
    exerciseName: "Sentadilla",
    text: "algo",
    createdAt: new Date(),
  });
}

async function cleanup(): Promise<void> {
  const subs = await sessionRef().collection("exerciseFeedback").get();
  await Promise.all(subs.docs.map((d) => d.ref.delete()));
  await sessionRef().delete();
}

const countsOf = async () =>
  (await sessionRef().get()).data()?.feedbackCounts as
    | Record<string, number>
    | undefined;

// ─── La función pura ─────────────────────────────────────────────────────────

describe("aggregateFeedbackCounts", () => {
  it("agrupa los reportes por kind", () => {
    expect(
      aggregateFeedbackCounts([
        { kind: "discomfort" },
        { kind: "comment" },
        { kind: "comment" },
      ]),
    ).toEqual({ discomfort: 1, comment: 2 });
  });

  it("devuelve el mapa vacío cuando no hay reportes", () => {
    expect(aggregateFeedbackCounts([])).toEqual({});
  });

  it("no emite claves en cero", () => {
    expect(aggregateFeedbackCounts([{ kind: "comment" }])).toEqual({
      comment: 1,
    });
  });

  it("ignora documentos malformados y kinds que no existen", () => {
    expect(
      aggregateFeedbackCounts([
        { kind: "comment" },
        { kind: "injury" }, // no existe
        { kind: 42 },
        { kind: null },
        {},
      ]),
    ).toEqual({ comment: 1 });
  });

  it("cuenta exactamente los dos kinds que la app y las reglas permiten", () => {
    const counts = aggregateFeedbackCounts([
      { kind: "discomfort" },
      { kind: "comment" },
    ]);
    expect(Object.keys(counts).sort()).toEqual(["comment", "discomfort"]);
  });
});

// ─── El handler, contra el emulador ──────────────────────────────────────────

describe("maintainSessionFeedbackCountersHandler", () => {
  beforeEach(async () => {
    await cleanup().catch(() => undefined);
    await seedSession();
  });

  afterEach(async () => {
    await cleanup().catch(() => undefined);
  });

  it("escribe el mapa en el doc de sesión padre", async () => {
    await seedFeedback("f1", "discomfort");
    await seedFeedback("f2", "comment");

    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);

    expect(await countsOf()).toEqual({ discomfort: 1, comment: 1 });
  });

  // ⚠️ EL TEST QUE JUSTIFICA EL DISEÑO. Eventarc entrega at-least-once, así que
  // el handler se va a ejecutar dos veces sobre el mismo reporte. Con
  // `FieldValue.increment()` esto daría 2 y el contador quedaría desviado para
  // siempre — marcando un dolor que nunca se reportó dos veces.
  it("llamarlo DOS VECES con los mismos datos no duplica el contador", async () => {
    await seedFeedback("f1", "discomfort");

    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);
    const primera = await countsOf();

    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);
    const segunda = await countsOf();

    expect(primera).toEqual({ discomfort: 1 });
    expect(segunda).toEqual({ discomfort: 1 });
  });

  // La otra mitad de lo mismo: recontar maneja los BORRADOS gratis. Un
  // increment necesitaría un decremento simétrico y acertarle al orden de
  // entrega.
  it("borrar un reporte BAJA el contador", async () => {
    await seedFeedback("f1", "discomfort");
    await seedFeedback("f2", "discomfort");
    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);
    expect(await countsOf()).toEqual({ discomfort: 2 });

    await feedbackRef("f2").delete();
    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);

    expect(await countsOf()).toEqual({ discomfort: 1 });
  });

  it("sin reportes deja el mapa vacío, no ausente", async () => {
    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);

    expect(await countsOf()).toEqual({});
  });

  // Un evento tardío sobre una sesión ya borrada no puede recrearla: `update`
  // sobre un doc inexistente tira, y por eso el handler chequea `exists`
  // adentro de la transacción.
  it("no resucita una sesión borrada", async () => {
    await seedFeedback("f1", "discomfort");
    await sessionRef().delete();

    await expect(
      maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION),
    ).resolves.toBeUndefined();

    expect((await sessionRef().get()).exists).toBe(false);
  });

  // `tx.update` con una sola clave no puede pisar el resto del documento. Si
  // alguna vez se cambiara por `set()` sin merge, la sesión perdería rutina,
  // duración y volumen — y el síntoma aparecería lejos de acá.
  it("no pisa los demás campos de la sesión", async () => {
    await seedFeedback("f1", "comment");

    await maintainSessionFeedbackCountersHandler(testApp, ATHLETE, SESSION);

    const data = (await sessionRef().get()).data();
    expect(data?.routineName).toBe("Pecho y tríceps");
    expect(data?.durationMin).toBe(45);
    expect(data?.totalVolumeKg).toBe(1800);
    expect(data?.wasFullyCompleted).toBe(true);
    expect(data?.feedbackCounts).toEqual({ comment: 1 });
  });
});
