/**
 * rc-webhook.test.ts — el webhook que le acredita la suscripcion al ALUMNO.
 * LOCAL, sin emulador y SIN RED: el cliente de RevenueCat entra por parametro.
 *
 * Lo que estos tests cuidan son cinco cosas, y ninguna es «que ande»:
 *
 *   1. Que el HMAC se calcule sobre los BYTES CRUDOS del body. Es la trampa que
 *      la propia doc de RevenueCat marca, y la unica forma de probarlo es
 *      firmar un body y despues pasarle al validador el MISMO objeto
 *      re-serializado: si el codigo usara `JSON.stringify`, ese test pasaria.
 *      Tiene que fallar.
 *
 *   2. Que un fallo TRANSITORIO pida reintento y NO marque el dedupe. Aca es al
 *      reves que en Mercado Pago: RevenueCat reintenta 5 veces y abandona, asi
 *      que los reintentos son un recurso escaso. Si un `error-rc` marcara el
 *      evento como procesado, el reintento entraria por el dedupe y el alumno
 *      que pago no cobraria nunca.
 *
 *   3. Que el mapa escrito tenga EXACTAMENTE una clave. No es cosmetica:
 *      `athletePaywallInputChanged` compara el mapa entero serializado, asi que
 *      cualquier campo volatil adentro hace correr el trigger en cada evento.
 *      Este test es el que impide que alguien «agregue un updatedAt, total es
 *      un campito».
 *
 *   4. Que el derecho salga de `gives_access` y no de `status`. La doc avisa
 *      que van a agregar estados nuevos; switchear sobre `status` es una bomba
 *      con fecha puesta por el proveedor.
 *
 *   5. Que del body NO salga ningun dato que decida plata. Lo unico que se usa
 *      es el `app_user_id`; el derecho se le pregunta a RevenueCat.
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
  defineSecret: () => ({ value: () => "TEST-key" }),
}));
jest.mock("firebase-functions/v2/https", () => ({
  onRequest: (_opts: unknown, handler: unknown) => handler,
}));

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
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
  ENTITLEMENT_ALUMNO,
  RC_WEBHOOK_EVENTS_COLLECTION,
  STATUS_SIN_DERECHO,
  TOLERANCIA_FIRMA_MS,
  firmaRcValida,
  runRcWebhook,
  uidDelEvento,
  type RcWebhookRequestLike,
} from "../subscriptions/rc/webhook";
import {
  RcApiError,
  normalizarLista,
  statusQueOtorga,
  type RcSubscription,
} from "../subscriptions/rc/client";

// ---------------------------------------------------------------------------
// Andamio
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
      collection: (col: string) => ({ doc: (id: string) => docRef(col, id) }),
    }),
  };

  return { app: app as never, store, escrituras };
}

const AHORA = Date.parse("2026-09-10T12:00:00.000Z");
const UID = "alumno-1";
const EVENTO_ID = "evt_abc123";
const SECRETO = "sec_de_prueba_revenuecat";

const MUNDO = (): Store => ({ users: { [UID]: { role: "athlete" } } });

/** Un evento de RevenueCat, recortado a lo que el handler mira. */
function evento(over: Record<string, unknown> = {}) {
  return {
    api_version: "1.0",
    event: {
      id: EVENTO_ID,
      type: "INITIAL_PURCHASE",
      app_user_id: UID,
      // Presente A PROPOSITO y con un valor que otorgaria: si el handler lo
      // leyera en vez de re-consultar, los tests de "no lee el body" fallarian.
      entitlement_ids: [ENTITLEMENT_ALUMNO],
      product_id: "treino_alumno_mensual",
      ...over,
    },
  };
}

