/**
 * provider.ts — el contrato del LLM que lee el PDF y el adaptador de Claude.
 *
 * `parsePlanPdf` no conoce a Vertex: recibe un `PlanExtractor`. Los tests le
 * pasan un doble; produccion, un `modelRouter` que manda cada modelo a su
 * adaptador: `geminiPlanExtractor` (gemini-provider.ts, el default) o
 * `vertexPlanExtractor` (Claude, abajo). Asi el callable se prueba contra el
 * emulador sin red y sin gastar un centavo, y cambiar de proveedor es escribir
 * otro adaptador, no tocar el flujo del cupo.
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
import { APIConnectionTimeoutError, APIError, APIUserAbortError } from "@anthropic-ai/sdk";
import { buildSystemPrompt, CatalogEntry, USER_TEXT } from "./prompt";
import { PDF_PLAN_EXTRACTION_SCHEMA } from "./extraction";

/**
 * Los modelos que se pueden elegir desde `app_config/pdf_import.model`. El
 * prefijo decide el adaptador (`modelRouter`): `gemini-*` va a Gemini y
 * `claude-*` a Claude, los dos en Vertex. El default es Gemini porque Claude
 * no tiene cuota en treino-dev (ver gemini-provider.ts); los de Claude quedan
 * para cambiar de modelo sin redeploy el dia que la tenga.
 */
export const SUPPORTED_MODELS = [
  "gemini-4-argon",
  "claude-opus-5-5",
  "claude-sonnet-5-5",
  "claude-haiku-5-5",
] as const;
export type SupportedModel = (typeof SUPPORTED_MODELS)[number];
export const DEFAULT_MODEL: SupportedModel = "gemini-4-argon";

export const SUPPORTED_EFFORTS = ["low", "medium", "high"] as const;
export type Effort = (typeof SUPPORTED_EFFORTS)[number];
export const DEFAULT_EFFORT: Effort = "medium";

export interface ExtractRequest {
  pdfBase64: string;
  catalog: readonly CatalogEntry[];
  model: SupportedModel;
  effort: Effort;
}

/** Tokens de la llamada, para el log: con esto se mide el costo por import. */
export interface ExtractUsage {
  inputTokens: number;
  outputTokens: number;
  /** Razonamiento facturado aparte de la salida (Gemini); 0 si no lo reporta. */
  thinkingTokens: number;
}

export interface ExtractResult {
  raw: unknown;
  /** El modelo que respondio, segun el proveedor. */
  model: string;
  usage?: ExtractUsage;
}

export type ExtractorErrorKind =
  | "timeout"
  | "refusal"
  | "truncated"
  | "bad_output"
  | "feature_disabled"
  | "provider";

export class ExtractorError extends Error {
  /**
   * `status`: el HTTP del proveedor cuando lo hubo. Viaja aparte del mensaje
   * para que el log lo tenga como campo propio: 429 es cuota, 403 permiso,
   * 404 un modelo que no existe en la region, y se filtra sin parsear texto.
   */
  constructor(
    public readonly kind: ExtractorErrorKind,
    message: string,
    public readonly status?: number,
  ) {
    super(message);
    this.name = "ExtractorError";
  }
}

/**
 * Clasifica un error del SDK en el `kind` que entiende el callable.
 *
 * `feature_disabled`: en Vertex AI los structured outputs (`output_config.format`
 * y strict tool use) estan DENEGADOS POR DEFECTO para todo proyecto dentro de
 * una organizacion, por la org policy `constraints/vertexai.allowedPartnerModelFeatures`
 * (docs de Google Cloud, «Control access to Model Garden models» y «Structured
 * outputs with Anthropic Claude models», actualizadas al 2026-10-21). treino-dev
 * esta en una organizacion. Sin ese permiso cada import se rechaza antes de la
 * inferencia; el callable lo convierte en un `failed-precondition` con motivo,
 * en vez de un `internal` mudo.
 *
 * Google no documenta el texto exacto del rechazo, asi que se reconoce por lo
 * que tiene que nombrar: la feature o la policy. Un 400/403 que no las nombra
 * sigue siendo `provider` (y el log lleva status y mensaje para diagnosticarlo).
 */
export function classifyProviderError(e: unknown): ExtractorError {
  if (
    e instanceof APIConnectionTimeoutError ||
    e instanceof APIUserAbortError ||
    (e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError"))
  ) {
    return new ExtractorError("timeout", "LLM call timed out.");
  }
  const message = e instanceof Error ? e.message : String(e);
  if (
    e instanceof APIError &&
    (e.status === 400 || e.status === 403) &&
    /structured[_ ]?outputs?|allowedPartnerModelFeatures|organization policy|org policy/i.test(message)
  ) {
    return new ExtractorError("feature_disabled", `${e.status}: ${message}`, e.status);
  }
  const status = e instanceof APIError ? e.status : undefined;
  const prefix = status != null ? `${status}: ` : "";
  return new ExtractorError("provider", `${prefix}${message}`, status);
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
        throw classifyProviderError(e);
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
      let raw: unknown;
      try {
        raw = JSON.parse(text);
      } catch {
        throw new ExtractorError("bad_output", "Output is not valid JSON.");
      }
      const u = message.usage;
      return {
        raw,
        model: message.model,
        usage: {
          inputTokens: u.input_tokens + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0),
          outputTokens: u.output_tokens,
          thinkingTokens: 0,
        },
      };
    },
  };
}

/**
 * Elige el adaptador por el prefijo del modelo. Un modelo sin adaptador no
 * llega aca (`readConfig` solo deja pasar `SUPPORTED_MODELS`), pero si llegara
 * es un error nuestro, no del PF.
 */
export function modelRouter(adapters: { gemini: PlanExtractor; claude: PlanExtractor }): PlanExtractor {
  return {
    extract(req) {
      if (req.model.startsWith("gemini-")) return adapters.gemini.extract(req);
      if (req.model.startsWith("claude-")) return adapters.claude.extract(req);
      return Promise.reject(new ExtractorError("provider", `No adapter for model ${req.model}.`));
    },
  };
}
