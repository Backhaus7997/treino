/**
 * parsePlanPdf (slice 3b) contra el emulador de Firestore, con el LLM
 * reemplazado por un doble (`PlanExtractor`). Sin red y sin Vertex.
 *
 * Cubre el orden del callable —auth, rol, kill switch, archivo, cupo, LLM,
 * validacion— y, sobre todo, la plata: que el cupo se descuente antes del
 * LLM, que corte por semana y por dia con el `resetsAt` correcto, que una
 * rafaga en paralelo no lo atraviese, y que vuelva cuando falla algo nuestro.
 *
 * Requiere FIRESTORE_EMULATOR_HOST=127.0.0.1:8080.
 */
import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { PDFDocument } from "pdf-lib";

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

import { parsePlanPdf, runParsePlanPdf, ParsePlanPdfDeps } from "../pdf-import/parse-plan-pdf";
import { ExtractorError, ExtractRequest, PlanExtractor } from "../pdf-import/provider";
import { quotaKeys, resetsAt } from "../pdf-import/quota";

let app: App;
const db = () => getFirestore(app);

// Jueves 2026-10-22, 12:00 en Buenos Aires. Semana: lunes 2026-10-19.
const NOW = new Date("2026-10-22T15:00:00Z");
const WEEK = "2026-10-19";
const DAY = "2026-10-22";

let pdf1: string;
let pdf21: string;

beforeAll(async () => {
  app = initializeApp({ projectId: "treino-dev" }, "parse-plan-pdf-test");
  const make = async (pages: number) => {
    const doc = await PDFDocument.create();
    for (let i = 0; i < pages; i++) doc.addPage();
    return Buffer.from(await doc.save()).toString("base64");
  };
  pdf1 = await make(1);
  pdf21 = await make(21);
});

afterAll(async () => {
  await setConfig(null);
  await deleteApp(app);
});

const set = { type: "normal", weightKg: 60, reps: 8, repsMin: null, repsMax: null,
  durationSeconds: null, distanceMeters: null };

function planWith(candidates: (string | null)[]) {
  return {
    numWeeks: 1,
    days: [{
      dayNumber: 1,
      title: "Torso A",
      rows: candidates.map((c, i) => ({
        number: i + 1,
        restSeconds: 90,
        exercises: [{
          component: 1,
          rawName: `Ejercicio ${i + 1}`,
          note: null,
          weeks: [[set]],
          candidateExerciseId: c,
          candidateConfidence: c == null ? null : 0.8,
          sourceText: null,
        }],
      })),
    }],
    warnings: [],
  };
}

/** Un doble del LLM: devuelve lo que se le diga o tira, y cuenta llamadas. */
function fakeExtractor(behavior: (req: ExtractRequest) => unknown | Promise<unknown>) {
  const calls: ExtractRequest[] = [];
  const extractor: PlanExtractor = {
    async extract(req) {
      calls.push(req);
      return { raw: await behavior(req), model: req.model };
    },
  };
  return { extractor, calls };
}

// Un uid por test: los docs no se pisan entre casos ni con otras suites.
let seq = 0;
let uid: string;

function deps(extractor: PlanExtractor): ParsePlanPdfDeps {
  return {
    db: db(),
    extractor,
    now: () => NOW,
    loadCatalog: async () => [{ id: "ex-press-banca", name: "Press banca" }],
  };
}

async function seedTrainer(extra: Record<string, unknown> = {}) {
  await db().collection("users").doc(uid).set({ role: "trainer", ...extra });
}

async function setConfig(config: Record<string, unknown> | null) {
  const ref = db().doc("app_config/pdf_import");
  if (config == null) await ref.delete();
  else await ref.set(config);
}

async function usage() {
  return (await db().collection("pdfImportUsage").doc(uid).get()).data();
}

