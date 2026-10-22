/**
 * extraction.ts — la forma de `PdfPlanExtraction` (contrato
 * `pdf-import-contrato.md`), el JSON schema que se le pasa al LLM y el
 * validador que la revisa al volver.
 *
 * ─── Por que hay DOS capas (schema + validador) ─────────────────────────────
 *
 * Los structured outputs de Claude (`output_config.format`) garantizan la
 * FORMA —tipos, campos requeridos, enums—, pero no aceptan restricciones
 * numericas ni de largo (`minimum`, `maximum`, `maxLength`) ni schemas
 * recursivos. Asi que el schema de aca abajo describe la forma y nada mas, y
 * TODOS los topes del contrato (16 semanas, 7 dias, reps <= 999, kg <= 500,
 * `weeks.length == numWeeks`, reps XOR rango…) los revisa `validateExtraction`
 * despues. Lo que no cumpla se rechaza entero: el callable devuelve `internal`
 * y le devuelve el cupo al PF (es error nuestro, no del archivo).
 *
 * El cliente vuelve a validar con `periodized_plan_json.dart`. Los topes
 * EXTRA de este archivo (los que el contrato no fija: series por semana,
 * filas por dia, largos de texto) son cotas de sanidad contra una salida
 * desbocada, y estan elegidos holgados para no rechazar un plan real.
 */

/** Los valores de `SetType` (`lib/features/workout/domain/set_enums.dart`). */
export const SET_TYPES = ["warmup", "normal", "drop", "failure"] as const;
export type SetTypeName = (typeof SET_TYPES)[number];

export interface PdfSet {
  type: SetTypeName;
  weightKg: number | null;
  reps: number | null;
  repsMin: number | null;
  repsMax: number | null;
  durationSeconds: number | null;
  distanceMeters: number | null;
}

export interface PdfExercise {
  component: number;
  rawName: string;
  note: string | null;
  /** Una lista de series por semana; `weeks.length === numWeeks`. */
  weeks: PdfSet[][];
  candidateExerciseId: string | null;
  candidateConfidence: number | null;
  sourceText: string | null;
}

export interface PdfRow {
  /** `null` = calentamiento. */
  number: number | null;
  restSeconds: number | null;
  exercises: PdfExercise[];
}

export interface PdfDay {
  dayNumber: number;
  title: string | null;
  rows: PdfRow[];
}

export interface PdfWarning {
  code: string;
  message: string;
  page: number | null;
}

export interface PdfPlanExtraction {
  numWeeks: number;
  days: PdfDay[];
  warnings: PdfWarning[];
}

/**
 * Los topes. Los marcados "contrato" salen de `pdf-import-contrato.md` y de
 * `set_limits.dart`; el resto son cotas de sanidad (ver el header).
 */
export const EXTRACTION_LIMITS = {
  maxWeeks: 16, // contrato
  maxDays: 7, // contrato
  maxRestSeconds: 600, // contrato
  maxReps: 999, // contrato (kMaxReps)
  maxWeightKg: 500, // contrato (kMaxWeightKg)
  maxSourceTextChars: 300, // contrato
  maxRowsPerDay: 40,
  maxExercisesPerRow: 6,
  maxSetsPerWeek: 20,
  maxDurationSeconds: 36_000, // 10 h
  maxDistanceMeters: 100_000, // 100 km
  maxRawNameChars: 200,
  maxNoteChars: 500,
  maxTitleChars: 120,
  maxWarnings: 50,
  maxWarningCodeChars: 60,
  maxWarningMessageChars: 300,
} as const;

// ─── JSON schema (solo forma) ───────────────────────────────────────────────

const nullable = (schema: Record<string, unknown>) => ({
  anyOf: [schema, { type: "null" }],
});

const SET_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "type",
    "weightKg",
    "reps",
    "repsMin",
    "repsMax",
    "durationSeconds",
    "distanceMeters",
  ],
  properties: {
    type: { type: "string", enum: [...SET_TYPES] },
    weightKg: nullable({ type: "number" }),
    reps: nullable({ type: "integer" }),
    repsMin: nullable({ type: "integer" }),
    repsMax: nullable({ type: "integer" }),
    durationSeconds: nullable({ type: "integer" }),
    distanceMeters: nullable({ type: "number" }),
  },
};

const EXERCISE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "component",
    "rawName",
    "note",
    "weeks",
    "candidateExerciseId",
    "candidateConfidence",
    "sourceText",
  ],
  properties: {
    component: { type: "integer" },
    rawName: { type: "string" },
    note: nullable({ type: "string" }),
    weeks: { type: "array", items: { type: "array", items: SET_SCHEMA } },
    candidateExerciseId: nullable({ type: "string" }),
    candidateConfidence: nullable({ type: "number" }),
    sourceText: nullable({ type: "string" }),
  },
};

/**
 * El schema que viaja en `output_config.format`. Sin `minimum`/`maximum`/
 * `maxLength` ni recursion (los structured outputs no los aceptan), y con
 * `additionalProperties: false` y todos los campos en `required` en cada
 * objeto. Los opcionales del contrato van como `anyOf [T, null]`.
 */
