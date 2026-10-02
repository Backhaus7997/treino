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

// La puerta modular de `firebase-admin/app`, traducida al doble namespaced.
//
// Producción dejó de hacer `admin.app()` y ahora usa `getApp()`; el
// `jest.mock("firebase-admin", …)` de arriba no cubre ese specifier. Los dobles
// salen del MISMO objeto, así que no pueden driftear.
//
// Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());


// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba.
//
// `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Producción
// importa FieldValue de `firebase-admin/firestore`, y sin esto le
// llega el REAL: el Firestore de mentira de este archivo no reconoce sus
// sentinels, guarda basura en vez de aplicarlos, y el test falla —o peor, pasa—
// por un motivo que no tiene que ver con lo que quiere probar.
//
// Getters y no valores: los factories se evalúan por demanda, así que esto no
// depende del orden entre los dos `jest.mock`.
//
// Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeApp());

import { HttpsError } from "firebase-functions/v2/https";

import { runCreatePreapproval as runCreatePreapprovalReal } from "../subscriptions/mp/create-preapproval";
import {
  MpApiError,
  MpClient,
  MpPreapproval,
  MpPreapprovalPlan,
} from "../subscriptions/mp/client";
import { DIFERIR_PRIMER_COBRO_ENABLED } from "../subscriptions/mp/diferir-primer-cobro";
import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

// ---------------------------------------------------------------------------
// Un Firestore de mentira, chico a proposito: `collection().doc().get()` y
// `.set()` para el checkout, y un `where('==')` sobre un solo campo para juntar
// los planes de un PF (lo unico que el handler pregunta por query). El helper
// `fake-tx-firestore` del repo modela TRANSACCIONES y esta tipado a dos
// colecciones; acá no hay transaccion y hay tres.
// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

function fakeApp(
  seed: Store = {},
  opts: { fallaLaQueryDePlanes?: boolean; fallaLaLecturaDeCheckouts?: boolean } = {},
) {
  // Copia por DOCUMENTO y no por JSON: los Timestamp de mentira de los planes
  // llevan una funcion (`toMillis`) que un clon por JSON borra.
  const store: Store = {};
  for (const [col, docs] of Object.entries(seed)) {
    store[col] = {};
    for (const [id, d] of Object.entries(docs)) store[col][id] = { ...d };
  }
  const escrituras: { col: string; id: string; data: unknown }[] = [];
  /** Cada `get` de un documento, en orden: lo que fija cuanto se lee y cuando. */
  const lecturas: { col: string; id: string }[] = [];

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => ({
          get: async () => {
            lecturas.push({ col, id });
            if (opts.fallaLaLecturaDeCheckouts && col === "mp_checkouts") {
              throw new Error("firestore caido");
            }
            return {
              exists: store[col]?.[id] !== undefined,
              data: () => store[col]?.[id],
            };
          },
          set: async (data: Record<string, unknown>) => {
            store[col] = store[col] ?? {};
            store[col][id] = data;
            escrituras.push({ col, id, data });
          },
        }),
        // Solo igualdad sobre UN campo, que es lo unico que usa produccion. Un
        // operador de mas TIENE que explotar: un fake que acepta de mas deja
        // pasar una query que Firestore rechazaria por falta de indice.
        where: (campo: string, op: string, valor: unknown) => {
          if (op !== "==") {
            throw new Error(`fakeApp: operador no soportado en where: ${op}`);
          }
          return {
            get: async () => {
              if (opts.fallaLaQueryDePlanes) throw new Error("firestore caido");
              return {
                docs: Object.entries(store[col] ?? {})
                  .filter(([, d]) => d[campo] === valor)
                  .map(([id, d]) => ({ id, data: () => d })),
              };
            },
          };
        },
      }),
    }),
  };

  return { app: app as never, store, escrituras, lecturas };
}

/**
 * Un cliente de MP de mentira que anota con qué lo llamaron.
 *
 * [suscripciones] es lo que devuelve la BUSQUEDA por plan (con lo que el
 * handler comprueba si el PF tiene dias pagos). Un plan que no figura devuelve
 * `[]`, y un `Error` hace fallar la busqueda de ese plan.
 */
function fakeMp(
  respuesta: MpPreapprovalPlan | Error = { id: "2c93", init_point: "https://mp/x" },
  suscripciones: Record<string, MpPreapproval[] | Error> = {},
) {
  const llamadas: unknown[] = [];
  const bajas: string[] = [];
  const busquedas: string[] = [];
  const client: MpClient = {
    getPreapproval: async () => ({}),
    searchPreapprovalsByPlan: async (planId) => {
      busquedas.push(planId);
      const r = suscripciones[planId];
      if (r instanceof Error) throw r;
      return r ?? [];
    },
    createPreapprovalPlan: async (input) => {
      llamadas.push(input);
      if (respuesta instanceof Error) throw respuesta;
      return respuesta;
    },
    // Se anota en vez de tirar: lo que estos tests fijan es que NUNCA se llame,
    // y una excepcion se veria como un fallo del checkout en vez de como lo que
    // seria — una baja que no correspondia.
    cancelPreapproval: async (id) => {
      bajas.push(id);
      return { id, status: "cancelled" };
    },
  };
  return { client, llamadas, bajas, busquedas };
}

const PF = { users: { t1: { role: "trainer" } } };
const OK = { mpClient: fakeMp().client, nowMs: 1_000_000 };

