/**
 * mp-webhook.test.ts — el PRIMER endpoint HTTP publico del repo.
 * LOCAL, sin emulador y SIN RED: el cliente de MP entra por parametro.
 *
 * Lo que estos tests cuidan son cuatro cosas, y ninguna es "que ande":
 *   1. Que del body entrante NO salga ningun dato que decida plata. Lo unico
 *      que se usa es el id; el estado se le pregunta a MP.
 *   2. Que el manifest de la firma use el `data.id` de la QUERY STRING y no el
 *      del body. Confundirlos da firmas que no matchean nunca, y el sintoma
 *      parece un problema de MP.
 *   3. Que solo el fallo TRANSITORIO pida reintento. MP reintenta cada 15
 *      minutos para siempre hasta recibir 200: un 5xx por un error de negocio
 *      es un martilleo eterno.
 *   4. Que un `error-mp` NO marque el evento como procesado — si lo marcara, el
 *      dedupe se comeria el reintento y el PF que pago no cobraria nunca.
 */

const warnSpy = jest.fn();
const errorSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...a: unknown[]) => warnSpy(...a),
    error: (...a: unknown[]) => errorSpy(...a),
    info: jest.fn(),
  },
}));
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "TEST-token" }),
}));
jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: (_opts: unknown, handler: unknown) => handler,
}));
jest.mock("firebase-functions/v2/https", () => ({
  onRequest: (_opts: unknown, handler: unknown) => handler,
}));

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
    Timestamp: { fromMillis: (ms: number) => ({ toMillis: () => ms }) },
  }),
  app: jest.fn(),
  initializeApp: jest.fn(),
}));

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeApp());

import { createHmac } from "node:crypto";

import {
  DEDUPE_MS,
  WebhookRequestLike,
  firmaValida,
  idDelEvento,
  runMpWebhook,
  topicoDelEvento,
} from "../subscriptions/mp/webhook";
import { MpApiError, MpPreapproval } from "../subscriptions/mp/client";

// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

function fakeApp(seed: Store = {}) {
  const store: Store = seed;
  const escrituras: { col: string; id: string; data: unknown }[] = [];

  const docRef = (col: string, id: string) => ({
    id,
    get: async () => ({
      exists: store[col]?.[id] !== undefined,
      data: () => store[col]?.[id],
    }),
    set: async (data: Record<string, unknown>, opts?: { merge?: boolean }) => {
      store[col] = store[col] ?? {};
      store[col][id] = opts?.merge
        ? { ...(store[col][id] ?? {}), ...data }
        : data;
      escrituras.push({ col, id, data });
    },
  });

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => docRef(col, id),
        get: async () => ({
          docs: Object.keys(store[col] ?? {}).map((id) => ({
            id,
            data: () => store[col][id],
          })),
        }),
      }),
    }),
  };

  return { app: app as never, store, escrituras };
}

const AHORA = Date.parse("2026-09-08T12:00:00.000Z");
const SUB_ID = "2c938084726fca480172750000000000";
const PLAN_ID = "p1";

/** El mundo normal: el mapeo del plan escrito y el PF sin suscripcion aun. */
const MUNDO = (): Store => ({
  users: { t1: { role: "trainer" } },
  mp_plans: { p1: { uid: "t1", tier: "plan2", cycle: "monthly" } },
});

const AUTORIZADA: MpPreapproval = {
  id: SUB_ID,
  status: "authorized",
  external_reference: "t1",
  preapproval_plan_id: PLAN_ID,
  next_payment_date: "2026-10-08T12:00:00.000Z",
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
};

function fakeMp(respuesta: MpPreapproval | Error) {
  const consultados: string[] = [];
  return {
    consultados,
    mpClient: {
      getPreapproval: async (id: string) => {
        consultados.push(id);
        if (respuesta instanceof Error) throw respuesta;
        return respuesta;
      },
      createPreapprovalPlan: async () => ({}),
      searchPreapprovalsByPlan: async () => {
        if (respuesta instanceof Error) throw respuesta;
        return [respuesta];
      },
    },
  };
}

/** Un request de mentira con la superficie que el handler usa. */
function req(over: {
  body?: unknown;
  query?: unknown;
  headers?: Record<string, string>;
} = {}): WebhookRequestLike {
  const headers = over.headers ?? {};
  return {
    body: over.body ?? { type: "subscription_preapproval", data: { id: SUB_ID } },
    query: over.query ?? {},
    header: (n: string) => headers[n.toLowerCase()],
  };
}

