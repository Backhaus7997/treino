/**
 * gemini-provider.ts — el adaptador de Gemini en Vertex AI.
 *
 * Mismo contrato que el de Claude (`PlanExtractor`): mismo system prompt, mismo
 * catalogo, mismo JSON schema y la misma salida CRUDA, que valida
 * `validateExtraction`. Lo unico que cambia es a quien se le pregunta.
 *
 * ─── Por que Gemini ─────────────────────────────────────────────────────────
 *
 * Claude en Vertex arranca con cuota 0 por modelo y hay que pedirla; el
 * 2026-10-27 Google la denego en automatico por el historial de la cuenta de
 * facturacion. Gemini es modelo propio de Google y no pasa por ese porton: en
 * treino-dev responde sin pedir nada. Evaluado con los PDFs de prueba (tabla,
 * semanas en columnas y un escaneado sin capa de texto) con el prompt de
 * produccion: `gemini-4-argon` los transcribio bien los tres.
 *
 * ─── REST y no un SDK ───────────────────────────────────────────────────────
 *
 * Es UN POST a `generateContent`. Las credenciales salen de la service account
 * de la funcion (ADC, via firebase-admin), igual que las de Claude: sin API key
 * ni secret. Un SDK de Google sumaria una dependencia para no ahorrar nada.
 *
 * ─── Reintentos: solo ante 429 y 503 ────────────────────────────────────────
 *
 * Gemini corre sobre capacidad COMPARTIDA de Google: cuando esta saturada
 * rechaza con 429 aunque el proyecto no tenga un limite propio (paso en la
 * evaluacion). Un rechazo no procesa tokens, asi que reintentarlo no cuesta;
 * al reves que con Claude, donde un reintento duplicaria una llamada que ya
 * gasto. Los reintentos comparten el mismo tope de tiempo que la llamada.
 *
 * `effort` no aplica: es un parametro de Claude.
 */
import { buildSystemPrompt, USER_TEXT } from "./prompt";
import { PDF_PLAN_EXTRACTION_SCHEMA } from "./extraction";
import {
  ExtractorError,
  ExtractResult,
  LLM_MAX_TOKENS,
  LLM_TIMEOUT_MS,
  PlanExtractor,
} from "./provider";

/** Esperas antes de cada reintento ante 429/503. Dos reintentos, tres intentos. */
export const GEMINI_RETRY_DELAYS_MS = [3_000, 8_000] as const;

const RETRYABLE_STATUS = new Set([429, 503]);

/** Motivos de corte que son el modelo (o sus filtros) negandose, no un error. */
const REFUSAL_FINISH_REASONS = new Set([
  "SAFETY",
  "PROHIBITED_CONTENT",
  "BLOCKLIST",
  "SPII",
  "RECITATION",
  "IMAGE_SAFETY",
]);

export interface GeminiDeps {
  /** Un access token con scope `cloud-platform` de la service account. */
  getAccessToken: () => Promise<string>;
  fetchFn?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  timeoutMs?: number;
}

