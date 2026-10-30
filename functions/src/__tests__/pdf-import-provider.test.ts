/**
 * `classifyProviderError`: como se traducen los errores del SDK de Anthropic
 * (Vertex) a lo que entiende `parsePlanPdf`. Sin red: se construyen los
 * errores del SDK a mano.
 */
import { APIConnectionTimeoutError, APIError, APIUserAbortError } from "@anthropic-ai/sdk";
import { classifyProviderError } from "../pdf-import/provider";

const apiError = (status: number, message: string) =>
  new APIError(status, { error: { message } }, message, new Headers());

describe("classifyProviderError", () => {
  it.each([
    [400, "structured_outputs is not allowed by organization policy constraints/vertexai.allowedPartnerModelFeatures"],
    [400, "Structured outputs are disabled for this project"],
    [403, "Request violates organization policy for partner model features"],
    [400, "Feature blocked by constraints/vertexai.allowedPartnerModelFeatures"],
  ])("%i que nombra la feature o la policy → feature_disabled", (status, message) => {
    const e = classifyProviderError(apiError(status, message));
    expect(e.kind).toBe("feature_disabled");
    expect(e.status).toBe(status);
  });

  it.each([
    [400, "messages.0.content.0: invalid document"], // un 400 cualquiera no es la policy
    [500, "structured outputs backend unavailable"], // un 5xx nunca es la policy
    [429, "rate limited"],
    [403, "Permission denied on resource project treino-dev"], // falta el rol, no la policy
    [404, "Publisher Model `claude-opus-5-5` was not found"], // modelo inexistente en la region
  ])("%i que no es la policy → provider, con el status en el mensaje y como campo", (status, message) => {
    const e = classifyProviderError(apiError(status, message));
    expect(e.kind).toBe("provider");
    expect(e.message).toContain(`${status}`);
    expect(e.message).toContain(message);
    expect(e.status).toBe(status);
  });

  it("timeouts y abortos → timeout", () => {
    expect(classifyProviderError(new APIConnectionTimeoutError()).kind).toBe("timeout");
    expect(classifyProviderError(new APIUserAbortError()).kind).toBe("timeout");
    const abort = new Error("The operation was aborted due to timeout");
    abort.name = "TimeoutError";
    expect(classifyProviderError(abort).kind).toBe("timeout");
  });

  it("un error que no es del SDK → provider, sin status", () => {
    expect(classifyProviderError(new Error("boom"))).toMatchObject({ kind: "provider", status: undefined });
    expect(classifyProviderError("texto")).toMatchObject({ kind: "provider", status: undefined });
  });
});