const deps = (mp: ReturnType<typeof fakeMp>, over: Partial<{
  nowMs: number;
  signingSecret: string;
}> = {}) => ({
  mpClient: mp.mpClient,
  nowMs: over.nowMs ?? AHORA,
  signingSecret: over.signingSecret ?? "",
});

beforeEach(() => jest.clearAllMocks());

// ---------------------------------------------------------------------------

describe("runMpWebhook — el camino que acredita el pago", () => {
  it("un alta reconcilia y escribe la suscripcion del PF", async () => {
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    const r = await runMpWebhook(app, req(), deps(mp));

    expect(r).toBe("reconciliado");
    expect(mp.consultados).toEqual([SUB_ID]);
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(sub.status).toBe("active");
  });

  it("el plan sale del preapproval de MP, NUNCA del body entrante", async () => {
    // El corazon del diseño: aunque el body diga otro plan y otro estado, lo
    // unico que se usa es el id. Si esto se rompe, cualquiera se firma un plan3.
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    await runMpWebhook(
      app,
      req({
        body: {
          type: "subscription_preapproval",
          data: { id: SUB_ID },
          // Basura hostil, toda ignorada.
          status: "authorized",
          preapproval_plan_id: "plan-del-atacante",
          tier: "plan3",
          external_reference: "otro-pf",
        },
      }),
      deps(mp),
    );

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(store.users["otro-pf"]).toBeUndefined();
  });

  it("una suscripcion SIN plan asociado no es nuestra: se acusa y se marca", async () => {
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp({ ...AUTORIZADA, preapproval_plan_id: undefined });

    const r = await runMpWebhook(app, req(), deps(mp));

    expect(r).toBe("sin-plan");
    expect(store.users.t1.subscription).toBeUndefined();
    // Se marca procesado: reintentar no le va a poner un plan.
    expect(store.mp_webhook_events[SUB_ID].procesadoMs).toBe(AHORA);
  });
});

describe("runMpWebhook — solo lo transitorio pide reintento", () => {
  it("si MP no contesta devuelve error-mp", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp(new MpApiError("MP caido", 503));

    expect(await runMpWebhook(app, req(), deps(mp))).toBe("error-mp");
  });

  it("y NO marca el evento como procesado — si no, el dedupe come el reintento", async () => {
    // Es el bug mas caro posible de este archivo: MP reintenta a los 15
    // minutos, el dedupe lo descarta, y el PF que pago no cobra nunca.
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp(new MpApiError("MP caido", 503));

    await runMpWebhook(app, req(), deps(mp));

    expect(store.mp_webhook_events?.[SUB_ID]).toBeUndefined();
  });

  it("el reintento posterior SI procesa", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runMpWebhook(app, req(), deps(fakeMp(new MpApiError("caido", 503))));
    const r = await runMpWebhook(app, req(), deps(fakeMp(AUTORIZADA)));

    expect(r).toBe("reconciliado");
    expect((store.users.t1.subscription as Record<string, unknown>).status)
      .toBe("active");
  });
});

describe("runMpWebhook — lo que se acusa sin trabajar", () => {
  it("un topico que no atendemos NO llama a MP", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    const r = await runMpWebhook(
      app,
      req({ body: { type: "payment", data: { id: "999" } } }),
      deps(mp),
    );

    expect(r).toBe("topico-ignorado");
    expect(mp.consultados).toHaveLength(0);
  });

  it("`subscription_preapproval_plan` tampoco: avisa del PLAN, no de la venta", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    const r = await runMpWebhook(
      app,
      req({ body: { type: "subscription_preapproval_plan", data: { id: PLAN_ID } } }),
      deps(mp),
    );

    expect(r).toBe("topico-ignorado");
    expect(mp.consultados).toHaveLength(0);
  });

  it("un evento sin id utilizable no llama a MP", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    const r = await runMpWebhook(
      app,
      req({ body: { type: "subscription_preapproval", data: {} } }),
      deps(mp),
    );

    expect(r).toBe("sin-id");
    expect(mp.consultados).toHaveLength(0);
  });
});