/**
 * `runCreatePreapproval` con el interruptor del diferimiento ENCENDIDO por defecto.
 *
 * Los tests de este archivo prueban el camino con diferimiento, y no tienen por que
 * depender del valor de la constante `DIFERIR_PRIMER_COBRO_ENABLED`: flipearla (el
 * rollback) no puede ponerlos rojos por accidente. Un test del camino apagado pasa
 * `diferirHabilitado: false` y gana sobre este default.
 */
const runCreatePreapproval: typeof runCreatePreapprovalReal = (app, uid, raw, deps) =>
  runCreatePreapprovalReal(app, uid, raw, { diferirHabilitado: true, ...deps });

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

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2",
      cycle: "monthly",
    }, { ...OK, mpClient: mp.client });

    expect(r).toEqual({
      initPoint: "https://mp/x",
      planId: "2c93",
      status: "created",
    });
  });

  it("abrir un checkout NO da de baja la suscripcion que el PF ya tiene", async () => {
    // Es la mitad de la decision de diseño del cobro doble, y la que se puede
    // fijar desde acá. Abrir un checkout no es pagar: MP deja la suscripcion en
    // `pending` hasta que el PF carga el medio de pago. Cancelar la vieja en
    // este momento dejaria SIN PLAN al que mira el precio y cierra la pestaña —
    // y la baja en MP es terminal, no se deshace arrepintiendose.
    //
    // La vieja se cancela cuando la nueva queda CONFIRMADA, desde el
    // reconciliador. Ver el encabezado de `mp/reconcile.ts`.
    const { app } = fakeApp({
      users: {
        t1: {
          role: "trainer",
          subscription: { tier: "plan2", status: "active" },
        },
      },
    });
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", {
      tier: "plan3",
      cycle: "monthly",
    }, { ...OK, mpClient: mp.client });

    expect(mp.bajas).toEqual([]);
    // El handler LEE `subscription` solo para decidir si difiere el primer cobro
    // (ver `diferir-primer-cobro.ts`), y una suscripcion viva nunca difiere:
    // ni abre prueba ni sale a MP a buscar pagos.
    expect(mp.llamadas[0]).not.toHaveProperty("freeTrialDays");
    expect(mp.busquedas).toEqual([]);
  });

  it("guarda el mapeo preapproval → (PF, plan), que es lo unico irrecuperable", async () => {
    // Sin este documento, un webhook con un id no sabe de que plan es la
    // suscripcion: MP no devuelve `preapproval_plan_id`.
    const { app, store } = fakeApp(PF);

    await runCreatePreapproval(app, "t1", {
      tier: "plan3",
      cycle: "annual",
    }, OK);

    expect(store.mp_plans["2c93"]).toMatchObject({
      uid: "t1",
      tier: "plan3",
      cycle: "annual",
    });
  });

  it("el mapeo se escribe ANTES que el doc de checkout", async () => {
    // El orden es la politica: si algo falla en el medio, lo que no se puede
    // perder es de que plan es el cobro. El checkout es una comodidad.
    const { app, escrituras } = fakeApp(PF);

    await runCreatePreapproval(app, "t1", {
      tier: "plan1",
      cycle: "monthly",
    }, OK);

    expect(escrituras.map((e) => e.col)).toEqual([
      "mp_plans",
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

    await runCreatePreapproval(app, "t1", {
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

    await runCreatePreapproval(app, "t1", {
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

  // ── El mail: MP ya no lo pide, y por eso desaparecieron sus tests ──
  //
  // Habia tres tests acá sobre de donde salia `payer_email` y cual ganaba.
  // Ya no existen porque el dato ya no existe: el checkout va contra un PLAN,
  // que no lo pide, y MP le pregunta al pagador quien es. El test de abajo
  // pinea justamente eso.

  it("NO se le manda ningun mail a MP — el plan no lo pide", async () => {
    // Si alguien vuelve a mandarlo, MP ata el cobro a ese mail y reaparece el
    // bug que este rediseño existe para matar: el PF cuya cuenta de Mercado
    // Pago usa otro mail no puede pagar nunca.
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", {
      tier: "plan1",
      cycle: "monthly",
      payerEmail: "loquesea@x.com",
    }, { ...OK, mpClient: mp.client });

    expect(mp.llamadas[0]).not.toHaveProperty("payerEmail");
    expect(JSON.stringify(mp.llamadas[0])).not.toContain("loquesea");
  });

  it("el PLAN se le acredita a quien PIDIO", async () => {
    // `external_reference` lleva el uid del que llamo. Es lo que reemplaza al
    // mail como vinculo con la persona, y ahora es el UNICO.
    const { app, store } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { ...OK, mpClient: mp.client });

    expect((mp.llamadas[0] as { externalReference: string }).externalReference)
      .toBe("t1");
    expect(store.mp_plans["2c93"]).toMatchObject({ uid: "t1" });
  });

  it("el plan se llama como lo lee el PF, no con el código del tier", async () => {
    // Es el nombre que MP muestra en su checkout, en la lista de suscripciones
    // y en el mail de cada cobro. Con el código crudo decía «plan1».
    const casos = [
      { tier: "plan1", cycle: "monthly", nombre: "TREINO — Plan 1 (mensual)" },
      { tier: "plan3", cycle: "annual", nombre: "TREINO — Plan 3 (anual)" },
    ];
    for (const c of casos) {
      const { app } = fakeApp(PF);
      const mp = fakeMp();

      await runCreatePreapproval(app, "t1", {
        tier: c.tier, cycle: c.cycle,
      }, { ...OK, mpClient: mp.client });

      expect((mp.llamadas[0] as { reason: string }).reason).toBe(c.nombre);
    }
  });

  it("la URL de retorno es del servidor — si no, es un open redirect", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", {
      tier: "plan1",
      cycle: "monthly",
      backUrl: "https://atacante.com",
      back_url: "https://atacante.com",
    }, { ...OK, mpClient: mp.client });

    expect((mp.llamadas[0] as { backUrl: string }).backUrl)
      .toBe("https://app.gettreino.com/?to=facturacion");
  });

  it("la URL de retorno entra por la raíz, sin App Link ni path directo", async () => {
    // El Coach Hub web usa HASH routing: el path se ignora entero, asi que
    // `https://app.gettreino.com/ajustes` dejaba al PF que pago en el DASHBOARD.
    // Y `/abrir/profe` es un App Link: en un telefono podria abrir la app en
    // vez de volver a la pestaña donde el PF estaba pagando. Se entra por la
    // raiz con el query, y ahi `DeepLinkDestination` resuelve el destino.
    // Ver el encabezado de BACK_URL en `create-preapproval.ts`.
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(
      app, "t1", { tier: "plan1", cycle: "monthly" },
      { ...OK, mpClient: mp.client },
    );

    const { backUrl } = mp.llamadas[0] as { backUrl: string };
    expect(backUrl).not.toContain("/abrir/");
    expect(backUrl).toContain("to=facturacion");
    // El path pelado es exactamente lo que NO funciona.
    expect(backUrl).not.toBe("https://app.gettreino.com/ajustes");
  });

  it("el ciclo anual cobra 12 meses, no 1", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp();

    await runCreatePreapproval(app, "t1", {
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
      runCreatePreapproval(app, "a1", {
        tier: "plan1", cycle: "monthly",
      }, OK));

    expect(err.code).toBe("permission-denied");
    expect(escrituras).toHaveLength(0);
  });

  it("un uid sin documento tampoco", async () => {
    const { app } = fakeApp({ users: {} });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "fantasma", {
        tier: "plan1", cycle: "monthly",
      }, OK));

    expect(err.code).toBe("permission-denied");
  });

  it("`free` NO es comprable — es la ausencia de plan, no un plan", async () => {
    const { app } = fakeApp(PF);

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
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
        runCreatePreapproval(app, "t1", {
          tier, cycle: "monthly",
        }, OK));
      expect(err.code).toBe("invalid-argument");
    });
  }

  it("rechaza un ciclo que no existe", async () => {
    const { app } = fakeApp(PF);
    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan1", cycle: "semanal",
      }, OK));
    expect(err.code).toBe("invalid-argument");
  });

  it("no sale a MP si el rol no da — se valida ANTES de gastar una llamada", async () => {
    const { app } = fakeApp({ users: { a1: { role: "athlete" } } });
    const mp = fakeMp();

    await errorDe(() =>
      runCreatePreapproval(app, "a1", {
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
        planId: "viejo",
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

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r).toEqual({
      initPoint: "https://mp/viejo",
      planId: "viejo",
      status: "reused",
    });
    expect(mp.llamadas).toHaveLength(0);
  });

  it("OTRO plan abre uno nuevo aunque haya checkout vigente", async () => {
    // Cambiar de plan1 a plan2 tiene que poder hacerse sin esperar 30 minutos.
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan3", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r.status).toBe("created");
    expect(mp.llamadas).toHaveLength(1);
  });

  it("el mismo plan pero VENCIDO abre uno nuevo", async () => {
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 31 * 60 * 1000 });

    expect(r.status).toBe("created");
  });

  it("el mismo tier con OTRO ciclo abre uno nuevo — mensual y anual no son lo mismo", async () => {
    const { app } = fakeApp(abierto);
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "annual",
    }, { mpClient: mp.client, nowMs: 1_000_000 + 60_000 });

    expect(r.status).toBe("created");
  });

  it("un checkout guardado sin initPoint no se reusa", async () => {
    const { app } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_checkouts: {
        t1: { planId: "x", tier: "plan2", cycle: "monthly", createdAtMs: 1_000_000 },
      },
    });
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
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
      runCreatePreapproval(app, "t1", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("unavailable");
  });

  it("un error NO reintentable da `internal` — no mentirle al PF con 'probá de nuevo'", async () => {
    const { app } = fakeApp(PF);
    const mp = fakeMp(new MpApiError("token vencido", 401));

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("internal");
  });

  it("si MP falla no queda NADA escrito", async () => {
    const { app, escrituras } = fakeApp(PF);
    const mp = fakeMp(new MpApiError("MP caido", 500));

    await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(escrituras).toHaveLength(0);
  });

  it("una respuesta sin init_point falla en vez de devolver un string vacio", async () => {
    const { app, escrituras } = fakeApp(PF);
    const mp = fakeMp({ id: "2c93" });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
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
      runCreatePreapproval(app, "t1", {
        tier: "plan1", cycle: "monthly",
      }, { ...OK, mpClient: mp.client }));

    expect(err.code).toBe("internal");
    expect(escrituras).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Volver a suscribirse con dias ya pagos. Un PF que se dio de baja conserva el
// plan hasta `currentPeriodEnd`; si antes de esa fecha vuelve al MISMO plan, el
// checkout nuevo cobraba en el acto y pagaba dos veces los mismos dias. Ahora el
// plan nace con una prueba de N dias y se espera que MP cobre cuando el periodo
// vence (supuesto que no esta medido contra MP).
// La regla entera se prueba en `mp-diferir-primer-cobro.test.ts`; acá se fija
// lo que ESTE handler hace con la decision.
// ---------------------------------------------------------------------------

describe("runCreatePreapproval: volver a suscribirse con dias pagos", () => {
  const AHORA = Date.parse("2026-09-07T12:00:00.000Z");
  const DIA_MS = 24 * 60 * 60 * 1000;
  /**
   * El periodo pago vence el 20/9 a las 09:00 ART. `AHORA` es el 7/9 a las 09:00 ART:
   * del 7/9 al 20/9 son 13 dias de calendario argentino (7 + 13 = 20), y tambien 13
   * dias de 24 h justos porque la hora del dia es la misma. Por eso en estas
   * fixtures la cuenta por calendario y la del tiempo exacto coinciden; los casos
   * donde se separan estan mas abajo, con sus propios instantes.
   */
  const FIN = Date.parse("2026-09-20T12:00:00.000Z");
  const ts = (ms: number) => ({ toMillis: () => ms });

  /** Un PF dado de baja que pago plan2 mensual el 20/8. */
  const PF_DADO_DE_BAJA = (): Store => ({
    users: {
      t1: {
        role: "trainer",
        subscription: {
          tier: "plan2",
          status: "cancelled",
          currentPeriodEnd: ts(FIN),
        },
      },
    },
    mp_plans: {
      p0: {
        producto: "trainer",
        uid: "t1",
        tier: "plan2",
        cycle: "monthly",
        createdAt: ts(AHORA - 20 * DIA_MS),
        terminal: true,
      },
    },
  });

  /**
   * Lo que MP dice del plan p0 cuando su ultimo cobro fue en la fecha pedida. Con
   * montos POSITIVOS, para que la rama positiva de la regla de los montos corra en
   * todo el flujo principal.
   */
  const cobroDeP0El = (ultimoCobroIso: string): Record<string, MpPreapproval[]> => ({
    p0: [{
      id: "s0",
      status: "cancelled",
      auto_recurring: { frequency: 1, frequency_type: "months" },
      summarized: {
        charged_quantity: 1,
        charged_amount: 22000,
        last_charged_date: ultimoCobroIso,
        last_charged_amount: 22000,
        pending_charge_quantity: 0,
      },
    }],
  });

  /** Un cobro real el 20/8: con un periodo mensual cubre hasta `FIN`. */
  const COBRO_DE_P0 = cobroDeP0El("2026-08-20T12:00:00.000Z");

  const deps = (mpClient: MpClient) => ({ mpClient, nowMs: AHORA });

  it("difiere: el plan se crea con la prueba y la fecha queda en mp_plans y mp_checkouts", async () => {
    const { app, store } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("created");
    // 13 dias de calendario argentino (7/9 + 13 = 20/9): se busca que el primer
    // cobro caiga el dia en que vence lo que ya estaba pago.
    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
    expect(store.mp_plans["2c93"].diferidoHastaMs).toBe(FIN);
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
    // Y se le pregunto a MP por el plan que pago, no por cualquiera.
    expect(mp.busquedas).toEqual(["p0"]);
  });

  it("difiere aunque la busqueda de MP omita last_charged_date: el respaldo desde el alta", async () => {
    // Si MP no manda la fecha del ultimo cobro, sin respaldo el diferimiento no se
    // dispararia nunca y el PF volveria a pagar dos veces. `date_created` mas los
    // cobros que MP confirma alcanzan: alta 20/8 + 1 cobro = 20/9.
    const { app, store } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, {
      p0: [{
        id: "s0",
        status: "cancelled",
        date_created: "2026-08-20T12:00:00.000Z",
        auto_recurring: { frequency: 1, frequency_type: "months" },
        summarized: { charged_quantity: 1, pending_charge_quantity: 0 },
      }],
    });

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    // Mismo vencimiento (20/9), mismos 13 dias de calendario (7/9 + 13 = 20/9).
    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
    expect(store.mp_plans["2c93"].diferidoHastaMs).toBe(FIN);
  });

  it("difiere tambien el cambio de ciclo dentro del mismo plan (mensual a anual)", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "annual",
    }, deps(mp.client));

    const llamada = mp.llamadas[0] as {
      freeTrialDays: number;
      frequencyMonths: number;
      transactionAmount: number;
    };
    // Los dias salen de lo que ya estaba pago (7/9 a 20/9: 13), no del ciclo nuevo.
    expect(llamada.freeTrialDays).toBe(13);
    // La prueba difiere el primer cobro: el precio y el ciclo son los pedidos.
    expect(llamada.frequencyMonths).toBe(12);
    expect(llamada.transactionAmount).toBe(TIER_PRICES_ARS.plan2.annual);
  });

  it("los dias salen de la fecha y del reloj del request: hora y media mas tarde, 13 dias igual", async () => {
    // A las 10:30 ART del 7/9 sigue siendo 7/9: del 7/9 al 20/9 son 13 dias de
    // calendario, aunque el tiempo exacto que falta sean 12 dias y 22,5 horas.
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: AHORA + 90 * 60 * 1000 });

    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
  });

  it("el caso real: abre el 2/10 a las 09:30 ART y lo pago vence el 1/11: 30 dias de prueba, no 31", async () => {
    // El PF pago el 1/10 a las 11:47 ART (14:47Z), asi que lo pago vence el 1/11 a
    // las 11:47 ART. Abre el checkout el 2/10 a las 09:30 ART (12:30Z): faltan 30
    // dias y 2 h 17 min. En dias de calendario argentino, del 2/10 al 1/11 son 30
    // (2/10 + 29 = 31/10, y un dia mas es el 1/11). Contar el tiempo exacto con
    // `ceil` daba 31, y MP mostraba "31 dias gratis".
    const vence = Date.parse("2026-11-01T14:47:00.000Z");
    const mundo = PF_DADO_DE_BAJA();
    (mundo.users.t1.subscription as Record<string, unknown>).currentPeriodEnd = ts(vence);
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, cobroDeP0El("2026-10-01T14:47:00.000Z"));

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: Date.parse("2026-10-02T12:30:00.000Z") });

    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(30);
    expect(store.mp_plans["2c93"].diferidoHastaMs).toBe(vence);
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(vence);
  });

  it("el dia cambia a las 00:00 ART (03:00Z), no a las 00:00 UTC", async () => {
    // Misma fecha de vencimiento (FIN: 20/9), dos relojes a un minuto de distancia:
    //   2026-09-08T02:59Z = 7/9 a las 23:59 ART: 7/9 + 13 = 20/9, 13 dias.
    //   2026-09-08T03:00Z = 8/9 a las 00:00 ART: 8/9 + 12 = 20/9, 12 dias.
    // Un corte en la medianoche UTC (el reloj de la function) daria 12 en los dos.
    for (const [ahoraIso, dias] of [
      ["2026-09-08T02:59:00.000Z", 13],
      ["2026-09-08T03:00:00.000Z", 12],
    ] as const) {
      const { app } = fakeApp(PF_DADO_DE_BAJA());
      const mp = fakeMp(undefined, COBRO_DE_P0);

      await runCreatePreapproval(app, "t1", {
        tier: "plan2", cycle: "monthly",
      }, { mpClient: mp.client, nowMs: Date.parse(ahoraIso) });

      expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(dias);
    }
  });

  it("con horas sobrantes cuenta calendario: abre a las 08:00 ART y vence 13 dias despues a las 09:00", async () => {
    // 2026-09-07T11:00Z = 7/9 a las 08:00 ART; FIN = 20/9 a las 09:00 ART. Faltan 13
    // dias y 1 hora, y un `ceil` del tiempo exacto daria 14. Del 7/9 al 20/9 son 13
    // dias de calendario.
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, { mpClient: mp.client, nowMs: Date.parse("2026-09-07T11:00:00.000Z") });

    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
  });

  it("no cambia el monto, la referencia ni la URL de retorno", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(mp.llamadas[0]).toMatchObject({
      externalReference: "t1",
      transactionAmount: TIER_PRICES_ARS.plan2.monthly,
      frequencyMonths: 1,
      backUrl: "https://app.gettreino.com/?to=facturacion",
    });
  });

  it("diferir tampoco otorga entitlement: no escribe `subscription` ni baja nada", async () => {
    const { app, escrituras } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(escrituras.map((e) => e.col)).toEqual(["mp_plans", "mp_checkouts"]);
    expect(mp.bajas).toEqual([]);
  });

  it("el cliente no puede pedir ni evitar la prueba: ignora lo que mande", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2",
      cycle: "monthly",
      // Lo que mandaria alguien que quiere 400 dias gratis, o ninguno.
      freeTrialDays: 400,
      free_trial: { frequency: 400, frequency_type: "days" },
      diferidoHastaMs: AHORA + 400 * DIA_MS,
    }, deps(mp.client));

    // Los de siempre (7/9 a 20/9: 13), no los 400 del cliente.
    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
  });

  // ── Cuando NO se difiere: el checkout es el de siempre, byte por byte ──

  /** Lo que tiene que valer para CUALQUIER checkout normal. */
  const esUnCheckoutNormal = (
    mp: ReturnType<typeof fakeMp>,
    store: Store,
  ) => {
    expect(mp.llamadas).toHaveLength(1);
    expect(mp.llamadas[0]).not.toHaveProperty("freeTrialDays");
    expect(store.mp_plans["2c93"]).not.toHaveProperty("diferidoHastaMs");
    // La forma del documento de checkout es exactamente la de antes: es la que
    // el reuso espera de los que ya estan guardados.
    expect(Object.keys(store.mp_checkouts.t1).sort())
      .toEqual(["createdAtMs", "cycle", "initPoint", "planId", "tier"]);
  };

  it("un PF sin suscripcion: checkout normal, sin salir a MP a buscar pagos", async () => {
    const { app, store } = fakeApp(PF);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
    expect(mp.busquedas).toEqual([]);
  });

  it("dado de baja en OTRO tier: checkout normal, sin buscar pagos", async () => {
    // Pagar plan3 y pedir plan2 no es "volver": son dos cobros distintos.
    const mundo = PF_DADO_DE_BAJA();
    (mundo.users.t1.subscription as Record<string, unknown>).tier = "plan3";
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
    expect(mp.busquedas).toEqual([]);
  });

  it("dado de baja con el periodo VENCIDO: checkout normal", async () => {
    const mundo = PF_DADO_DE_BAJA();
    (mundo.users.t1.subscription as Record<string, unknown>).currentPeriodEnd =
      ts(AHORA - DIA_MS);
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
  });

  it("dado de baja con MENOS de un dia por delante: checkout normal", async () => {
    const mundo = PF_DADO_DE_BAJA();
    (mundo.users.t1.subscription as Record<string, unknown>).currentPeriodEnd =
      ts(AHORA + 6 * 60 * 60 * 1000);
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
  });

  it("dado de baja pero MP NO muestra ningun cobro: checkout normal", async () => {
    // Una fecha futura en `subscription` no prueba que se haya pagado. Se
    // consulto a MP, y MP no respalda nada: se cobra en el acto, como antes.
    const { app, store } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, {
      p0: [{
        id: "s0",
        status: "cancelled",
        auto_recurring: { frequency: 1, frequency_type: "months" },
        summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
      }],
    });

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
    expect(mp.busquedas).toEqual(["p0"]);
  });

  it("el unico cobro esta en un plan de ALUMNO: checkout normal", async () => {
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_plans.p0 = {
      uid: "t1",
      producto: "athlete",
      cycle: "monthly",
      createdAt: ts(AHORA - 20 * DIA_MS),
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    esUnCheckoutNormal(mp, store);
    expect(mp.busquedas).toEqual([]);
  });

  // ── Cuando no se puede LEER, no se abre el checkout ──

  it("si MP falla al buscar pagos: `unavailable` y NO se crea nada", async () => {
    // Abrir el checkout igual seria cobrar en el acto a alguien que quiza tiene
    // dias pagos: el doble cobro que esto cierra. El PF puede reintentar.
    const { app, escrituras } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, { p0: new MpApiError("MP caido", 503) });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan2", cycle: "monthly",
      }, deps(mp.client)));

    expect(err.code).toBe("unavailable");
    expect(mp.llamadas).toHaveLength(0);
    expect(escrituras).toHaveLength(0);
  });

  it("si la busqueda falla con un error que no es de MP, tambien `unavailable`", async () => {
    const { app, escrituras } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, { p0: new Error("socket hang up") });

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan2", cycle: "monthly",
      }, deps(mp.client)));

    expect(err.code).toBe("unavailable");
    expect(mp.llamadas).toHaveLength(0);
    expect(escrituras).toHaveLength(0);
  });

  it("si falla la lectura de los planes en Firestore: `unavailable` y NO se crea nada", async () => {
    const { app, escrituras } = fakeApp(PF_DADO_DE_BAJA(), {
      fallaLaQueryDePlanes: true,
    });
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", {
        tier: "plan2", cycle: "monthly",
      }, deps(mp.client)));

    expect(err.code).toBe("unavailable");
    expect(mp.llamadas).toHaveLength(0);
    expect(escrituras).toHaveLength(0);
  });

  it("un fallo de lectura NO afecta a quien no necesita leer", async () => {
    // Un PF sin suscripcion no consulta planes: con Firestore "caido" en esa
    // query igual compra normal.
    const { app, store } = fakeApp(PF, { fallaLaQueryDePlanes: true });
    const mp = fakeMp(undefined, { p0: new MpApiError("MP caido", 503) });

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("created");
    esUnCheckoutNormal(mp, store);
  });

  // ── La ventana de reuso: un checkout diferido y uno normal NO se mezclan ──

  const checkoutGuardado = (extra: Record<string, unknown> = {}) => ({
    planId: "viejo",
    tier: "plan2",
    cycle: "monthly",
    initPoint: "https://mp/viejo",
    createdAtMs: AHORA - 60_000,
    ...extra,
  });

  it("el MISMO pedido diferido dentro de la ventana reusa el checkout y no crea otro plan", async () => {
    // El doble click del PF dado de baja: MP no deduplica, y un segundo plan es
    // un segundo cobro.
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = { t1: checkoutGuardado({ diferidoHastaMs: FIN }) };
    const { app } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r).toEqual({
      initPoint: "https://mp/viejo",
      planId: "viejo",
      status: "reused",
    });
    expect(mp.llamadas).toHaveLength(0);
    // Y tampoco se vuelve a buscar el pago en MP: ya se verifico cuando se abrio.
    expect(mp.busquedas).toEqual([]);
  });

  it("un checkout NORMAL guardado no se reusa para un pedido que ahora difiere", async () => {
    // Reusarlo cobraria en el acto a alguien que tiene dias pagos. Pasa cuando
    // el PF abrio el checkout, se dio de baja, y vuelve a tocar "ELEGIR PLAN"
    // dentro de los 30 minutos.
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = { t1: checkoutGuardado() };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("created");
    // 7/9 + 13 = 20/9 (FIN).
    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
    // Un checkout normal NO es atajo: se busca el pago en MP como siempre.
    expect(mp.busquedas).toEqual(["p0"]);
  });

  it("un checkout DIFERIDO guardado no se reusa para un pedido normal", async () => {
    // Al reves: ya no le quedan dias pagos (se reactivo, o el periodo vencio) y
    // reusar el diferido lo dejaria con una prueba que no le corresponde.
    const { app, store } = fakeApp({
      ...PF,
      mp_checkouts: { t1: checkoutGuardado({ diferidoHastaMs: FIN }) },
    });
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("created");
    esUnCheckoutNormal(mp, store);
  });

  it("un checkout diferido a una fecha que PASA del fin de periodo de hoy no se reusa", async () => {
    // Si el periodo se achico desde que se abrio, esa fecha ya no es lo que el PF
    // tiene pago: no hay atajo, se busca en MP, y el resultado (FIN) no coincide
    // con lo guardado, asi que se abre un plan nuevo con la fecha correcta.
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = {
      t1: checkoutGuardado({ diferidoHastaMs: FIN + 3 * DIA_MS }),
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("created");
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
    expect(mp.busquedas).toEqual(["p0"]);
  });

  it("un checkout guardado ANTES de esto (sin el campo) se sigue reusando en un pedido normal", async () => {
    // Los documentos de `mp_checkouts` que hay en produccion no tienen
    // `diferidoHastaMs`. Si dejaran de matchear, el primer PF que toque el
    // boton dos veces dentro de su ventana se llevaria un plan de mas en MP.
    const { app } = fakeApp({
      ...PF,
      mp_checkouts: { t1: checkoutGuardado() },
    });
    const mp = fakeMp();

    const r = await runCreatePreapproval(app, "t1", {
      tier: "plan2", cycle: "monthly",
    }, deps(mp.client));

    expect(r.status).toBe("reused");
    expect(mp.llamadas).toHaveLength(0);
  });

  // ── El doble click: con un checkout diferido ya abierto, NO se vuelve a buscar ──
  //
  // Sin el atajo, cada toque de un PF dado de baja pagaba hasta tres busquedas en
  // MP aunque el checkout ya estuviera abierto y fuera a reusarse. La verificacion
  // del pago se hizo cuando se abrio.

  const PEDIDO = { tier: "plan2", cycle: "monthly" };

  it("el segundo toque reusa el checkout y hace 0 busquedas en MP", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const primero = await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));
    expect(primero.status).toBe("created");
    // La verificacion se hizo UNA vez.
    expect(mp.busquedas).toEqual(["p0"]);

    const segundo = await runCreatePreapproval(
      app, "t1", PEDIDO, { mpClient: mp.client, nowMs: AHORA + 60_000 });

    expect(segundo).toEqual({
      initPoint: primero.initPoint,
      planId: primero.planId,
      status: "reused",
    });
    // Ni una busqueda mas, ni un plan mas.
    expect(mp.busquedas).toEqual(["p0"]);
    expect(mp.llamadas).toHaveLength(1);
  });

  it("diez toques seguidos hacen UNA sola verificacion y UN solo plan", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    for (let toque = 0; toque < 10; toque++) {
      await runCreatePreapproval(
        app, "t1", PEDIDO, { mpClient: mp.client, nowMs: AHORA + toque * 1000 });
    }

    expect(mp.busquedas).toHaveLength(1);
    expect(mp.llamadas).toHaveLength(1);
  });

  it("el atajo trae la MISMA fecha: lo que se reusa es lo que se guardo", async () => {
    const { app, store } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));
    await runCreatePreapproval(
      app, "t1", PEDIDO, { mpClient: mp.client, nowMs: AHORA + 60_000 });

    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
    expect(store.mp_plans["2c93"].diferidoHastaMs).toBe(FIN);
  });

  it("pasada la ventana de reuso se vuelve a buscar y se abre un plan nuevo", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp({ id: "otro", init_point: "https://mp/otro" }, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));
    const tarde = await runCreatePreapproval(
      app, "t1", PEDIDO, { mpClient: mp.client, nowMs: AHORA + 31 * 60 * 1000 });

    expect(tarde.status).toBe("created");
    expect(mp.busquedas).toEqual(["p0", "p0"]);
    expect(mp.llamadas).toHaveLength(2);
  });

  it("otro ciclo dentro de la ventana no usa el atajo: se busca y se abre un plan nuevo", async () => {
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));
    const anual = await runCreatePreapproval(
      app, "t1", { tier: "plan2", cycle: "annual" },
      { mpClient: mp.client, nowMs: AHORA + 60_000 });

    expect(anual.status).toBe("created");
    expect(mp.busquedas).toEqual(["p0", "p0"]);
  });

  it("otro tier dentro de la ventana tampoco: no es atajo ni es elegible", async () => {
    // Pide plan3 estando dado de baja en plan2: no es volver al mismo plan.
    const { app } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));
    const otro = await runCreatePreapproval(
      app, "t1", { tier: "plan3", cycle: "monthly" },
      { mpClient: mp.client, nowMs: AHORA + 60_000 });

    expect(otro.status).toBe("created");
    expect(mp.busquedas).toEqual(["p0"]);
    expect(mp.llamadas[1]).not.toHaveProperty("freeTrialDays");
  });

  it("con una fecha guardada que queda a MENOS de un dia no hay atajo: se busca en MP", async () => {
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = {
      t1: checkoutGuardado({ diferidoHastaMs: AHORA + 6 * 60 * 60 * 1000 }),
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));

    expect(r.status).toBe("created");
    expect(mp.busquedas).toEqual(["p0"]);
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
  });

  it("con una fecha guardada valida, aunque distinta de la que saldria de buscar, SI se reusa", async () => {
    // El atajo confia en la fecha guardada: la verificacion contra MP se hizo
    // cuando se abrio ese checkout, hace menos de 30 minutos.
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = {
      t1: checkoutGuardado({ diferidoHastaMs: FIN - 3 * DIA_MS }),
    };
    const { app } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client));

    expect(r.status).toBe("reused");
    expect(mp.busquedas).toEqual([]);
    expect(mp.llamadas).toHaveLength(0);
  });

  it("no mira el checkout abierto si el PF ni siquiera es elegible: una sola lectura", async () => {
    // La elegibilidad barata va primero y no lee nada. Un PF sin suscripcion lee
    // `mp_checkouts` una vez (la de `abrirCheckout`); uno elegible, dos (el atajo
    // y `abrirCheckout`).
    const noElegible = fakeApp(PF);
    await runCreatePreapproval(
      noElegible.app, "t1", PEDIDO, deps(fakeMp().client));
    const elegible = fakeApp(PF_DADO_DE_BAJA());
    await runCreatePreapproval(
      elegible.app, "t1", PEDIDO, deps(fakeMp(undefined, COBRO_DE_P0).client));

    const deCheckouts = (l: { col: string }[]) =>
      l.filter((x) => x.col === "mp_checkouts").length;
    expect(deCheckouts(noElegible.lecturas)).toBe(1);
    expect(deCheckouts(elegible.lecturas)).toBe(2);
  });

  it("si falla la lectura del checkout abierto: `unavailable` y NO se crea nada", async () => {
    // Igual que cuando fallan los planes o MP: seguir de largo seria abrir un
    // checkout que quiza cobre dos veces.
    const { app, escrituras } = fakeApp(PF_DADO_DE_BAJA(), {
      fallaLaLecturaDeCheckouts: true,
    });
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const err = await errorDe(() =>
      runCreatePreapproval(app, "t1", PEDIDO, deps(mp.client)));

    expect(err.code).toBe("unavailable");
    expect(mp.llamadas).toHaveLength(0);
    expect(escrituras).toHaveLength(0);
  });

  // ── El interruptor apagado: el rollback ──
  //
  // Existe por si MP rechaza (o cuenta distinto) una prueba de dias. Apagado, el
  // checkout es el de siempre: cobra en el acto, y no lee ni busca nada.

  it("apagado, un PF con dias pagos abre un checkout NORMAL y no busca nada en MP", async () => {
    const { app, store, lecturas } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", PEDIDO, {
      ...deps(mp.client),
      diferirHabilitado: false,
    });

    expect(r.status).toBe("created");
    esUnCheckoutNormal(mp, store);
    expect(mp.busquedas).toEqual([]);
    // Ni los planes de Firestore ni el checkout abierto: solo la lectura de
    // `abrirCheckout`.
    expect(lecturas.filter((l) => l.col === "mp_checkouts")).toHaveLength(1);
    expect(lecturas.filter((l) => l.col === "mp_plans")).toHaveLength(0);
  });

  it("apagado, un checkout DIFERIDO que ya estaba abierto no se reusa: se abre uno normal", async () => {
    // El rollback tiene que ser real: si se reusara, el PF seguiria pagando por un
    // plan con una prueba que el interruptor acaba de apagar.
    const mundo = PF_DADO_DE_BAJA();
    mundo.mp_checkouts = { t1: checkoutGuardado({ diferidoHastaMs: FIN }) };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp(undefined, COBRO_DE_P0);

    const r = await runCreatePreapproval(app, "t1", PEDIDO, {
      ...deps(mp.client),
      diferirHabilitado: false,
    });

    expect(r.status).toBe("created");
    esUnCheckoutNormal(mp, store);
  });

  it("encendido, el mismo mundo SI difiere (el control del camino apagado)", async () => {
    const { app, store } = fakeApp(PF_DADO_DE_BAJA());
    const mp = fakeMp(undefined, COBRO_DE_P0);

    await runCreatePreapproval(app, "t1", PEDIDO, {
      ...deps(mp.client),
      diferirHabilitado: true,
    });

    // 7/9 + 13 = 20/9 (FIN).
    expect((mp.llamadas[0] as { freeTrialDays: number }).freeTrialDays).toBe(13);
    expect(store.mp_checkouts.t1.diferidoHastaMs).toBe(FIN);
  });

  it("sin pasar el interruptor vale la constante, sea cual sea su valor", async () => {
    // Fija el cableado del default sin asumir el valor: lo que hace el handler sin
    // el parametro es exactamente lo que hace pasandole la constante.
    const sinParametro = fakeApp(PF_DADO_DE_BAJA());
    const mpSin = fakeMp(undefined, COBRO_DE_P0);
    await runCreatePreapprovalReal(sinParametro.app, "t1", PEDIDO, deps(mpSin.client));

    const conLaConstante = fakeApp(PF_DADO_DE_BAJA());
    const mpCon = fakeMp(undefined, COBRO_DE_P0);
    await runCreatePreapprovalReal(conLaConstante.app, "t1", PEDIDO, {
      ...deps(mpCon.client),
      diferirHabilitado: DIFERIR_PRIMER_COBRO_ENABLED,
    });

    expect(mpSin.llamadas).toEqual(mpCon.llamadas);
    expect(mpSin.busquedas).toEqual(mpCon.busquedas);
  });
});
