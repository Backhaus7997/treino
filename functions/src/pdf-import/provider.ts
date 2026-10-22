/**
 * provider.ts — el adaptador del LLM que lee el PDF.
 *
 * `parsePlanPdf` no conoce a Vertex: recibe un `PlanExtractor`. Los tests le
 * pasan un doble; produccion, `vertexPlanExtractor`. Asi el callable se prueba
 * contra el emulador sin red y sin gastar un centavo, y cambiar de proveedor
 * (Anthropic directo, otro modelo) es escribir otro adaptador, no tocar el
 * flujo del cupo.
 *
 * El adaptador devuelve la salida CRUDA (JSON parseado, sin validar): validar
 * es trabajo de `validateExtraction`, que no confia en ningun proveedor.
 *
 * Errores: el adaptador traduce lo suyo a `ExtractorError` con un `kind`
 * que el callable mapea al codigo del contrato — `timeout` a
 * `deadline-exceeded`, todo lo demas a `internal` —, y los dos devuelven el
 * cupo.
 */
import AnthropicVertex from "@anthropic-ai/vertex-sdk";
import { APIConnectionTimeoutError, APIUserAbortError } from "@anthropic-ai/sdk";
import { buildSystemPrompt, CatalogEntry, USER_TEXT } from "./prompt";
import { PDF_PLAN_EXTRACTION_SCHEMA } from "./extraction";

export const SUPPORTED_MODELS = [
  "claude-opus-5-5",
  "claude-sonnet-5-5",
  "claude-haiku-5-5",
] as const;
export type SupportedModel = (typeof SUPPORTED_MODELS)[number];
export const DEFAULT_MODEL: SupportedModel = "claude-opus-5-5";

export const SUPPORTED_EFFORTS = ["low", "medium", "high"] as const;
export type Effort = (typeof SUPPORTED_EFFORTS)[number];
export const DEFAULT_EFFORT: Effort = "medium";

export interface ExtractRequest {
  pdfBase64: string;
  catalog: readonly CatalogEntry[];
  model: SupportedModel;
  effort: Effort;
}

export interface ExtractResult {
  raw: unknown;
  /** El modelo que respondio, segun el proveedor. */
  model: string;
}

export type ExtractorErrorKind = "timeout" | "refusal" | "truncated" | "bad_output" | "provider";

export class ExtractorError extends Error {
  constructor(public readonly kind: ExtractorErrorKind, message: string) {
    super(message);
    this.name = "ExtractorError";
  }
}

export interface PlanExtractor {
  extract(req: ExtractRequest): Promise<ExtractResult>;
}

/**
 * Topes de la llamada. `max_tokens` corta una salida desbocada (y su costo);
 * el timeout del SDK queda por debajo de los 300 s del callable para que el
 * error sea nuestro `deadline-exceeded` y no un corte del runtime que no
 * devuelve el cupo. Sin reintentos: un reintento duplicaria el tiempo y el
 * gasto de una llamada que ya fallo.
 */
export const LLM_MAX_TOKENS = 64_000;
export const LLM_TIMEOUT_MS = 270_000;

/**
 * Claude en Vertex AI, endpoint `global`, con las credenciales de la service
 * account de la funcion (ADC). Sin API key ni secret.
 */
export function vertexPlanExtractor(projectId: string): PlanExtractor {
  const client = new AnthropicVertex({
    projectId,
    region: "global",
    timeout: LLM_TIMEOUT_MS,
    maxRetries: 0,
  });

  return {
    async extract(req) {
      let message;
      try {
        // Streaming: con salidas largas, una request no-streaming puede
        // cortarse por timeout HTTP antes de terminar.
        message = await client.messages
          .stream({
            model: req.model,
            max_tokens: LLM_MAX_TOKENS,
            system: [
              {
                type: "text",
                text: buildSystemPrompt(req.catalog),
                // Instrucciones + catalogo son estables entre llamadas.
                cache_control: { type: "ephemeral" },
              },
            ],
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "document",
                    source: {
                      type: "base64",
                      media_type: "application/pdf",
                      data: req.pdfBase64,
                    },
                  },
                  { type: "text", text: USER_TEXT },
                ],
              },
            ],
            output_config: {
              effort: req.effort,
              format: { type: "json_schema", schema: PDF_PLAN_EXTRACTION_SCHEMA },
            },
          }, {
            // El timeout del cliente cubre la espera de la respuesta; esta
            // señal corta tambien la lectura del stream.
            signal: AbortSignal.timeout(LLM_TIMEOUT_MS),
          })
          .finalMessage();
      } catch (e) {
        if (
          e instanceof APIConnectionTimeoutError ||
          (e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError")) ||
          (e instanceof APIUserAbortError)
        ) {
          throw new ExtractorError("timeout", "LLM call timed out.");
        }
        throw new ExtractorError("provider", e instanceof Error ? e.message : String(e));
      }

      if (message.stop_reason === "refusal") {
        throw new ExtractorError("refusal", "The model declined the request.");
      }
      if (message.stop_reason === "max_tokens") {
        throw new ExtractorError("truncated", "Output hit max_tokens.");
      }
      const text = message.content
        .filter((b) => b.type === "text")
        .map((b) => (b as { text: string }).text)
        .join("");
      try {
        return { raw: JSON.parse(text), model: message.model };
      } catch {
        throw new ExtractorError("bad_output", "Output is not valid JSON.");
      }
    },
  };
}