describe("runMpWebhook — el dedupe", () => {
  it("el mismo evento repetido no vuelve a consultar a MP", async () => {
    const { app } = fakeApp(MUNDO());

    await runMpWebhook(app, req(), deps(fakeMp(AUTORIZADA)));
    const segundo = fakeMp(AUTORIZADA);
    const r = await runMpWebhook(app, req(), deps(segundo));

    expect(r).toBe("duplicado");
    expect(segundo.consultados).toHaveLength(0);
  });

  it("pasada la ventana vuelve a procesar", async () => {
    // La ventana es MENOR que los 15 minutos de reintento de MP a proposito: si
    // fuera mayor, un evento que de verdad se perdio no se reintentaria nunca.
    const { app } = fakeApp(MUNDO());

    await runMpWebhook(app, req(), deps(fakeMp(AUTORIZADA)));
    const despues = fakeMp(AUTORIZADA);
    const r = await runMpWebhook(
      app,
      req(),
      deps(despues, { nowMs: AHORA + DEDUPE_MS + 1 }),
    );

    expect(r).toBe("reconciliado");
    expect(despues.consultados).toEqual([SUB_ID]);
  });

  it("la ventana de dedupe es menor que los 15 minutos de reintento de MP", () => {
    expect(DEDUPE_MS).toBeLessThan(15 * 60 * 1000);
  });
});

// ---------------------------------------------------------------------------
// LA FIRMA. El manifest tiene tres trampas y las tres producen firmas que no
// matchean nunca, con un sintoma que parece un problema de Mercado Pago.
// ---------------------------------------------------------------------------

const SECRETO = "clave-de-prueba";

/** El manifest tal cual lo define la doc, para calcular la firma esperada. */
function firmar(partes: string, ts: string): string {
  const v1 = createHmac("sha256", SECRETO).update(partes).digest("hex");
  return `ts=${ts},v1=${v1}`;
}

describe("el modo degradado GRITA", () => {
  it("sin clave de firma, cada request logea un warn", async () => {
    // Un modo degradado silencioso es el que se queda para siempre. En
    // produccion la app TREINO SI tiene clave (verificado en el panel el
    // 2026-09-08), asi que este warn tambien sirve de alarma: si aparece, o el
    // secreto se borro o el deploy salio sin el.
    const { app } = fakeApp(MUNDO());

    await runMpWebhook(app, req(), deps(fakeMp(AUTORIZADA), { signingSecret: "" }));

    const dicho = JSON.stringify(warnSpy.mock.calls);
    expect(dicho).toContain("SIN clave de firma");
    expect(dicho).toContain("MP_WEBHOOK_SECRET");
  });

  it("CON clave, no ensucia los logs", async () => {
    const { app } = fakeApp(MUNDO());
    const manifest = `id:${SUB_ID};ts:1704908010;`;

    await runMpWebhook(
      app,
      req({
        query: { "data.id": SUB_ID },
        headers: { "x-signature": firmar(manifest, "1704908010") },
      }),
      deps(fakeMp(AUTORIZADA), { signingSecret: SECRETO }),
    );

    expect(JSON.stringify(warnSpy.mock.calls)).not.toContain("SIN clave");
  });
});

describe("firmaValida", () => {
  it("sin secreto configurado deja pasar: no hay nada que validar", () => {
    // MP puede no dar clave para aplicaciones de Suscripciones. Lo que sostiene
    // la seguridad es no confiar en el body, no la firma.
    expect(firmaValida({
      signingSecret: "",
      xSignature: undefined,
      xRequestId: undefined,
      dataIdDeLaUrl: undefined,
    })).toBe(true);
  });

  it("con secreto y firma correcta, pasa", () => {
    const manifest = `id:${SUB_ID};request-id:rq-1;ts:1704908010;`;
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: firmar(manifest, "1704908010"),
      xRequestId: "rq-1",
      dataIdDeLaUrl: SUB_ID,
    })).toBe(true);
  });

  it("con secreto y firma incorrecta, NO pasa", () => {
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: "ts=1704908010,v1=" + "0".repeat(64),
      xRequestId: "rq-1",
      dataIdDeLaUrl: SUB_ID,
    })).toBe(false);
  });

  it("con secreto y SIN header, no pasa", () => {
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: undefined,
      xRequestId: "rq-1",
      dataIdDeLaUrl: SUB_ID,
    })).toBe(false);
  });

  it("TRAMPA 1 — los componentes ausentes se REMUEVEN del manifest", () => {
    // Sin x-request-id el template es `id:...;ts:...;`, no
    // `id:...;request-id:;ts:...;`. Dejar la clave vacia cambia el HMAC.
    const manifest = `id:${SUB_ID};ts:1704908010;`;
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: firmar(manifest, "1704908010"),
      xRequestId: undefined,
      dataIdDeLaUrl: SUB_ID,
    })).toBe(true);
  });

  it("TRAMPA 2 — un id alfanumerico en MAYUSCULAS va en minusculas", () => {
    const enMayusculas = "ORD01JQ4S4KY8HWQ6NA5PXB65B3D3";
    const manifest = `id:${enMayusculas.toLowerCase()};ts:1704908010;`;
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: firmar(manifest, "1704908010"),
      xRequestId: undefined,
      dataIdDeLaUrl: enMayusculas,
    })).toBe(true);
  });

  it("tolera espacios y orden invertido en el header", () => {
    const manifest = `id:${SUB_ID};ts:1704908010;`;
    const v1 = createHmac("sha256", SECRETO).update(manifest).digest("hex");
    expect(firmaValida({
      signingSecret: SECRETO,
      xSignature: `v1=${v1}, ts=1704908010`,
      xRequestId: undefined,
      dataIdDeLaUrl: SUB_ID,
    })).toBe(true);
  });

  it("un header sin ts o sin v1 no pasa", () => {
    for (const h of ["ts=1704908010", "v1=abc", "cualquiera", ""]) {
      expect(firmaValida({
        signingSecret: SECRETO,
        xSignature: h,
        xRequestId: undefined,
        dataIdDeLaUrl: SUB_ID,
      })).toBe(false);
    }
  });
});