async function expectHttpsError(p: Promise<unknown>, code: string, details?: unknown) {
  const err = await p.then(
    () => { throw new Error(`se esperaba ${code} y salio bien`); },
    (e) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  expect((err as HttpsError).code).toBe(code);
  if (details !== undefined) expect((err as HttpsError).details).toEqual(details);
}

beforeEach(async () => {
  uid = `pdf-trainer-${Date.now()}-${seq++}`;
  await setConfig({ enabled: true });
  await db().collection("exercises").doc("ex-press-banca").set({ name: "Press banca" });
});

describe("configuracion del callable", () => {
  it("southamerica-east1, timeout 300, maxInstances acotado y SIN App Check", () => {
    const endpoint = (parsePlanPdf as unknown as { __endpoint: Record<string, unknown> }).__endpoint;
    expect(endpoint.region).toEqual(["southamerica-east1"]);
    expect(endpoint.timeoutSeconds).toBe(300);
    expect(endpoint.maxInstances).toBe(10);
    expect(JSON.stringify(endpoint)).not.toContain("enforceAppCheck");
  });

  it("se exporta desde index.ts", async () => {
    const index = await import("../index");
    expect((index as Record<string, unknown>).parsePlanPdf).toBeDefined();
  });
});

describe("auth y rol", () => {
  it("sin auth: unauthenticated, sin llamar al LLM", async () => {
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), undefined, { pdfBase64: pdf1 }), "unauthenticated");
    expect(f.calls).toHaveLength(0);
  });

  it("un atleta: permission-denied", async () => {
    await db().collection("users").doc(uid).set({ role: "athlete" });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "permission-denied");
    expect(f.calls).toHaveLength(0);
  });

  it("sin doc de usuario: permission-denied", async () => {
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "permission-denied");
  });
});

describe("kill switch", () => {
  it.each([
    ["sin doc", null],
    ["enabled false", { enabled: false }],
    ["enabled 'true' (string)", { enabled: "true" }],
  ])("%s: failed-precondition, sin descontar cupo", async (_n, config) => {
    await seedTrainer();
    await setConfig(config as Record<string, unknown> | null);
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "failed-precondition");
    expect(f.calls).toHaveLength(0);
    expect(await usage()).toBeUndefined();
  });
});

describe("lista de prueba (allowlistUids)", () => {
  it("apagado: un uid de la lista pasa, y el cupo se le aplica igual", async () => {
    await seedTrainer();
    await setConfig({ enabled: false, allowlistUids: ["otro-uid", uid] });
    const f = fakeExtractor(() => planWith([null]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(res.quota).toMatchObject({ usedThisWeek: 1, limitWeekly: 2 });
    expect(await usage()).toMatchObject({ weekCount: 1, dayCount: 1 });
  });

  it("apagado: un uid fuera de la lista rebota con failed-precondition", async () => {
    await seedTrainer();
    await setConfig({ enabled: false, allowlistUids: ["otro-uid"] });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "failed-precondition");
    expect(f.calls).toHaveLength(0);
  });

  it("apagado: estar en la lista no saltea el rol", async () => {
    await db().collection("users").doc(uid).set({ role: "athlete" });
    await setConfig({ enabled: false, allowlistUids: [uid] });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "permission-denied");
  });

  it("apagado: la lista con otra forma (string) no habilita a nadie", async () => {
    await seedTrainer();
    await setConfig({ enabled: false, allowlistUids: uid });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), "failed-precondition");
  });

  it("prendido: pasan todos los trainers, esten o no en la lista", async () => {
    await seedTrainer();
    await setConfig({ enabled: true, allowlistUids: ["otro-uid"] });
    const f = fakeExtractor(() => planWith([null]));
    await expect(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 })).resolves.toBeDefined();
  });
});

describe("el archivo", () => {
  it.each([
    ["no es PDF", () => Buffer.from("hola").toString("base64"), "not_pdf"],
    ["21 paginas", () => pdf21, "too_many_pages"],
    ["mas de 5 MB", () => "A".repeat(7_000_000), "too_big"],
  ])("%s: invalid-argument con el motivo, sin descontar cupo", async (_n, pdf, reason) => {
    await seedTrainer();
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(
      runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf(), fileName: "x.pdf" }),
      "invalid-argument",
      { reason },
    );
    expect(f.calls).toHaveLength(0);
    expect(await usage()).toBeUndefined();
  });
});

