/**
 * mp-create-preapproval.test.ts — el unico punto de la app que abre un cobro.
 * LOCAL, sin emulador y SIN RED: el cliente de MP entra por parametro.
 *
 * Lo que estos tests cuidan no es que "ande": es que el PF no pueda elegir
 * cuanto paga, a nombre de quien, ni a donde vuelve — y que crear un checkout
 * NO le regale el limite del plan.
 */

jest.mock("firebase-functions", () => ({
  logger: { warn: jest.fn(), info: jest.fn(), error: jest.fn() },
}));
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "TEST-token" }),
}));
jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
  }),
  app: jest.fn(),
  initializeApp: jest.fn(),
}));

import { HttpsError } from "firebase-functions/v2/https";

import { runCreatePreapproval } from "../subscriptions/mp/create-preapproval";
import { MpApiError, MpClient, MpPreapproval } from "../subscriptions/mp/client";
import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

// ---------------------------------------------------------------------------
// Un Firestore de mentira, chico a proposito: solo `collection().doc().get()`
// y `.set()`, que es todo lo que el handler usa. El helper `fake-tx-firestore`
// del repo modela TRANSACCIONES y esta tipado a dos colecciones; acá no hay
// transaccion y hay tres.
// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

function fakeApp(seed: Store = {}) {
  const store: Store = JSON.parse(JSON.stringify(seed));
  const escrituras: { col: string; id: string; data: unknown }[] = [];

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => ({
          get: async () => ({
            exists: store[col]?.[id] !== undefined,
            data: () => store[col]?.[id],
          }),
          set: async (data: Record<string, unknown>) => {
            store[col] = store[col] ?? {};
            store[col][id] = data;
            escrituras.push({ col, id, data });
          },
        }),
      }),
    }),
  };

  return { app: app as never, store, escrituras };
}

/** Un cliente de MP de mentira que anota con qué lo llamaron. */
function fakeMp(
  respuesta: MpPreapproval | Error = { id: "2c93", init_point: "https://mp/x" },
) {
  const llamadas: unknown[] = [];
  const client: MpClient = {
    getPreapproval: async () => ({}),
    createPreapproval: async (input) => {
      llamadas.push(input);
      if (respuesta instanceof Error) throw respuesta;
      return respuesta;
    },
  };
  return { client, llamadas };
}

const PF = { users: { t1: { role: "trainer" } } };
const OK = { mpClient: fakeMp().client, nowMs: 1_000_000 };

async function errorDe(fn: () => Promise<unknown>): Promise<HttpsError> {
  try {
    await fn();
  } catch (e) {
    return e as HttpsError;
  }
  throw new Error("se esperaba un HttpsError y la llamada resolvio bien");
}

beforeEach(() => jest.clearAllMocks());

describe("runCreatePreapproval — el camino feliz", () => {
  it("devuelve el init_point y el id que dio MP", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2",
      cycle: "monthly",
    }, { ...OK, mpClient: mp.client });

    expect(r).toEqual({
      initPoint: "https://mp/x",
      preapprovalId: "2c93",
      status: "created",
    });
  });

  it("guarda el mapeo preapproval → (PF, plan), que es lo unico irrecuperable", async () => {
    // Sin este documento, un webhook con un id no sabe de que plan es la
    // suscripcion: MP no devuelve `preapproval_plan_id`.
    const { app, store } = fakeApp(PF);

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan3",
      cycle: "annual",
    }, OK);

    expect(store.mp_preapprovals["2c93"]).toMatchObject({
      uid: "t1",
      tier: "plan3",
      cycle: "annual",
    });
  });

  it("el mapeo se escribe ANTES que el doc de checkout", async () => {
    // El orden es la politica: si algo falla en el medio, lo que no se puede
    // perder es de que plan es el cobro. El checkout es una comodidad.
    const { app, escrituras } = fakeApp(PF);

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan1",
      cycle: "monthly",
    }, OK);

    expect(escrituras.map((e) => e.col)).toEqual([
      "mp_preapprovals",
      "mp_checkouts",
    ]);
  });
});