describe("runMpWebhook — TRAMPA 3: el manifest usa el data.id de la QUERY", () => {
  it("firma armada con el id de la QUERY: pasa, aunque el body traiga otro", async () => {
    // La doc es explicita: «[data.id_url] se sustituira por el valor del
    // parametro data.id recibido en los query params». Leerlo del body da
    // firmas que no matchean nunca.
    const { app } = fakeApp(MUNDO());
    const manifest = `id:${SUB_ID};ts:1704908010;`;

    const r = await runMpWebhook(
      app,
      req({
        query: { "data.id": SUB_ID },
        body: { type: "subscription_preapproval", data: { id: SUB_ID } },
        headers: { "x-signature": firmar(manifest, "1704908010") },
      }),
      deps(fakeMp(AUTORIZADA), { signingSecret: SECRETO }),
    );

    expect(r).toBe("reconciliado");
  });

  it("una firma que NO valida corta antes de llamar a MP", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp(AUTORIZADA);

    const r = await runMpWebhook(
      app,
      req({
        query: { "data.id": SUB_ID },
        headers: { "x-signature": "ts=1704908010,v1=" + "0".repeat(64) },
      }),
      deps(mp, { signingSecret: SECRETO }),
    );

    expect(r).toBe("firma-invalida");
    expect(mp.consultados).toHaveLength(0);
  });

  it("no se logea el body ni los headers de un evento rechazado", async () => {
    // Serian datos de cualquiera de internet escritos en Cloud Logging.
    const { app } = fakeApp(MUNDO());

    await runMpWebhook(
      app,
      req({
        query: { "data.id": SUB_ID },
        headers: { "x-signature": "ts=1,v1=" + "0".repeat(64) },
      }),
      deps(fakeMp(AUTORIZADA), { signingSecret: SECRETO }),
    );

    const logeado = JSON.stringify(warnSpy.mock.calls);
    expect(logeado).not.toContain("x-signature");
    expect(logeado).not.toContain(SUB_ID);
  });
});

// ---------------------------------------------------------------------------

describe("idDelEvento", () => {
  it("lo saca del body", () => {
    expect(idDelEvento({ data: { id: SUB_ID } }, {})).toBe(SUB_ID);
  });

  it("o de la query, porque MP no publica ejemplo de body para este topico", () => {
    expect(idDelEvento({}, { "data.id": SUB_ID })).toBe(SUB_ID);
    expect(idDelEvento({}, { id: SUB_ID })).toBe(SUB_ID);
  });

  it("acepta el numerico del ejemplo oficial", () => {
    expect(idDelEvento({ data: { id: 999999999 } }, {})).toBe("999999999");
  });

  it("rechaza cualquier cosa que no tenga forma de id de MP", () => {
    // Sin esto, un POST hostil nos manda a hacer un GET con basura en la URL.
    for (const malo of [
      { data: { id: "../../v1/payments/1" } },
      { data: { id: "a".repeat(65) } },
      { data: { id: "con espacio" } },
      { data: { id: "" } },
      { data: { id: null } },
      { data: { id: { anidado: 1 } } },
      {},
      null,
    ]) {
      expect(idDelEvento(malo, {})).toBeNull();
    }
  });
});

describe("topicoDelEvento", () => {
  it("lo saca del `type` del body o del `topic` de la query", () => {
    expect(topicoDelEvento({ type: "subscription_preapproval" }, {}))
      .toBe("subscription_preapproval");
    expect(topicoDelEvento({}, { topic: "payment" })).toBe("payment");
    expect(topicoDelEvento({}, {})).toBe("");
  });
});
