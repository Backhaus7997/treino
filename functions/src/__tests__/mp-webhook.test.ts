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
  varianteDeFirma,
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
  const bajas: string[] = [];
  return {
    consultados,
    bajas,
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
      // La baja de la suscripcion vieja al cambiar de plan. El webhook no la
      // pide por su cuenta, pero llama a `reconcileSubscription`, que si: un
      // aviso de MP sobre el plan NUEVO ya confirmado cierra el cobro doble en
      // el acto, sin esperar al barrido de las 03:00. Se anota en vez de tirar
      // para que se pueda afirmar cuando NO se cancela nada.
      cancelPreapproval: async (preapprovalId: string) => {
        bajas.push(preapprovalId);
        return { id: preapprovalId, status: "cancelled" };
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

// ---------------------------------------------------------------------------
// VECTORES DORADOS — lo unico de este archivo que NO es auto-consistente.
//
// El resto de los tests de firma calculan el HMAC esperado con el MISMO
// algoritmo que el codigo bajo prueba (el helper `firmar` de mas abajo). Eso
// verifica que TREINO esta de acuerdo con TREINO: si nuestro manifest usara
// coma en vez de punto y coma, o le faltara el `;` final, o tuviera los
// componentes en otro orden, TODOS esos tests seguirian en verde.
//
// Estas constantes cierran ese agujero. Son hashes LITERALES, escritos a mano,
// derivados de los insumos que comparten los SDKs oficiales de Mercado Pago
// (`secret`, `request-id` y `ts` de los fixtures de `mercadopago/sdk-nodejs`).
// Si el template estuviera mal armado en CUALQUIER detalle —separador, cierre,
// orden, remocion de ausentes, hex vs base64, o el clasico de invertir clave y
// mensaje— ninguno de estos validaria.
//
// HONESTIDAD SOBRE QUE PRUEBAN: que TREINO calcula IDENTICO a la implementacion
// canonica de MP. **NO** prueban que sea lo que el servidor de MP firma —
// MP no publica ningun vector oficial. Eso solo lo confirma una notificacion
// real.
// ---------------------------------------------------------------------------

const ORO = {
  secret: "your_secret_key_here",
  requestId: "2066ca19-c6f1-498a-be75-1923005edd06",
  ts: "1742505638683",
  idMinusculas: "ord01jq4s4ky8hwq6na5pxb65b3d3",
  idMayusculas: "ORD01JQ4S4KY8HWQ6NA5PXB65B3D3",
};

/** `id:<min>;request-id:<rid>;ts:<ts>;` — el caso completo. */
const ORO_COMPLETO =
  "633f91233312dd391ec75fa0bea539cfc2d6c4918873305b84a96cc1c58db71c";
/** El MISMO manifest pero con el id en MAYUSCULAS, sin normalizar. */
const ORO_MAYUSCULAS =
  "fb15ae6472eb449173c556793205d77787d58f384d183bb5bc3b724c27bd103c";
/** `request-id:<rid>;ts:<ts>;` — sin data.id, componente removido. */
const ORO_SIN_DATA_ID =
  "8a7b0cc777a8217c3bab41a50c95dc92debbc6f8448f1c967dfe10ac1cb8b894";
/** `id:<min>;ts:<ts>;` — sin request-id, componente removido. */
const ORO_SIN_REQUEST_ID =
  "a20c44820ab71562e89a7c9f64d5636efc8beba587b16c2f9bbbc3504892741a";

const conFirma = (v1: string) => `ts=${ORO.ts},v1=${v1}`;

describe("firmaValida — vectores dorados, calculados AFUERA de esta implementacion", () => {
  it("el manifest completo valida contra el hash literal", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
    })).toBe(true);
  });

  it("sin data.id: el componente se REMUEVE, no queda vacio", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_SIN_DATA_ID),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: undefined,
    })).toBe(true);
  });

  it("sin request-id: idem", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_SIN_REQUEST_ID),
      xRequestId: undefined,
      dataIdDeLaUrl: ORO.idMinusculas,
    })).toBe(true);
  });

  // ── La divergencia doc-vs-SDK, fijada en los dos sentidos ──
  //
  // La doc de MP manda bajar el id a minusculas; el SDK oficial de Node NO lo
  // hace y tiene un test que lo pinea. Como las dos fuentes son de MP y dicen
  // lo opuesto, `firmaValida` acepta LAS DOS derivaciones. Estos dos tests son
  // los que impiden que alguien "simplifique" eligiendo una: cada uno usa un
  // hash literal distinto, y sacar cualquiera de las dos ramas tira uno.

  it("un id en MAYUSCULAS firmado TAL CUAL valida — es lo que hace el SDK", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_MAYUSCULAS),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMayusculas,
    })).toBe(true);
  });

  it("el MISMO id en mayusculas firmado en MINUSCULAS tambien — es lo que dice la doc", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMayusculas,
    })).toBe(true);
  });

  it("aceptar las dos NO es aceptar cualquiera: otro id sigue sin validar", () => {
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: "otro-id-cualquiera",
    })).toBe(false);
  });

  it("un ts distinto no valida — el ts entra al manifest tal cual", () => {
    // La doc dice que el ts viene «en milisegundos» y su propio ejemplo son
    // segundos; el SDK arreglo ese bug declarando que son SEGUNDOS. Para el
    // HMAC da igual, porque entra como string literal — este test lo fija.
    expect(firmaValida({
      signingSecret: ORO.secret,
      xSignature: `ts=1742505638,v1=${ORO_COMPLETO}`,
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
    })).toBe(false);
  });

  it("otro secreto no valida", () => {
    expect(firmaValida({
      signingSecret: "otro_secreto",
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
    })).toBe(false);
  });
});

