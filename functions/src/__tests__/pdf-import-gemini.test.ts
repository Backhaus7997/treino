/**
 * `geminiPlanExtractor` y `modelRouter`: que el pedido a Vertex lleve el
 * prompt, el catalogo y el schema de produccion, como se lee cada corte de la
 * respuesta, y cuando se reintenta. Sin red: `fetch` es un doble.
 */
import { PDF_PLAN_EXTRACTION_SCHEMA } from "../pdf-import/extraction";
import {
  buildGeminiRequest,
  GEMINI_RETRY_DELAYS_MS,
  geminiPlanExtractor,
  interpretGeminiResponse,
} from "../pdf-import/gemini-provider";
import { USER_TEXT } from "../pdf-import/prompt";
import { ExtractorError, ExtractRequest, LLM_MAX_TOKENS, modelRouter, PlanExtractor } from "../pdf-import/provider";

const PLAN = { numWeeks: 1, days: [], warnings: [] };

const req: ExtractRequest = {
  pdfBase64: "JVBERi0xLjcK",
  catalog: [{ id: "bench-press-barra", name: "Press banca" }],
  model: "gemini-4-argon",
  effort: "medium",
};

const ok = (text: string, extra: Record<string, unknown> = {}) => ({
  candidates: [{ content: { parts: [{ text }] }, finishReason: "STOP" }],
  usageMetadata: { promptTokenCount: 16692, candidatesTokenCount: 5924, thoughtsTokenCount: 12 },
  modelVersion: "gemini-4-argon",
  ...extra,
});

const response = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const apiError = (status: number, message: string) => response(status, { error: { code: status, message } });

function harness(replies: Response[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const sleeps: number[] = [];
  const extractor = geminiPlanExtractor("treino-dev", {
    getAccessToken: async () => "tok",
    fetchFn: (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      const next = replies.shift();
      if (!next) throw new Error("sin respuesta preparada");
      return next;
    }) as unknown as typeof fetch,
    sleep: async (ms) => {
      sleeps.push(ms);
    },
  });
  return { extractor, calls, sleeps };
}

describe("buildGeminiRequest", () => {
  it("lleva el system prompt con el catalogo, el PDF, el texto fijo y el schema de produccion", () => {
    const body = buildGeminiRequest(req.pdfBase64, req.catalog);
    expect(body.systemInstruction.parts[0].text).toContain("bench-press-barra\tPress banca");
    expect(body.contents[0].parts).toEqual([
      { inlineData: { mimeType: "application/pdf", data: req.pdfBase64 } },
      { text: USER_TEXT },
    ]);
    expect(body.generationConfig).toEqual({
      responseMimeType: "application/json",
      responseJsonSchema: PDF_PLAN_EXTRACTION_SCHEMA,
      maxOutputTokens: LLM_MAX_TOKENS,
    });
  });
});

describe("interpretGeminiResponse", () => {
  it("devuelve el JSON crudo, el modelo que respondio y los tokens", () => {
    expect(interpretGeminiResponse(ok(JSON.stringify(PLAN)), "gemini-4-argon")).toEqual({
      raw: PLAN,
      model: "gemini-4-argon",
      usage: { inputTokens: 16692, outputTokens: 5924, thinkingTokens: 12 },
    });
  });

  it("deja afuera las partes de razonamiento", () => {
    const body = {
      candidates: [{
        content: { parts: [{ text: "pienso que…", thought: true }, { text: JSON.stringify(PLAN) }] },
        finishReason: "STOP",
      }],
    };
    expect(interpretGeminiResponse(body, "gemini-4-argon")).toMatchObject({ raw: PLAN, model: "gemini-4-argon" });
  });

  it.each([
    ["MAX_TOKENS", "truncated"],
    ["SAFETY", "refusal"],
    ["PROHIBITED_CONTENT", "refusal"],
    ["RECITATION", "refusal"],
    ["OTHER", "provider"],
  ])("finishReason %s → %s", (finishReason, kind) => {
    const body = { candidates: [{ content: { parts: [{ text: "{}" }] }, finishReason }] };
    expect(() => interpretGeminiResponse(body, "gemini-4-argon")).toThrow(expect.objectContaining({ kind }));
  });

  it("un prompt bloqueado → refusal", () => {
    expect(() => interpretGeminiResponse({ promptFeedback: { blockReason: "SAFETY" } }, "gemini-4-argon"))
      .toThrow(expect.objectContaining({ kind: "refusal" }));
  });

  it("una salida que no es JSON → bad_output", () => {
    expect(() => interpretGeminiResponse(ok("no es json"), "gemini-4-argon"))
      .toThrow(expect.objectContaining({ kind: "bad_output" }));
  });
});

