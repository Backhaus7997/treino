/**
 * parsePlanPdf — callable que lee un plan de entrenamiento de un PDF con
 * Claude en Vertex AI y lo devuelve como `PdfPlanExtraction` para la vista
 * previa del PF (contrato `pdf-import-contrato.md`).
 *
 * Pure handler (`runParsePlanPdf`, con dependencias inyectadas) + onCall
 * delgado, mismo molde que `add-alias.ts`.
 *
 * ─── El orden, y por que es ese ─────────────────────────────────────────────
 *
 *   1. auth y `role == "trainer"`.
 *   2. kill switch `app_config/pdf_import.enabled` (apagado por defecto), con
 *      `allowlistUids` como lista de prueba que pasa aunque este apagado.
 *   3. el archivo: `%PDF-`, 5 MB, 20 paginas. Antes del cupo: un archivo que
 *      rebota por forma no le cuesta un import al PF.
 *   4. descuento del cupo en transaccion (`quota.ts`).
 *   5. el LLM, a traves de un `PlanExtractor` inyectable.
 *   6. validacion de la salida y de los candidatos contra el catalogo.
 *   Si 5 o 6 fallan es error NUESTRO: se devuelve el cupo.
 *
 * ─── App Check: NO ──────────────────────────────────────────────────────────
 *
 * Sin `enforceAppCheck`, y la exencion `debt` esta declarada en
 * `__tests__/appcheck-enforcement.test.ts`. La atestacion de esta app no
 * funciona (medicion del #961: hasta CERO validas en Android); con el flag,
 * el boton de importar fallaria casi siempre. Lo que acota el abuso: auth,
 * rol de PF (los crea el equipo), el cupo semanal/diario en transaccion, el
 * kill switch, `maxInstances` y los topes de bytes, paginas y tokens.
 *
 * ─── El modelo se cambia sin redeploy ───────────────────────────────────────
 *
 * `app_config/pdf_import` lleva `{ enabled, allowlistUids?, model?, effort? }`. `model` se
 * acepta solo si esta en `SUPPORTED_MODELS`; cualquier otro valor cae al
 * default y deja un warn. Asi un typo en la consola no rompe el import ni
 * manda la llamada a un modelo que no evaluamos.
 */
import { App, getApp, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { effectiveTier } from "../subscriptions/effective-limit";
import { toSubscriptionState } from "../subscriptions/subscription-state";
import { checkPdf } from "./pdf-check";
import { PdfPlanExtraction, validateExtraction } from "./extraction";
import { CatalogEntry } from "./prompt";
import {
  DEFAULT_EFFORT,
  DEFAULT_MODEL,
  Effort,
  ExtractorError,
  PlanExtractor,
  SUPPORTED_EFFORTS,
  SUPPORTED_MODELS,
  SupportedModel,
  vertexPlanExtractor,
} from "./provider";
import { consumeQuota, QuotaSnapshot, refundQuota } from "./quota";

export const PDF_IMPORT_CONFIG_DOC = "app_config/pdf_import";

export interface ParsePlanPdfRequest {
  pdfBase64?: unknown;
  fileName?: unknown;
  athleteId?: unknown;
}

export interface ParsePlanPdfResponse {
  plan: PdfPlanExtraction;
  quota: QuotaSnapshot;
  model: string;
}

export interface ParsePlanPdfDeps {
  db: Firestore;
  extractor: PlanExtractor;
  now: () => Date;
  loadCatalog: () => Promise<CatalogEntry[]>;
  /** Tope total de la llamada al LLM; por defecto `LLM_DEADLINE_MS`. */
  llmDeadlineMs?: number;
}

/**
 * Tope de la llamada al LLM medido por NOSOTROS, por debajo de los 300 s del
 * callable. El timeout del SDK no alcanza: cubre la espera de la respuesta,
 * no la lectura de un stream largo. Si el runtime mata la funcion a los 300 s
 * no corre el `catch` y el cupo no vuelve; con este tope el error es nuestro
 * `deadline-exceeded` y la devolucion corre.
 */
export const LLM_DEADLINE_MS = 280_000;

function withDeadline<T>(p: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new ExtractorError("timeout", `No answer in ${ms} ms.`)), ms);
  });
  return Promise.race([p, deadline]).finally(() => clearTimeout(timer));
}

/**
 * Un id que Firestore acepta como documento de `exercises`. Lo que no cumple
 * (una barra, `.`, `..`, `__x__`) haria tirar a `doc()`, y un candidato
 * alucinado no puede tumbar un plan valido: se anula como cualquier otro
 * inexistente.
 */