export const PDF_PLAN_EXTRACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["numWeeks", "days", "warnings"],
  properties: {
    numWeeks: { type: "integer" },
    days: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["dayNumber", "title", "rows"],
        properties: {
          dayNumber: { type: "integer" },
          title: nullable({ type: "string" }),
          rows: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["number", "restSeconds", "exercises"],
              properties: {
                number: nullable({ type: "integer" }),
                restSeconds: nullable({ type: "integer" }),
                exercises: { type: "array", items: EXERCISE_SCHEMA },
              },
            },
          },
        },
      },
    },
    warnings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["code", "message", "page"],
        properties: {
          code: { type: "string" },
          message: { type: "string" },
          page: nullable({ type: "integer" }),
        },
      },
    },
  },
} as const;

// ─── Validador ──────────────────────────────────────────────────────────────

export type ValidationResult =
  | { ok: true; plan: PdfPlanExtraction }
  | { ok: false; errors: string[] };

/**
 * Revisa una salida del LLM contra los topes. Devuelve TODOS los errores (con
 * su ruta JSON) y no solo el primero: van al log, y un log con un solo error
 * esconde si el modelo se equivoco en una celda o en todo el plan.
 *
 * Lo valida entero aunque el schema ya haya garantizado la forma: el schema
 * lo aplica el proveedor, y este validador es la unica capa que controlamos
 * nosotros. Un cambio de modelo o de proveedor no puede abrir un agujero.
 */
export function validateExtraction(raw: unknown): ValidationResult {
  const errors: string[] = [];
  const err = (path: string, msg: string) => errors.push(`${path}: ${msg}`);
  const L = EXTRACTION_LIMITS;

  if (!isObject(raw)) return { ok: false, errors: ["$: no es un objeto"] };

  const numWeeks = raw.numWeeks;
  if (!isIntIn(numWeeks, 1, L.maxWeeks)) {
    err("$.numWeeks", `tiene que ser un entero entre 1 y ${L.maxWeeks}`);
  }

  if (!Array.isArray(raw.days)) {
    err("$.days", "no es una lista");
  } else {
    if (raw.days.length < 1 || raw.days.length > L.maxDays) {
      err("$.days", `tiene que tener entre 1 y ${L.maxDays} dias`);
    }
    const seen = new Set<number>();
    raw.days.forEach((day, d) => {
      const p = `$.days[${d}]`;
      if (!isObject(day)) { err(p, "no es un objeto"); return; }
      if (!isIntIn(day.dayNumber, 1, L.maxDays)) {
        err(`${p}.dayNumber`, `tiene que ser un entero entre 1 y ${L.maxDays}`);
      } else if (seen.has(day.dayNumber as number)) {
        err(`${p}.dayNumber`, `repetido (${day.dayNumber})`);
      } else {
        seen.add(day.dayNumber as number);
      }
      checkOptionalText(day.title, L.maxTitleChars, `${p}.title`, err);
      checkRows(day.rows, p, numWeeks, err);
    });
  }

  if (!Array.isArray(raw.warnings)) {
    err("$.warnings", "no es una lista");
  } else {
    if (raw.warnings.length > L.maxWarnings) {
      err("$.warnings", `mas de ${L.maxWarnings} avisos`);
    }
    raw.warnings.forEach((w, i) => {
      const p = `$.warnings[${i}]`;
      if (!isObject(w)) { err(p, "no es un objeto"); return; }
      checkText(w.code, L.maxWarningCodeChars, `${p}.code`, err);
      checkText(w.message, L.maxWarningMessageChars, `${p}.message`, err);
      if (w.page !== null && !isIntIn(w.page, 1, 10_000)) {
        err(`${p}.page`, "tiene que ser un entero >= 1 o null");
      }
    });
  }

  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, plan: raw as unknown as PdfPlanExtraction };
}

type Err = (path: string, msg: string) => void;