describe("camino feliz", () => {
  it("devuelve el plan, el cupo y el modelo, y descuenta uno", async () => {
    await seedTrainer();
    const f = fakeExtractor(() => planWith(["ex-press-banca"]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1, fileName: "plan.pdf" });

    expect(res.model).toBe("claude-opus-5-5");
    expect(res.quota).toEqual({ usedThisWeek: 1, limitWeekly: 2, usedToday: 1, limitDaily: 2 });
    expect(res.plan.days[0].rows[0].exercises[0].candidateExerciseId).toBe("ex-press-banca");
    expect(await usage()).toMatchObject({ weekKey: WEEK, weekCount: 1, dayKey: DAY, dayCount: 1 });

    expect(f.calls).toHaveLength(1);
    expect(f.calls[0]).toMatchObject({ pdfBase64: pdf1, fileName: "plan.pdf", effort: "medium" });
  });

  it("el modelo y el effort salen de app_config, sin redeploy", async () => {
    await seedTrainer();
    await setConfig({ enabled: true, model: "claude-haiku-5-5", effort: "low" });
    const f = fakeExtractor(() => planWith([null]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(res.model).toBe("claude-haiku-5-5");
    expect(f.calls[0]).toMatchObject({ model: "claude-haiku-5-5", effort: "low" });
  });

  it("un modelo o effort desconocido en app_config cae al default", async () => {
    await seedTrainer();
    await setConfig({ enabled: true, model: "gpt-5", effort: "turbo" });
    const f = fakeExtractor(() => planWith([null]));
    await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(f.calls[0]).toMatchObject({ model: "claude-opus-5-5", effort: "medium" });
  });
});

describe("cupo", () => {
  it("semanal agotado (free 2/2): resource-exhausted con scope week y el lunes siguiente", async () => {
    await seedTrainer();
    await db().collection("pdfImportUsage").doc(uid).set({
      weekKey: WEEK, weekCount: 2, dayKey: "2026-10-20", dayCount: 2,
    });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(
      runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }),
      "resource-exhausted",
      { scope: "week", resetsAt: "2026-10-26T03:00:00.000Z" },
    );
    expect(f.calls).toHaveLength(0);
  });

  it("diario agotado (plan2: 10 por dia) con semana libre: scope day y la medianoche siguiente", async () => {
    await seedTrainer({ subscription: { tier: "plan2", status: "active" } });
    await db().collection("pdfImportUsage").doc(uid).set({
      weekKey: WEEK, weekCount: 10, dayKey: DAY, dayCount: 10,
    });
    const f = fakeExtractor(() => planWith([null]));
    await expectHttpsError(
      runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }),
      "resource-exhausted",
      { scope: "day", resetsAt: "2026-10-23T03:00:00.000Z" },
    );
    expect(f.calls).toHaveLength(0);
  });

  it("el tier sale de la suscripcion: plan3 informa 30/10", async () => {
    await seedTrainer({ subscription: { tier: "plan3", status: "active" } });
    const f = fakeExtractor(() => planWith([null]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(res.quota).toMatchObject({ limitWeekly: 30, limitDaily: 10 });
  });

  it("contadores de una semana y un dia viejos valen cero", async () => {
    await seedTrainer();
    await db().collection("pdfImportUsage").doc(uid).set({
      weekKey: "2026-10-12", weekCount: 99, dayKey: "2026-10-18", dayCount: 99,
    });
    const f = fakeExtractor(() => planWith([null]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(res.quota).toMatchObject({ usedThisWeek: 1, usedToday: 1 });
  });

  it("una rafaga en paralelo no atraviesa el cupo (free: 3 a la vez, pasan 2)", async () => {
    await seedTrainer();
    const f = fakeExtractor(() => planWith([null]));
    const results = await Promise.allSettled(
      [0, 1, 2].map(() => runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 })),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(2);
    const rejected = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
    expect(rejected).toHaveLength(1);
    expect((rejected[0].reason as HttpsError).code).toBe("resource-exhausted");
    expect(await usage()).toMatchObject({ weekCount: 2, dayCount: 2 });
  });
});

describe("falla nuestra: se devuelve el cupo", () => {
  it.each([
    ["el proveedor falla", "internal", () => { throw new ExtractorError("provider", "503"); }],
    ["el modelo se niega", "internal", () => { throw new ExtractorError("refusal", "no"); }],
    ["salida truncada", "internal", () => { throw new ExtractorError("truncated", "max_tokens"); }],
    ["timeout del LLM", "deadline-exceeded", () => { throw new ExtractorError("timeout", "slow"); }],
    ["error inesperado", "internal", () => { throw new Error("boom"); }],
    ["salida invalida (numWeeks 99)", "internal", () => ({ ...planWith([null]), numWeeks: 99 })],
    ["salida que no es un plan", "internal", () => "hola"],
  ])("%s: %s y el contador vuelve a cero", async (_n, code, behavior) => {
    await seedTrainer();
    const f = fakeExtractor(behavior as () => unknown);
    await expectHttpsError(runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 }), code as string);
    expect(f.calls).toHaveLength(1);
    expect(await usage()).toMatchObject({ weekKey: WEEK, weekCount: 0, dayKey: DAY, dayCount: 0 });
  });

  it("un LLM que no contesta corta en el deadline propio: deadline-exceeded y cupo devuelto", async () => {
    await seedTrainer();
    const f = fakeExtractor(() => new Promise(() => undefined));
    await expectHttpsError(
      runParsePlanPdf({ ...deps(f.extractor), llmDeadlineMs: 50 }, uid, { pdfBase64: pdf1 }),
      "deadline-exceeded",
    );
    expect(await usage()).toMatchObject({ weekCount: 0, dayCount: 0 });
  });

  it("la devolucion no toca el uso previo: 1 usado + 1 fallido = 1", async () => {
    await seedTrainer();
    const ok = fakeExtractor(() => planWith([null]));
    await runParsePlanPdf(deps(ok.extractor), uid, { pdfBase64: pdf1 });
    const bad = fakeExtractor(() => { throw new ExtractorError("provider", "503"); });
    await expectHttpsError(runParsePlanPdf(deps(bad.extractor), uid, { pdfBase64: pdf1 }), "internal");
    expect(await usage()).toMatchObject({ weekCount: 1, dayCount: 1 });
  });
});

