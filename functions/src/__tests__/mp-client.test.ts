/**
 * mp-client.test.ts — el cliente HTTP de Mercado Pago.
 * LOCAL, sin emulador y SIN RED: el `fetch` entra por parametro.
 */

import {
  MpApiError,
  createMpClient,
} from "../subscriptions/mp/client";

/** Un `fetch` de mentira que devuelve lo que le digas y anota como lo llamaron. */
function fakeFetch(
  respuesta: { status: number; body?: unknown; texto?: string } | Error,
): { fn: typeof fetch; llamadas: { url: string; init?: RequestInit }[] } {
  const llamadas: { url: string; init?: RequestInit }[] = [];
  const fn = (async (url: string, init?: RequestInit) => {
    llamadas.push({ url, init });
    if (respuesta instanceof Error) throw respuesta;
    return {
      ok: respuesta.status >= 200 && respuesta.status < 300,
      status: respuesta.status,
      json: async () => respuesta.body,
      text: async () => respuesta.texto ?? "",
    };
  }) as unknown as typeof fetch;
  return { fn, llamadas };
}

/**
 * Corre la llamada y devuelve el `MpApiError` que tiro. Existe porque
 * `promesa.catch(e => e as MpApiError)` da la UNION con el tipo resuelto, y
 * ahi `retryable` no existe para TypeScript.
 */
async function errorDe(fn: () => Promise<unknown>): Promise<MpApiError> {
  try {
    await fn();
  } catch (e) {
    return e as MpApiError;
  }
  throw new Error("se esperaba un MpApiError y la llamada resolvio bien");
}

describe("createMpClient — el camino feliz", () => {
  it("pega al endpoint correcto con el token en el header", async () => {
    const { fn, llamadas } = fakeFetch({
      status: 200,
      body: { id: "2c93", status: "authorized" },
    });

    await createMpClient("TEST-token-123", fn).getPreapproval("2c93");

    expect(llamadas).toHaveLength(1);
    expect(llamadas[0].url).toBe("https://api.mercadopago.com/preapproval/2c93");
    expect(llamadas[0].init?.method).toBe("GET");
    expect(
      (llamadas[0].init?.headers as Record<string, string>).Authorization,
    ).toBe("Bearer TEST-token-123");
  });

  it("devuelve el JSON tal cual, sin interpretarlo", async () => {
    // El cliente NO traduce estados: eso es de `map-status.ts`. Si algun dia
    // este test empieza a esperar un estado ya mapeado, alguien mezcló dos
    // capas que estan separadas a proposito.
    const { fn } = fakeFetch({
      status: 200,
      body: { status: "authorized", external_reference: "uid-42" },
    });

    const r = await createMpClient("t", fn).getPreapproval("x");

    expect(r.status).toBe("authorized");
    expect(r.external_reference).toBe("uid-42");
  });

  it("escapa el id en la URL", async () => {
    // Un id con `/` o `?` sin escapar cambia la ruta del request.
    const { fn, llamadas } = fakeFetch({ status: 200, body: {} });

    await createMpClient("t", fn).getPreapproval("a/b?c=1");

    expect(llamadas[0].url).toBe(
      "https://api.mercadopago.com/preapproval/a%2Fb%3Fc%3D1",
    );
  });

  it("manda un AbortSignal: una llamada colgada se lleva la function entera", async () => {
    const { fn, llamadas } = fakeFetch({ status: 200, body: {} });

    await createMpClient("t", fn).getPreapproval("x");

    expect(llamadas[0].init?.signal).toBeDefined();
  });
});

describe("createMpClient — los errores, y cuáles conviene reintentar", () => {
  it("un token vacío falla al construir, no en la primera llamada", () => {
    // El síntoma útil es "no arranca", no "todo devuelve 401 y nadie sabe por
    // qué". Un token vacío en producción es un secreto mal cargado.
    expect(() => createMpClient("")).toThrow(/MP_ACCESS_TOKEN/);
  });

  it("un id vacío no sale a la red", async () => {
    const { fn, llamadas } = fakeFetch({ status: 200, body: {} });

    await expect(
      createMpClient("t", fn).getPreapproval(""),
    ).rejects.toThrow(MpApiError);
    expect(llamadas).toHaveLength(0);
  });

  it("un fallo de red da status 0 y ES reintentable", async () => {
    const { fn } = fakeFetch(new Error("ECONNRESET"));

    const err = await errorDe(() => createMpClient("t", fn).getPreapproval("x"));

    expect(err).toBeInstanceOf(MpApiError);
    expect(err.status).toBe(0);
    expect(err.retryable).toBe(true);
  });

  // La tabla es la parte que importa: reintentar lo que no se arregla solo es
  // ruido, y no reintentar lo que sí se arregla es perder un cobro.
  const casos: [number, boolean, string][] = [
    [401, false, "token vencido o mal cargado — reintentar no lo arregla"],
    [403, false, "sin permisos — idem"],
    [404, false, "el preapproval no existe — sería ruido para siempre"],
    [429, true, "rate limit — se arregla esperando"],
    [500, true, "MP se cayó"],
    [503, true, "MP no disponible"],
  ];

  for (const [status, retryable, porque] of casos) {
    it(`HTTP ${status} → retryable=${retryable} (${porque})`, async () => {
      const { fn } = fakeFetch({ status, texto: "detalle de MP" });

      const err = await errorDe(() => createMpClient("t", fn).getPreapproval("x"));

      expect(err).toBeInstanceOf(MpApiError);
      expect(err.status).toBe(status);
      expect(err.retryable).toBe(retryable);
    });
  }

  it("el body del error viaja recortado — esto va a Cloud Logging", async () => {
    const { fn } = fakeFetch({ status: 500, texto: "x".repeat(2000) });

    const err = await errorDe(() => createMpClient("t", fn).getPreapproval("x"));

    expect(err.body).toHaveLength(500);
  });

  it("una respuesta 200 que no es JSON falla en vez de devolver basura", async () => {
    // Un 200 con HTML —una página de error de un proxy, por ejemplo— no puede
    // terminar escribiéndose como si fuera una suscripción.
    const { fn } = fakeFetch({ status: 200, body: null });

    await expect(
      createMpClient("t", fn).getPreapproval("x"),
    ).rejects.toThrow(/no es un objeto JSON/);
  });
});