describe("varianteDeFirma — de donde sale el id, que la doc no desambigua", () => {
  // Todos usan los MISMOS hashes dorados de arriba: lo unico que cambia es por
  // que campo entra el id. Si el manifest se armara distinto, ninguno pasaria.

  it("dice `data.id-url` cuando MP manda `?data.id=`", () => {
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
    })).toBe("data.id-url");
  });

  it("dice `id-url` cuando MP manda `?id=` — la lectura que nos faltaba", () => {
    // Este es EL caso del 401 real: el simulador manda dos ids y elegimos el
    // que no era.
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: undefined,
      idDeLaUrl: ORO.idMinusculas,
    })).toBe("id-url");
  });

  it("dice `data.id-body` si MP firmo con el del body", () => {
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: undefined,
      dataIdDelBody: ORO.idMinusculas,
    })).toBe("data.id-body");
  });

  it("dice `sin-id` cuando el manifest no lleva id", () => {
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_SIN_DATA_ID),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: undefined,
    })).toBe("sin-id");
  });

  it("con `data.id` y `id` a la vez, gana el de la doc y lo dice", () => {
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
      idDeLaUrl: "123456",
    })).toBe("data.id-url");
  });

  it("pero si MP firmo con el OTRO, tambien lo encuentra", () => {
    // El escenario exacto del simulador: `data.id` es el recurso, `id` es el
    // id de la notificacion, y no sabemos con cual firma.
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: "otro-id-distinto",
      idDeLaUrl: ORO.idMinusculas,
    })).toBe("id-url");
  });

  it("probar varias lecturas NO es aceptar cualquier firma", () => {
    // La garantia que no se puede perder: ninguna combinacion de ids valida una
    // firma que no salio de nuestro secreto.
    expect(varianteDeFirma({
      signingSecret: ORO.secret,
      xSignature: `ts=${ORO.ts},v1=${"0".repeat(64)}`,
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
      idDeLaUrl: ORO.idMinusculas,
      dataIdDelBody: ORO.idMinusculas,
    })).toBeNull();
  });

  it("y con otro secreto tampoco valida ninguna variante", () => {
    expect(varianteDeFirma({
      signingSecret: "otro_secreto",
      xSignature: conFirma(ORO_COMPLETO),
      xRequestId: ORO.requestId,
      dataIdDeLaUrl: ORO.idMinusculas,
      idDeLaUrl: ORO.idMinusculas,
      dataIdDelBody: ORO.idMinusculas,
    })).toBeNull();
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

  it("con el flag de diagnostico PRENDIDO si logea los valores crudos", async () => {
    // La contracara del test de abajo: la politica se puede levantar, pero
    // SOLO a proposito y por un rato. Si esto queda prendido en produccion,
    // Cloud Logging se llena de lo que mande cualquiera de internet.
    const { app } = fakeApp(MUNDO());

    await runMpWebhook(
      app,
      req({
        query: { "data.id": SUB_ID },
        headers: { "x-signature": "ts=1,v1=" + "0".repeat(64) },
      }),
      { ...deps(fakeMp(AUTORIZADA), { signingSecret: SECRETO }), diagnostico: true },
    );

    const logeado = JSON.stringify(warnSpy.mock.calls);
    expect(logeado).toContain("firmaRecibida");
    expect(logeado).toContain(SUB_ID);
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