/** El cuerpo de `generateContent`. Exportado para el test. */
export function buildGeminiRequest(pdfBase64: string, catalog: Parameters<typeof buildSystemPrompt>[0]) {
  return {
    systemInstruction: { parts: [{ text: buildSystemPrompt(catalog) }] },
    contents: [
      {
        role: "user",
        parts: [
          { inlineData: { mimeType: "application/pdf", data: pdfBase64 } },
          { text: USER_TEXT },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      // El mismo schema que usa Claude, sin tocar: Vertex acepta el JSON Schema
      // tal cual (`anyOf` con null, `additionalProperties: false`).
      responseJsonSchema: PDF_PLAN_EXTRACTION_SCHEMA,
      maxOutputTokens: LLM_MAX_TOKENS,
    },
  };
}

interface GeminiPart {
  text?: string;
  thought?: boolean;
}

interface GeminiResponse {
  candidates?: { content?: { parts?: GeminiPart[] }; finishReason?: string }[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    thoughtsTokenCount?: number;
  };
  modelVersion?: string;
}

/**
 * Traduce una respuesta 200 de `generateContent` a la salida cruda o a un
 * `ExtractorError`. Pura: sin red, para poder probar cada corte.
 */
export function interpretGeminiResponse(body: GeminiResponse, requestedModel: string): ExtractResult {
  const blocked = body.promptFeedback?.blockReason;
  if (blocked) throw new ExtractorError("refusal", `The prompt was blocked: ${blocked}.`);

  const candidate = body.candidates?.[0];
  const finish = candidate?.finishReason;
  if (finish === "MAX_TOKENS") throw new ExtractorError("truncated", "Output hit maxOutputTokens.");
  if (finish && REFUSAL_FINISH_REASONS.has(finish)) {
    throw new ExtractorError("refusal", `The model declined the request: ${finish}.`);
  }
  if (finish && finish !== "STOP") {
    throw new ExtractorError("provider", `Unexpected finishReason: ${finish}.`);
  }

  // Las partes `thought` son el razonamiento del modelo, no la respuesta.
  const text = (candidate?.content?.parts ?? [])
    .filter((p) => !p.thought)
    .map((p) => p.text ?? "")
    .join("");
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new ExtractorError("bad_output", "Output is not valid JSON.");
  }
  const u = body.usageMetadata;
  return {
    raw,
    model: body.modelVersion ?? requestedModel,
    usage: u
      ? {
        inputTokens: u.promptTokenCount ?? 0,
        outputTokens: u.candidatesTokenCount ?? 0,
        thinkingTokens: u.thoughtsTokenCount ?? 0,
      }
      : undefined,
  };
}

function isAbort(e: unknown): boolean {
  return e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError");
}

/** Gemini en Vertex AI, endpoint `global`, con las credenciales de la funcion. */
export function geminiPlanExtractor(projectId: string, deps: GeminiDeps): PlanExtractor {
  const fetchFn = deps.fetchFn ?? fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));

  return {
    async extract(req) {
      const url = "https://aiplatform.googleapis.com/v1/projects/" +
        `${projectId}/locations/global/publishers/google/models/${req.model}:generateContent`;
      const body = JSON.stringify(buildGeminiRequest(req.pdfBase64, req.catalog));
      const timeoutMs = deps.timeoutMs ?? LLM_TIMEOUT_MS;
      const deadline = Date.now() + timeoutMs;
      const signal = AbortSignal.timeout(timeoutMs);

      for (let attempt = 0; ; attempt++) {
        let res: Response;
        let text: string;
        try {
          res = await fetchFn(url, {
            method: "POST",
            headers: {
              "authorization": `Bearer ${await deps.getAccessToken()}`,
              "content-type": "application/json",
            },
            body,
            signal,
          });
          // Leer el cuerpo tambien puede cortarse por el tope: va adentro del
          // try para que sea `timeout` y no una salida vacia.
          text = await res.text();
        } catch (e) {
          if (isAbort(e)) throw new ExtractorError("timeout", "LLM call timed out.");
          throw new ExtractorError("provider", e instanceof Error ? e.message : String(e));
        }
        let json: unknown = null;
        try {
          json = JSON.parse(text);
        } catch {
          // Un error HTTP puede venir sin JSON; un 200 sin JSON lo trata
          // `interpretGeminiResponse` como salida invalida.
        }

        if (res.ok) return interpretGeminiResponse((json ?? {}) as GeminiResponse, req.model);

        const message = (json as { error?: { message?: string } } | null)?.error?.message ?? res.statusText;
        const delay = GEMINI_RETRY_DELAYS_MS[attempt];
        if (RETRYABLE_STATUS.has(res.status) && delay !== undefined) {
          // Si la espera no entra en el tope, no se espera para nada: el error
          // es el timeout, igual que si la llamada hubiera tardado.
          if (Date.now() + delay >= deadline) {
            throw new ExtractorError("timeout", "LLM call timed out while retrying.", res.status);
          }
          await sleep(delay);
          continue;
        }
        throw new ExtractorError("provider", `${res.status}: ${message}`, res.status);
      }
    },
  };
}