describe("candidatos del catalogo", () => {
  it("un id inexistente se anula (id y confianza); uno existente se conserva", async () => {
    await seedTrainer();
    const f = fakeExtractor(() => planWith(["ex-press-banca", "ex-inventado", null]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    const exs = res.plan.days[0].rows.map((r) => r.exercises[0]);
    expect(exs[0]).toMatchObject({ candidateExerciseId: "ex-press-banca", candidateConfidence: 0.8 });
    expect(exs[1]).toMatchObject({ candidateExerciseId: null, candidateConfidence: null });
    expect(exs[2]).toMatchObject({ candidateExerciseId: null, candidateConfidence: null });
  });

  it("un id con forma invalida (barra, __x__) se anula sin tumbar el plan", async () => {
    await seedTrainer();
    const f = fakeExtractor(() => planWith(["exercises/otro", "__nope__", "ex-press-banca"]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    const ids = res.plan.days[0].rows.map((r) => r.exercises[0].candidateExerciseId);
    expect(ids).toEqual([null, null, "ex-press-banca"]);
  });

  it("se verifica contra Firestore, no contra el catalogo que viajo en el prompt", async () => {
    await seedTrainer();
    await db().collection("exercises").doc("ex-press-banca").delete();
    const f = fakeExtractor(() => planWith(["ex-press-banca"]));
    const res = await runParsePlanPdf(deps(f.extractor), uid, { pdfBase64: pdf1 });
    expect(res.plan.days[0].rows[0].exercises[0].candidateExerciseId).toBeNull();
  });
});

describe("claves de semana y dia en Buenos Aires", () => {
  it("domingo 23:59 ART sigue en la semana; lunes 00:00 ART empieza otra", () => {
    expect(quotaKeys(new Date("2026-10-26T02:59:00Z"))).toEqual({ weekKey: WEEK, dayKey: "2026-10-25" });
    expect(quotaKeys(new Date("2026-10-26T03:00:00Z"))).toEqual({ weekKey: "2026-10-26", dayKey: "2026-10-26" });
  });

  it("los siete dias de la semana, a la mañana y a la noche, caen en el mismo lunes", () => {
    for (let d = 0; d < 7; d++) {
      for (const hourUtc of [3, 14, 26]) { // 00:00, 11:00 y 23:00 ART
        const t = new Date(Date.UTC(2026, 9, 19 + d, hourUtc, 30));
        expect(quotaKeys(t).weekKey).toBe(WEEK);
      }
    }
  });

  it("cruza meses y años", () => {
    expect(quotaKeys(new Date("2027-01-01T15:00:00Z")).weekKey).toBe("2026-12-28");
    expect(resetsAt(quotaKeys(new Date("2026-12-31T15:00:00Z")), "day")).toBe("2027-01-01T03:00:00.000Z");
  });
});