/** Arma el request con la firma BIEN calculada sobre los bytes que manda. */
function pedido(
  cuerpo: unknown,
  opts: { secreto?: string; tsMs?: number; rawBody?: Buffer } = {},
): RcWebhookRequestLike {
  const secreto = opts.secreto ?? SECRETO;
  const tsMs = opts.tsMs ?? AHORA;
  const t = String(Math.floor(tsMs / 1000));
  const raw = opts.rawBody ?? Buffer.from(JSON.stringify(cuerpo), "utf8");
  const v1 = createHmac("sha256", secreto)
    .update(`${t}.`)
    .update(raw)
    .digest("hex");
  return {
    body: cuerpo,
    rawBody: raw,
    header: (n: string) =>
      n.toLowerCase() === "x-revenuecat-webhook-signature"
        ? `t=${t},v1=${v1}`
        : undefined,
  };
}

function sub(over: Partial<RcSubscription> = {}): RcSubscription {
  return {
    gives_access: true,
    status: "active",
    entitlements: { items: [{ lookup_key: ENTITLEMENT_ALUMNO }] },
    ...over,
  };
}

function fakeRc(respuesta: RcSubscription[] | Error) {
  const consultados: string[] = [];
  return {
    consultados,
    rcClient: {
      getSubscriptions: async (id: string) => {
        consultados.push(id);
        if (respuesta instanceof Error) throw respuesta;
        return respuesta;
      },
    },
  };
}

const deps = (
  rcClient: { getSubscriptions: (id: string) => Promise<RcSubscription[]> },
  over: Record<string, unknown> = {},
) => ({
  rcClient,
  nowMs: AHORA,
  signingSecret: SECRETO,
  entitlement: ENTITLEMENT_ALUMNO,
  ...over,
});

beforeEach(() => {
  warnSpy.mockClear();
  errorSpy.mockClear();
});

// ---------------------------------------------------------------------------
// 1. La firma
// ---------------------------------------------------------------------------