// ---------------------------------------------------------------------------
// LA INVARIANTE. Si esto se rompe, cualquiera se regala un plan tocando un
// boton: crear un checkout deja de ser "pedir pagar" y pasa a ser "cobrar".
// ---------------------------------------------------------------------------

describe("runCreatePreapproval — NO otorga entitlement", () => {
  it("no escribe `subscription` en NINGUN caso", async () => {
    const { app, escrituras, store } = fakeApp(PF);

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan3",
      cycle: "annual",
    }, OK);

    expect(escrituras.some((e) => e.col === "users")).toBe(false);
    expect(store.users.t1.subscription).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Lo que el cliente NO decide. Cada uno de estos tres fue un agujero real en
// integraciones de pago ajenas.
// ---------------------------------------------------------------------------

describe("runCreatePreapproval — el cliente no elige nada que cueste plata", () => {
  it("el MONTO sale de la tabla del servidor, no del request", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2",
      cycle: "monthly",
      // Lo que un atacante mandaria. Tiene que ser ignorado por completo.
      amount: 1,
      transactionAmount: 1,
      transaction_amount: 1,
    }, { ...OK, mpClient: mp.client });

    expect((mp.llamadas[0] as { transactionAmount: number }).transactionAmount)
      .toBe(TIER_PRICES_ARS.plan2.monthly);
    expect((mp.llamadas[0] as { transactionAmount: number }).transactionAmount)
      .not.toBe(1);
  });

  it("el MAIL sale del token, no del request", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", "real@x.com", {
      tier: "plan1",
      cycle: "monthly",
      payerEmail: "victima@x.com",
      payer_email: "victima@x.com",
      email: "victima@x.com",
    }, { ...OK, mpClient: mp.client });

    expect((mp.llamadas[0] as { payerEmail: string }).payerEmail)
      .toBe("real@x.com");
  });

  it("la URL de retorno es del servidor — si no, es un open redirect", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan1",
      cycle: "monthly",
      backUrl: "https://atacante.com",
      back_url: "https://atacante.com",
    }, { ...OK, mpClient: mp.client });

    expect((mp.llamadas[0] as { backUrl: string }).backUrl)
      .toBe("https://app.gettreino.com/ajustes");
  });

  it("el ciclo anual cobra 12 meses, no 1", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2",
      cycle: "annual",
    }, { ...OK, mpClient: mp.client });

    const call = mp.llamadas[0] as { frequencyMonths: number; transactionAmount: number };
    expect(call.frequencyMonths).toBe(12);
    expect(call.transactionAmount).toBe(TIER_PRICES_ARS.plan2.annual);
  });
});