function isValidDocId(id: string): boolean {
  return id.length > 0 && id.length <= 1500 && !id.includes("/") &&
    id !== "." && id !== ".." && !/^__.*__$/.test(id);
}

interface PdfImportConfig {
  model: SupportedModel;
  effort: Effort;
}

/**
 * Lee el kill switch y la config. Apagado si el doc no existe o `enabled` no
 * es `true` literal — salvo para los uids de `allowlistUids`, la lista de
 * prueba: con el import apagado para todos, el dueño evalua con PDFs reales
 * en produccion desde cuentas puntuales. A los de la lista el cupo se les
 * aplica igual.
 */
async function readConfig(db: Firestore, uid: string): Promise<PdfImportConfig> {
  const snap = await db.doc(PDF_IMPORT_CONFIG_DOC).get();
  const data = snap.data() ?? {};
  const allowlisted = Array.isArray(data.allowlistUids) && data.allowlistUids.includes(uid);
  if (data.enabled !== true && !allowlisted) {
    throw new HttpsError("failed-precondition", "PDF import is disabled.");
  }
  let model = DEFAULT_MODEL;
  if (data.model != null) {
    if ((SUPPORTED_MODELS as readonly unknown[]).includes(data.model)) {
      model = data.model as SupportedModel;
    } else {
      logger.warn("parsePlanPdf: model desconocido en app_config — se usa el default", {
        configured: data.model,
        fallback: DEFAULT_MODEL,
      });
    }
  }
  let effort = DEFAULT_EFFORT;
  if (data.effort != null) {
    if ((SUPPORTED_EFFORTS as readonly unknown[]).includes(data.effort)) {
      effort = data.effort as Effort;
    } else {
      logger.warn("parsePlanPdf: effort desconocido en app_config — se usa el default", {
        configured: data.effort,
        fallback: DEFAULT_EFFORT,
      });
    }
  }
  return { model, effort };
}

/**
 * Deja en `null` todo candidato cuyo id no exista en `exercises`. Se consulta
 * el catalogo REAL (getAll por id) y no la lista que viajo en el prompt: el
 * catalogo puede haber cambiado, y el contrato pide "id existente".
 * Devuelve cuantos se anularon, para el log.
 */
async function dropUnknownCandidates(db: Firestore, plan: PdfPlanExtraction): Promise<number> {
  const exercises = plan.days.flatMap((d) => d.rows.flatMap((r) => r.exercises));
  const ids = [...new Set(exercises.map((e) => e.candidateExerciseId)
    .filter((x): x is string => x != null && isValidDocId(x)))];
  const existing = new Set<string>();
  if (ids.length > 0) {
    const snaps = await db.getAll(...ids.map((id) => db.collection("exercises").doc(id)));
    for (const s of snaps) if (s.exists) existing.add(s.id);
  }
  let dropped = 0;
  for (const e of exercises) {
    if (e.candidateExerciseId == null) {
      e.candidateConfidence = null;
    } else if (!existing.has(e.candidateExerciseId)) {
      e.candidateExerciseId = null;
      e.candidateConfidence = null;
      dropped++;
    }
  }
  return dropped;
}