describe("geminiPlanExtractor", () => {
  it("le pega al modelo pedido en el endpoint global, con el token de la service account", async () => {
    const h = harness([response(200, ok(JSON.stringify(PLAN)))]);
    await expect(h.extractor.extract(req)).resolves.toMatchObject({ raw: PLAN });
    expect(h.calls[0].url).toBe(
      "https://aiplatform.googleapis.com/v1/projects/treino-dev/locations/global/publishers/google/models/" +
        "gemini-4-argon:generateContent",
    );
    expect(h.calls[0].init.headers).toMatchObject({ authorization: "Bearer tok" });
    expect(JSON.parse(h.calls[0].init.body as string)).toEqual(buildGeminiRequest(req.pdfBase64, req.catalog));
  });

  it("ante 429 o 503 reintenta con espera y sigue si despues responde", async () => {
    const h = harness([
      apiError(429, "Resource exhausted"),
      apiError(503, "Unavailable"),
      response(200, ok(JSON.stringify(PLAN))),
    ]);
    await expect(h.extractor.extract(req)).resolves.toMatchObject({ raw: PLAN });
    expect(h.calls).toHaveLength(3);
    expect(h.sleeps).toEqual([...GEMINI_RETRY_DELAYS_MS]);
  });

  it("si la capacidad sigue saturada, corta tras tres intentos con el status", async () => {
    const h = harness([apiError(429, "a"), apiError(429, "b"), apiError(429, "Resource exhausted")]);
    await expect(h.extractor.extract(req)).rejects.toMatchObject({
      kind: "provider",
      status: 429,
      message: "429: Resource exhausted",
    });
    expect(h.calls).toHaveLength(3);
  });

  it.each([400, 403, 404, 500])("%i no se reintenta: → provider con el status", async (status) => {
    const h = harness([apiError(status, "nope")]);
    await expect(h.extractor.extract(req)).rejects.toMatchObject({ kind: "provider", status });
    expect(h.calls).toHaveLength(1);
  });

  it("no espera un reintento que no entra en el tope: es timeout", async () => {
    const extractor = geminiPlanExtractor("treino-dev", {
      getAccessToken: async () => "tok",
      fetchFn: (async () => apiError(429, "busy")) as unknown as typeof fetch,
      sleep: async () => {
        throw new Error("no deberia esperar");
      },
      timeoutMs: 1_000, // menos que la primera espera
    });
    await expect(extractor.extract(req)).rejects.toMatchObject({ kind: "timeout" });
  });

  it("un aborto por tiempo → timeout", async () => {
    const extractor = geminiPlanExtractor("treino-dev", {
      getAccessToken: async () => "tok",
      fetchFn: (async () => {
        const e = new Error("The operation was aborted due to timeout");
        e.name = "TimeoutError";
        throw e;
      }) as unknown as typeof fetch,
    });
    await expect(extractor.extract(req)).rejects.toMatchObject({ kind: "timeout" });
  });
});

describe("modelRouter", () => {
  const tagged = (tag: string): PlanExtractor => ({ extract: async (r) => ({ raw: tag, model: r.model }) });
  const router = modelRouter({ gemini: tagged("gemini"), claude: tagged("claude") });

  it.each([
    ["gemini-4-argon", "gemini"],
    ["claude-opus-5-5", "claude"],
    ["claude-haiku-5-5", "claude"],
  ])("%s va al adaptador %s", async (model, tag) => {
    const res = router.extract({ ...req, model: model as ExtractRequest["model"] });
    await expect(res).resolves.toMatchObject({ raw: tag });
  });

  it("un modelo sin adaptador es error nuestro", async () => {
    await expect(router.extract({ ...req, model: "gpt-5" as ExtractRequest["model"] }))
      .rejects.toBeInstanceOf(ExtractorError);
  });
});