function checkRows(rows: unknown, dayPath: string, numWeeks: unknown, err: Err) {
  const L = EXTRACTION_LIMITS;
  const p = `${dayPath}.rows`;
  if (!Array.isArray(rows)) { err(p, "no es una lista"); return; }
  if (rows.length < 1 || rows.length > L.maxRowsPerDay) {
    err(p, `tiene que tener entre 1 y ${L.maxRowsPerDay} filas`);
  }
  rows.forEach((row, r) => {
    const rp = `${p}[${r}]`;
    if (!isObject(row)) { err(rp, "no es un objeto"); return; }
    if (row.number !== null && !isIntIn(row.number, 1, L.maxRowsPerDay)) {
      err(`${rp}.number`, "tiene que ser un entero >= 1 o null (calentamiento)");
    }
    if (row.restSeconds !== null && !isIntIn(row.restSeconds, 0, L.maxRestSeconds)) {
      err(`${rp}.restSeconds`, `tiene que ser un entero entre 0 y ${L.maxRestSeconds} o null`);
    }
    if (!Array.isArray(row.exercises)) { err(`${rp}.exercises`, "no es una lista"); return; }
    const n = row.exercises.length;
    if (n < 1 || n > L.maxExercisesPerRow) {
      err(`${rp}.exercises`, `tiene que tener entre 1 y ${L.maxExercisesPerRow} ejercicios`);
    }
    const components = new Set<number>();
    row.exercises.forEach((ex, e) => {
      const ep = `${rp}.exercises[${e}]`;
      if (!isObject(ex)) { err(ep, "no es un objeto"); return; }
      if (!isIntIn(ex.component, 1, n) || components.has(ex.component as number)) {
        err(`${ep}.component`, `tiene que ser unico y estar entre 1 y ${n}`);
      } else {
        components.add(ex.component as number);
      }
      checkText(ex.rawName, L.maxRawNameChars, `${ep}.rawName`, err);
      checkOptionalText(ex.note, L.maxNoteChars, `${ep}.note`, err);
      checkOptionalText(ex.sourceText, L.maxSourceTextChars, `${ep}.sourceText`, err);
      if (
        ex.candidateExerciseId !== null &&
        (typeof ex.candidateExerciseId !== "string" || ex.candidateExerciseId.length === 0)
      ) {
        err(`${ep}.candidateExerciseId`, "tiene que ser un id no vacio o null");
      }
      if (
        ex.candidateConfidence !== null &&
        !(isFiniteNumber(ex.candidateConfidence) &&
          ex.candidateConfidence >= 0 && ex.candidateConfidence <= 1)
      ) {
        err(`${ep}.candidateConfidence`, "tiene que estar entre 0 y 1 o ser null");
      }
      checkWeeks(ex.weeks, `${ep}.weeks`, numWeeks, err);
    });
  });
}

function checkWeeks(weeks: unknown, p: string, numWeeks: unknown, err: Err) {
  const L = EXTRACTION_LIMITS;
  if (!Array.isArray(weeks)) { err(p, "no es una lista"); return; }
  if (typeof numWeeks === "number" && weeks.length !== numWeeks) {
    err(p, `tiene ${weeks.length} semanas y numWeeks es ${numWeeks}`);
  }
  weeks.forEach((sets, w) => {
    const wp = `${p}[${w}]`;
    if (!Array.isArray(sets)) { err(wp, "no es una lista"); return; }
    if (sets.length > L.maxSetsPerWeek) {
      err(wp, `mas de ${L.maxSetsPerWeek} series`);
    }
    sets.forEach((s, i) => checkSet(s, `${wp}[${i}]`, err));
  });
}

function checkSet(s: unknown, p: string, err: Err) {
  const L = EXTRACTION_LIMITS;
  if (!isObject(s)) { err(p, "no es un objeto"); return; }
  if (!(SET_TYPES as readonly unknown[]).includes(s.type)) {
    err(`${p}.type`, `tiene que ser uno de ${SET_TYPES.join(", ")}`);
  }
  if (s.weightKg !== null && !isNumIn(s.weightKg, 0, L.maxWeightKg)) {
    err(`${p}.weightKg`, `tiene que estar entre 0 y ${L.maxWeightKg} o ser null`);
  }
  for (const k of ["reps", "repsMin", "repsMax"] as const) {
    if (s[k] !== null && !isIntIn(s[k], 0, L.maxReps)) {
      err(`${p}.${k}`, `tiene que ser un entero entre 0 y ${L.maxReps} o null`);
    }
  }
  const hasRange = s.repsMin !== null || s.repsMax !== null;
  if (s.reps !== null && hasRange) {
    err(p, "reps y repsMin/repsMax son excluyentes");
  }
  if (hasRange && (s.repsMin === null || s.repsMax === null)) {
    err(p, "un rango necesita repsMin y repsMax");
  }
  if (
    typeof s.repsMin === "number" && typeof s.repsMax === "number" &&
    s.repsMin > s.repsMax
  ) {
    err(p, "repsMin mayor que repsMax");
  }
  if (s.durationSeconds !== null && !isIntIn(s.durationSeconds, 0, L.maxDurationSeconds)) {
    err(`${p}.durationSeconds`, `tiene que ser un entero entre 0 y ${L.maxDurationSeconds} o null`);
  }
  if (s.distanceMeters !== null && !isNumIn(s.distanceMeters, 0, L.maxDistanceMeters)) {
    err(`${p}.distanceMeters`, `tiene que estar entre 0 y ${L.maxDistanceMeters} o ser null`);
  }
}

function checkText(v: unknown, max: number, p: string, err: Err) {
  if (typeof v !== "string" || v.trim().length === 0) { err(p, "texto vacio o ausente"); return; }
  if (v.length > max) err(p, `mas de ${max} caracteres`);
}

function checkOptionalText(v: unknown, max: number, p: string, err: Err) {
  if (v === null) return;
  if (typeof v !== "string") { err(p, "tiene que ser texto o null"); return; }
  if (v.length > max) err(p, `mas de ${max} caracteres`);
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function isNumIn(v: unknown, min: number, max: number): boolean {
  return isFiniteNumber(v) && v >= min && v <= max;
}

function isIntIn(v: unknown, min: number, max: number): boolean {
  return Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
}