export async function runParsePlanPdf(
  deps: ParsePlanPdfDeps,
  uid: string | undefined,
  data: ParsePlanPdfRequest,
): Promise<ParsePlanPdfResponse> {
  const { db } = deps;

  // ── 1. auth y rol ─────────────────────────────────────────────────────────
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists || userSnap.data()?.role !== "trainer") {
    throw new HttpsError("permission-denied", "Caller must be a trainer.");
  }

  // ── 2. kill switch ────────────────────────────────────────────────────────
  const config = await readConfig(db, uid);

  // ── 3. el archivo ─────────────────────────────────────────────────────────
  const pdf = await checkPdf(data?.pdfBase64);
  if (!pdf.ok) {
    throw new HttpsError("invalid-argument", "Invalid PDF.", { reason: pdf.reason });
  }
  // El nombre del archivo NO viaja al modelo (ver `USER_TEXT` en prompt.ts):
  // solo va al log, recortado.
  const fileName = typeof data.fileName === "string" ? data.fileName.slice(0, 200) : null;

  // ── 4. cupo ───────────────────────────────────────────────────────────────
  const { state } = toSubscriptionState(userSnap.data(), uid);
  const tier = effectiveTier(state, deps.now().getTime());
  const { keys, snapshot } = await consumeQuota(db, uid, tier, deps.now());

  // ── 5 y 6. LLM y validacion; si fallan, se devuelve el cupo ───────────────
  try {
    const catalog = await deps.loadCatalog();
    const result = await withDeadline(
      deps.extractor.extract({
        pdfBase64: data.pdfBase64 as string,
        catalog,
        model: config.model,
        effort: config.effort,
      }),
      deps.llmDeadlineMs ?? LLM_DEADLINE_MS,
    );

    const validation = validateExtraction(result.raw);
    if (!validation.ok) {
      logger.error("parsePlanPdf: salida del LLM invalida", {
        uid,
        model: result.model,
        errors: validation.errors.slice(0, 50),
        errorCount: validation.errors.length,
      });
      throw new HttpsError("internal", "The extracted plan is invalid.");
    }

    const dropped = await dropUnknownCandidates(db, validation.plan);
    logger.info("parsePlanPdf: ok", {
      uid,
      tier,
      model: result.model,
      fileName,
      pages: pdf.pages,
      days: validation.plan.days.length,
      warnings: validation.plan.warnings.length,
      droppedCandidates: dropped,
    });
    return { plan: validation.plan, quota: snapshot, model: result.model };
  } catch (e) {
    await refundQuota(db, uid, keys).catch((refundErr) =>
      logger.error("parsePlanPdf: no se pudo devolver el cupo", { uid, refundErr }),
    );
    if (e instanceof HttpsError) throw e;
    if (e instanceof ExtractorError) {
      logger.error("parsePlanPdf: fallo el LLM", { uid, kind: e.kind, message: e.message });
      if (e.kind === "timeout") {
        throw new HttpsError("deadline-exceeded", "The PDF took too long to process.");
      }
      if (e.kind === "feature_disabled") {
        // No es culpa del PF ni del archivo: falta un paso de rollout. El log
        // dice cual, para que nadie lo tenga que adivinar desde un `internal`.
        logger.error(
          "parsePlanPdf: Vertex rechazo los structured outputs. Falta permitir " +
            "`publishers/anthropic/models/<modelo>:structured_outputs` en la org policy " +
            "constraints/vertexai.allowedPartnerModelFeatures del proyecto " +
            "(docs/plan-import-pdf.md, rollout).",
          { uid, model: config.model, message: e.message },
        );
        throw new HttpsError("failed-precondition", "PDF import is not available.", {
          reason: "structured_outputs_disabled",
        });
      }
      throw new HttpsError("internal", "The PDF could not be processed.");
    }
    logger.error("parsePlanPdf: error inesperado", { uid, error: String(e) });
    throw new HttpsError("internal", "The PDF could not be processed.");
  }
}

// ─── Wiring de produccion ───────────────────────────────────────────────────

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * El catalogo para el prompt, cacheado por instancia: son ~800 docs y no
 * cambian entre un import y el siguiente. La verificacion de candidatos NO usa
 * este cache (ver `dropUnknownCandidates`).
 */
const CATALOG_TTL_MS = 30 * 60 * 1000;
let catalogCache: { at: number; entries: CatalogEntry[] } | null = null;

async function loadCatalogCached(db: Firestore): Promise<CatalogEntry[]> {
  if (catalogCache && Date.now() - catalogCache.at < CATALOG_TTL_MS) return catalogCache.entries;
  const snap = await db.collection("exercises").select("name").get();
  const entries = snap.docs
    .map((d) => ({ id: d.id, name: d.get("name") }))
    .filter((e): e is CatalogEntry => typeof e.name === "string" && e.name.trim().length > 0);
  catalogCache = { at: Date.now(), entries };
  return entries;
}

let extractor: PlanExtractor | null = null;

export const parsePlanPdf = onCall(
  {
    region: "southamerica-east1",
    timeoutSeconds: 300,
    // Cada instancia atiende un import a la vez y puede quedarse esperando al
    // LLM hasta 270 s: 10 instancias acotan cuantos imports corren en
    // paralelo (y el gasto de una rafaga) sin trabar el uso normal.
    maxInstances: 10,
    concurrency: 1,
    memory: "512MiB",
    // Sin enforceAppCheck: ver el header y la exencion `debt`.
  },
  async (request): Promise<ParsePlanPdfResponse> => {
    const db = getFirestore(ensureApp());
    if (!extractor) {
      const projectId = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
      if (!projectId) throw new HttpsError("internal", "Missing project id.");
      extractor = vertexPlanExtractor(projectId);
    }
    return runParsePlanPdf(
      { db, extractor, now: () => new Date(), loadCatalog: () => loadCatalogCached(db) },
      request.auth?.uid,
      (request.data ?? {}) as ParsePlanPdfRequest,
    );
  },
);