describe("rc/webhook — la firma va sobre los BYTES CRUDOS", () => {
  it("acepta una firma bien armada", () => {
    const req = pedido(evento());
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: req.rawBody,
        nowMs: AHORA,
      }),
    ).toBe(true);
  });

  it("EL TEST QUE IMPORTA: re-serializar el body ROMPE la firma", () => {
    // RevenueCat manda su JSON con SU formato. Cualquier round-trip por
    // `JSON.parse` + `JSON.stringify` puede cambiar los bytes —orden de claves,
    // espacios, escapes de unicode— y la firma deja de matchear. La doc lo
    // advierte textualmente.
    //
    // Se simula con un body espaciado, que es exactamente lo que produciria un
    // re-serializado distinto del original.
    const cuerpo = evento();
    const original = Buffer.from(JSON.stringify(cuerpo, null, 2), "utf8");
    const req = pedido(cuerpo, { rawBody: original });

    // Con los bytes originales: valida.
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: original,
        nowMs: AHORA,
      }),
    ).toBe(true);

    // Con el MISMO objeto re-serializado sin espacios: NO valida.
    //
    // Si algun dia este test se pone verde, alguien cambio el codigo para
    // firmar sobre `JSON.stringify(req.body)` y el webhook va a rechazar
    // requests legitimos en produccion.
    const reserializado = Buffer.from(JSON.stringify(cuerpo), "utf8");
    expect(original.equals(reserializado)).toBe(false);
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: reserializado,
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("rechaza si falta el header", () => {
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: undefined,
        rawBody: Buffer.from("{}"),
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("rechaza un header sin t o sin v1", () => {
    const base = {
      signingSecret: SECRETO,
      rawBody: Buffer.from("{}"),
      nowMs: AHORA,
    };
    expect(firmaRcValida({ ...base, header: "v1=abc" })).toBe(false);
    expect(firmaRcValida({ ...base, header: "t=123" })).toBe(false);
    expect(firmaRcValida({ ...base, header: "cualquier cosa" })).toBe(false);
  });

  it("rechaza un v1 alterado en un solo caracter", () => {
    const req = pedido(evento());
    const header = req.header("x-revenuecat-webhook-signature")!;
    const roto = header.slice(0, -1) + (header.endsWith("a") ? "b" : "a");
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: roto,
        rawBody: req.rawBody,
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("rechaza un ts viejo — la ventana de replay es de 5 minutos", () => {
    const viejo = AHORA - TOLERANCIA_FIRMA_MS - 1000;
    const req = pedido(evento(), { tsMs: viejo });
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: req.rawBody,
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("rechaza un ts del FUTURO — la tolerancia es simetrica", () => {
    // Un reloj adelantado del lado de ellos es deriva legitima; uno adelantado
    // media hora es alguien fabricando un `t` para estirar la ventana.
    const futuro = AHORA + TOLERANCIA_FIRMA_MS + 1000;
    const req = pedido(evento(), { tsMs: futuro });
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: req.rawBody,
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("rechaza una firma hecha con OTRO secreto", () => {
    const req = pedido(evento(), { secreto: "el-secreto-viejo" });
    expect(
      firmaRcValida({
        signingSecret: SECRETO,
        header: req.header("x-revenuecat-webhook-signature"),
        rawBody: req.rawBody,
        nowMs: AHORA,
      }),
    ).toBe(false);
  });

  it("sin secreto configurado pasa — modo degradado, y se avisa", async () => {
    const { app } = fakeApp(MUNDO());
    const rc = fakeRc([sub()]);
    const r = await runRcWebhook(
      app,
      { body: evento(), rawBody: Buffer.from("{}"), header: () => undefined },
      deps(rc.rcClient, { signingSecret: "" }),
    );
    expect(r).toBe("acreditado");
    // El modo degradado que no se ve es el que se queda para siempre.
    expect(warnSpy).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// 2. El derecho sale de `gives_access`, no del body ni de `status`
// ---------------------------------------------------------------------------

describe("rc/client — statusQueOtorga", () => {
  it("otorga con gives_access true y nuestro entitlement", () => {
    expect(statusQueOtorga([sub()], ENTITLEMENT_ALUMNO)).toBe("active");
  });

  it("NO otorga si gives_access es false, aunque el status diga active", () => {
    // Este es el caso que hace que switchear sobre `status` sea una bomba.
    expect(
      statusQueOtorga([sub({ gives_access: false, status: "active" })], ENTITLEMENT_ALUMNO),
    ).toBeNull();
  });

  it("otorga con un status que todavia no existe, si gives_access es true", () => {
    // La doc avisa: «additional states might be added in the future».
    expect(
      statusQueOtorga([sub({ status: "algo_que_inventaron_mañana" })], ENTITLEMENT_ALUMNO),
    ).toBe("algo_que_inventaron_mañana");
  });

  it("NO otorga si el entitlement es de otro producto", () => {
    expect(
      statusQueOtorga(
        [sub({ entitlements: { items: [{ lookup_key: "otra_cosa" }] } })],
        ENTITLEMENT_ALUMNO,
      ),
    ).toBeNull();
  });

  it("prefiere la suscripcion SANA sobre la que esta en gracia", () => {
    // El alumno que migro de mensual a anual puede tener dos vivas, con la
    // vieja en gracia por un cobro que rebota. Degradarlo por eso seria un bug
    // que solo aparece en el caso mas raro y mas caro.
    const enGracia = sub({ status: "in_grace_period" });
    expect(statusQueOtorga([enGracia, sub()], ENTITLEMENT_ALUMNO)).toBe("active");
    expect(statusQueOtorga([sub(), enGracia], ENTITLEMENT_ALUMNO)).toBe("active");
  });

  it("devuelve in_grace_period si es lo unico que hay", () => {
    expect(
      statusQueOtorga([sub({ status: "in_grace_period" })], ENTITLEMENT_ALUMNO),
    ).toBe("in_grace_period");
  });

  it("tolera entitlements ausente, null, o sin items", () => {
    expect(statusQueOtorga([sub({ entitlements: null })], ENTITLEMENT_ALUMNO)).toBeNull();
    expect(statusQueOtorga([sub({ entitlements: {} })], ENTITLEMENT_ALUMNO)).toBeNull();
  });
});

describe("rc/client — normalizarLista no confia en la forma del sobre", () => {
  it("acepta {items: [...]}", () => {
    expect(normalizarLista({ items: [{ gives_access: true, status: "active" }] })).toHaveLength(1);
  });

  it("acepta un array pelado", () => {
    expect(normalizarLista([{ gives_access: true, status: "active" }])).toHaveLength(1);
  });

  it("devuelve vacio ante cualquier otra cosa, sin explotar", () => {
    expect(normalizarLista(null)).toEqual([]);
    expect(normalizarLista({})).toEqual([]);
    expect(normalizarLista("no")).toEqual([]);
  });

  it("no asume que los campos required vengan", () => {
    // «don't assume Always fields are non-null», dice la doc.
    const [s] = normalizarLista({ items: [{}] });
    expect(s.gives_access).toBe(false);
    expect(s.status).toBe("unknown");
  });
});

// ---------------------------------------------------------------------------
// 3. El handler
// ---------------------------------------------------------------------------

describe("rc/webhook — el handler", () => {
  it("acredita: escribe status active", async () => {
    const { app, store } = fakeApp(MUNDO());
    const rc = fakeRc([sub()]);

    const r = await runRcWebhook(app, pedido(evento()), deps(rc.rcClient));

    expect(r).toBe("acreditado");
    expect(store.users[UID].athleteSubscription).toEqual({ status: "active" });
    // Se re-consulto de verdad, con el uid del evento.
    expect(rc.consultados).toEqual([UID]);
  });

  it("EL TEST QUE IMPORTA: el mapa escrito tiene EXACTAMENTE una clave", async () => {
    // `athletePaywallInputChanged` compara el mapa entero serializado. Un
    // `updatedAt` adentro haria correr el trigger en CADA evento de RevenueCat
    // aunque el derecho no se haya movido — y con el paywall prendido eso paga
    // una query a `trainer_links` por cada alumno sin derecho.
    //
    // Si este test se pone rojo porque alguien agrego un campo: el campo va
    // AFUERA del mapa, como hermano de `users/{uid}`.
    const { app, store } = fakeApp(MUNDO());
    await runRcWebhook(app, pedido(evento()), deps(fakeRc([sub()]).rcClient));

    const mapa = store.users[UID].athleteSubscription as Record<string, unknown>;
    expect(Object.keys(mapa)).toEqual(["status"]);
  });

  it("mapea in_grace_period a grace", async () => {
    const { app, store } = fakeApp(MUNDO());
    const rc = fakeRc([sub({ status: "in_grace_period" })]);

    expect(await runRcWebhook(app, pedido(evento()), deps(rc.rcClient))).toBe("acreditado");
    expect(store.users[UID].athleteSubscription).toEqual({ status: "grace" });
  });

  it("revoca cuando ninguna suscripcion otorga", async () => {
    const mundo = MUNDO();
    mundo.users[UID].athleteSubscription = { status: "active" };
    const { app, store } = fakeApp(mundo);

    const r = await runRcWebhook(app, pedido(evento()), deps(fakeRc([]).rcClient));

    expect(r).toBe("revocado");
    expect(store.users[UID].athleteSubscription).toEqual({
      status: STATUS_SIN_DERECHO,
    });
  });

  it("NO lee el derecho del body: un evento que miente no acredita", async () => {
    // El body dice `entitlement_ids: [alumno_pro]`, que otorgaria. RevenueCat
    // dice que no hay nada. Gana RevenueCat.
    const { app, store } = fakeApp(MUNDO());

    const r = await runRcWebhook(
      app,
      pedido(evento({ entitlement_ids: [ENTITLEMENT_ALUMNO], type: "INITIAL_PURCHASE" })),
      deps(fakeRc([]).rcClient),
    );

    expect(r).toBe("revocado");
    expect(store.users[UID].athleteSubscription).toEqual({
      status: STATUS_SIN_DERECHO,
    });
  });

  it("no escribe si el status no cambio", async () => {
    const mundo = MUNDO();
    mundo.users[UID].athleteSubscription = { status: "active" };
    const { app, escrituras } = fakeApp(mundo);

    const r = await runRcWebhook(app, pedido(evento()), deps(fakeRc([sub()]).rcClient));

    expect(r).toBe("sin-cambios");
    // Solo la marca del dedupe, ninguna escritura sobre el usuario.
    expect(escrituras.filter((e) => e.col === "users")).toHaveLength(0);
  });

  it("dedupe: el mismo evento dos veces consulta a RevenueCat UNA vez", async () => {
    const { app } = fakeApp(MUNDO());
    const rc = fakeRc([sub()]);

    expect(await runRcWebhook(app, pedido(evento()), deps(rc.rcClient))).toBe("acreditado");
    expect(await runRcWebhook(app, pedido(evento()), deps(rc.rcClient))).toBe("duplicado");

    expect(rc.consultados).toEqual([UID]);
  });

  it("EL TEST QUE IMPORTA: un error transitorio NO marca el dedupe", async () => {
    // Si lo marcara, el reintento de RevenueCat entraria por el dedupe y se
    // descartaria: el alumno que pago nunca cobraria su acreditacion. Y aca no
    // hay barrido nocturno que lo salve, como si lo hay del lado del PF.
    const mundo = MUNDO();
    const { app, store } = fakeApp(mundo);
    const caido = fakeRc(new RcApiError("503", 503, true));

    expect(await runRcWebhook(app, pedido(evento()), deps(caido.rcClient))).toBe("error-rc");
    expect(store[RC_WEBHOOK_EVENTS_COLLECTION]?.[EVENTO_ID]).toBeUndefined();

    // Y el reintento, con el MISMO id, entra y acredita.
    const sano = fakeRc([sub()]);
    expect(await runRcWebhook(app, pedido(evento()), deps(sano.rcClient))).toBe("acreditado");
    expect(store.users[UID].athleteSubscription).toEqual({ status: "active" });
  });

  it("firma invalida: corta ANTES de consultar a RevenueCat", async () => {
    const { app } = fakeApp(MUNDO());
    const rc = fakeRc([sub()]);

    const r = await runRcWebhook(
      app,
      { body: evento(), rawBody: Buffer.from("{}"), header: () => "t=1,v1=nope" },
      deps(rc.rcClient),
    );

    expect(r).toBe("firma-invalida");
    expect(rc.consultados).toEqual([]);
  });

  it("sin app_user_id: 200 y no consulta nada", async () => {
    const { app } = fakeApp(MUNDO());
    const rc = fakeRc([sub()]);

    const r = await runRcWebhook(
      app,
      pedido(evento({ app_user_id: undefined })),
      deps(rc.rcClient),
    );

    expect(r).toBe("sin-uid");
    expect(rc.consultados).toEqual([]);
  });

  it("usuario inexistente: no lo CREA, y no consulta a RevenueCat", async () => {
    // Puede ser un app_user_id anonimo de RevenueCat. Un webhook no crea
    // usuarios: si lo hiciera, cualquiera con la clave de firma podria sembrar
    // documentos en `users`.
    const { app, store } = fakeApp({ users: {} });
    const rc = fakeRc([sub()]);

    const r = await runRcWebhook(app, pedido(evento()), deps(rc.rcClient));

    expect(r).toBe("sin-alumno");
    expect(store.users[UID]).toBeUndefined();
    expect(rc.consultados).toEqual([]);
  });

  it("uidDelEvento prefiere app_user_id sobre original_app_user_id", () => {
    expect(
      uidDelEvento({
        event: { app_user_id: "el-logueado", original_app_user_id: "el-anonimo" },
      }),
    ).toBe("el-logueado");
    expect(uidDelEvento({ event: {} })).toBeNull();
    expect(uidDelEvento({})).toBeNull();
    expect(uidDelEvento(null)).toBeNull();
  });
});