describe("runCreatePreapproval — quien puede y quien no", () => {
  it("un alumno no puede contratar un plan de entrenador", async () => {
    const { app, escrituras } = fakeApp({ users: { a1: { role: "athlete" } } });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "a1", "a@x.com", {
        tier: "plan1", cycle: "monthly",
      }, OK));

    expect(err.code).toBe("permission-denied");
    expect(escrituras).toHaveLength(0);
  });

  it("un uid sin documento tampoco", async () => {
    const { app } = fakeApp({ users: {} });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "fantasma", "f@x.com", {
        tier: "plan1", cycle: "monthly",
      }, OK));

    expect(err.code).toBe("permission-denied");
  });

  it("`free` NO es comprable — es la ausencia de plan, no un plan", async () => {
    const { app } = fakeApp(PF);

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "free", cycle: "monthly",
      }, OK));

    expect(err.code).toBe("invalid-argument");
  });

  const basura: [string, unknown][] = [
    ["un tier inventado", "plan9"],
    ["mayusculas", "PLAN1"],
    ["null", null],
    ["un numero", 1],
    ["un objeto", { tier: "plan1" }],
  ];
  for (const [caso, tier] of basura) {
    it(`rechaza ${caso} como tier`, async () => {
      const { app } = fakeApp(PF);
      const err = await errorDe(() =>
        runCreatePreapproval(app, "t1", "pf@x.com", {
          tier, cycle: "monthly",
        }, OK));
      expect(err.code).toBe("invalid-argument");
    });
  }

  it("rechaza un ciclo que no existe", async () => {
    const { app } = fakeApp(PF);
    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "semanal",
      }, OK));
    expect(err.code).toBe("invalid-argument");
  });

  it("no sale a MP si el rol no da — se valida ANTES de gastar una llamada", async () => {
    const { app } = fakeApp({ users: { a1: { role: "athlete" } } });
    const mp = fakeMp();

    await errorDe(() =>
      runCreatePreapproval(app, "a1", "a@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(mp.llamadas).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Doble click. MP no deduplica: cada preapproval es independiente, y si el PF
// completa dos, paga dos veces.
// ---------------------------------------------------------------------------

describe("runCreatePreapproval — idempotencia del checkout", () => {
  const abierto = {
    users: { t1: { role: "trainer" } },
    mp_checkouts: {
      t1: {
        preapprovalId: "viejo",
        tier: "plan2",
        cycle: "monthly",
        initPoint: "https://mp/viejo",
        createdAtMs: 1_000_000,
      },
    },
  };

  it("el mismo plan dentro de la ventana reusa el checkout y NO llama a MP", async () => {
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r).toEqual({
      initPoint: "https://mp/viejo",
      preapprovalId: "viejo",
      status: "reused",
    });
    expect(mp.llamadas).toHaveLength(0);
  });

  it("OTRO plan abre uno nuevo aunque haya checkout vigente", async () => {
    // Cambiar de plan1 a plan2 tiene que poder hacerse sin esperar 30 minutos.
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan3", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r.status).toBe("created");
    expect(mp.llamadas).toHaveLength(1);
  });

  it("el mismo plan pero VENCIDO abre uno nuevo", async () => {
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 31 * 60 * 1000 });

    expect(r.status).toBe("created");
  });

  it("el mismo tier con OTRO ciclo abre uno nuevo — mensual y anual no son lo mismo", async () => {
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2", cycle: "annual",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r.status).toBe("created");
  });

  it("un checkout guardado sin initPoint no se reusa", async () => {
    const { app } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_checkouts: {
        t1: { preapprovalId: "x", tier: "plan2", cycle: "monthly", createdAtMs: 1_000_000 },
      },
    });
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", "pf@x.com", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r.status).toBe("created");
  });
});

// ---------------------------------------------------------------------------
// Cuando MP falla. Lo que importa es que no quede basura escrita y que el
// codigo de error diga la verdad sobre si vale reintentar.
// ---------------------------------------------------------------------------

describe("runCreatePreapproval — cuando MP falla", () => {
  it("un error reintentable da `unavailable`", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp(new MpApiError("MP caido", 503));

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("unavailable");
  });

  it("un error NO reintentable da `internal` — no mentirle al PF con 'probá de nuevo'", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp(new MpApiError("token vencido", 401));

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("internal");
  });

  it("si MP falla no queda NADA escrito", async () => {
    const { app, escrituras } = fakeApp(PF);
    const mp = fakeMp(new MpApiError("MP caido", 500));

    await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(escrituras).toHaveLength(0);
  });

  it("una respuesta sin init_point falla en vez de devolver un string vacio", async () => {
    const { app, escrituras } = fakeApp(PF);
    const mp = fakeMp({ id: "2c93" });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("internal");
    expect(err.message).toMatch(/init_point/);
    expect(escrituras).toHaveLength(0);
  });

  it("una respuesta sin id tampoco escribe el mapeo", async () => {
    // Un mapeo con id vacio seria un documento que ningun webhook va a
    // encontrar: peor que no tenerlo, porque parece que esta.
    const { app, escrituras } = fakeApp(PF);
    const mp = fakeMp({ init_point: "https://mp/x" });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", "pf@x.com", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("internal");
    expect(escrituras).toHaveLength(0);
  });
});
