/**
 * mp-reconcile-my-checkout.test.ts — acreditarle el pago al PF en el acto.
 * LOCAL, sin emulador y SIN RED: el cliente de MP entra por parametro.
 *
 * Lo que estos tests cuidan son tres cosas, y ninguna es "que ande":
 *   1. Que nadie pueda pedir la reconciliacion de un plan AJENO.
 *   2. Que el cooldown corte ANTES de la llamada a Mercado Pago, que es lo
 *      unico que este callable expone y lo unico que el resto del modulo no
 *      protege.
 *   3. Que `written` NO se confunda con exito: un `written` con status
 *      `pending` es justo el caso de alguien a quien no se le acredito nada.
 */

const infoSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: { warn: jest.fn(), error: jest.fn(), info: (...a: unknown[]) => infoSpy(...a) },
}));
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "TEST-token" }),
}));
// `reconcile.ts` evalua `onSchedule(...)` al importarse, y este archivo lo
// importa para reusar `reconcileSubscription`.
jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: (_opts: unknown, handler: unknown) => handler,
}));

const ts = (ms: number) => ({ toMillis: () => ms });

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
    Timestamp: { fromMillis: (ms: number) => ({ toMillis: () => ms }) },
  }),
  app: jest.fn(),
  initializeApp: jest.fn(),
}));

// Las dos puertas modulares tienen que dar EL MISMO doble que la namespaced.
// Ver el encabezado de `mp-reconcile.test.ts`; lo fija
// `firebase-admin-mock-surface.test.ts`.
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

import {
  RECONCILE_COOLDOWN_MS,
  estadoDesdeResultados,
  runReconcileMyCheckout,
} from "../subscriptions/mp/reconcile-my-checkout";
import { MpApiError, MpPreapproval } from "../subscriptions/mp/client";
import { ReconcileResult } from "../subscriptions/mp/reconcile";

// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

/**
 * Igual al de `mp-reconcile.test.ts`, mas `.where(campo, "==", valor)`: este
 * callable consulta `mp_plans` filtrado por uid, y sin eso el doble devolveria
 * los planes de TODOS — que es justo lo que un test tiene que poder detectar.
 */
function fakeApp(seed: Store = {}) {
  const store: Store = seed;
  const escrituras: { col: string; id: string; data: unknown; merge: boolean }[] = [];

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
      escrituras.push({ col, id, data, merge: opts?.merge === true });
    },
  });

  const docsDe = (col: string, filtro?: (d: Record<string, unknown>) => boolean) =>
    Object.keys(store[col] ?? {})
      .filter((id) => (filtro ? filtro(store[col][id]) : true))
      .map((id) => ({ id, data: () => store[col][id] }));

  const coleccion = (col: string) => ({
    doc: (id: string) => docRef(col, id),
    get: async () => ({ docs: docsDe(col) }),
    where: (campo: string, op: string, valor: unknown) => {
      if (op !== "==") throw new Error(`el doble solo modela "==", no "${op}"`);
      return { get: async () => ({ docs: docsDe(col, (d) => d[campo] === valor) }) };
    },
  });

  const app = { firestore: () => ({ collection: coleccion }) };

  return { app: app as never, store, escrituras };
}

const AHORA = Date.parse("2026-09-08T12:00:00.000Z");

const AUTORIZADA: MpPreapproval = {
  id: "sub-1",
  status: "authorized",
  external_reference: "t1",
  next_payment_date: "2026-10-08T12:00:00.000Z",
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
};

/**
 * `porPlan` decide que contesta MP para cada plan. `llamadas` registra por cual
 * se pregunto — es como se verifica que el cooldown corto ANTES de la red.
 */
function fakeMp(porPlan: Record<string, MpPreapproval | Error | null>) {
  const llamadas: string[] = [];
  const bajas: string[] = [];
  return {
    llamadas,
    bajas,
    deps: (nowMs: number = AHORA) => ({
      nowMs,
      mpClient: {
        getPreapproval: async () => ({}),
        createPreapprovalPlan: async () => ({}),
        searchPreapprovalsByPlan: async (planId: string) => {
          llamadas.push(planId);
          const r = porPlan[planId];
          if (r instanceof Error) throw r;
          return r == null ? [] : [r];
        },
        // La baja de la suscripcion vieja al cambiar de plan. Se anota en vez
        // de tirar: lo que estos tests miran es el cooldown y a que plan se le
        // pregunto, y una excepcion acá se veria como un fallo de la red.
        cancelPreapproval: async (preapprovalId: string) => {
          bajas.push(preapprovalId);
          return { id: preapprovalId, status: "cancelled" };
        },
      },
    }),
  };
}

/** Un PF con un checkout abierto de plan2 y su mapeo escrito. */
const MUNDO = (): Store => ({
  users: { t1: { role: "trainer" } },
  mp_plans: { p1: { uid: "t1", tier: "plan2", cycle: "monthly" } },
  mp_checkouts: {
    t1: {
      planId: "p1",
      tier: "plan2",
      cycle: "monthly",
      initPoint: "https://mp/checkout/p1",
      createdAtMs: AHORA - 60_000,
    },
  },
});

beforeEach(() => jest.clearAllMocks());

describe("runReconcileMyCheckout — el camino feliz", () => {
  it("MP dice authorized → acreditado, con el tier que compro", async () => {
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.estado).toBe("acreditado");
    expect(r.tier).toBe("plan2");
    expect((store.users.t1.subscription as Record<string, unknown>).status)
      .toBe("active");
  });

  it("MP todavia no autorizo → pendiente, y NO se le miente al PF", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: { ...AUTORIZADA, status: "pending" } });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.estado).toBe("pendiente");
    expect(r.tier).toBeUndefined();
  });

  it("MP no ve ninguna suscripcion contra el plan → pendiente", async () => {
    // Es el outcome MAS PROBABLE al volver del checkout, y no es un error: el
    // PF puede haber abandonado, o MP puede tardar en registrarla.
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: null });

    expect((await runReconcileMyCheckout(app, "t1", mp.deps())).estado)
      .toBe("pendiente");
  });

  it("MP no contesta → no-disponible, que es distinto de `pendiente`", async () => {
    // La diferencia le importa al PF: en uno reintentar sirve, en el otro hay
    // que esperar. Colapsarlos seria decirle "esperá" a alguien cuyo problema
    // se arregla tocando de nuevo.
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: new MpApiError("MP caido", 503) });

    expect((await runReconcileMyCheckout(app, "t1", mp.deps())).estado)
      .toBe("no-disponible");
  });

  it("sin ningun plan a su nombre → sin-checkout, y NO se llama a MP", async () => {
    const { app } = fakeApp({ users: { t1: { role: "trainer" } }, mp_plans: {} });
    const mp = fakeMp({});

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.estado).toBe("sin-checkout");
    expect(mp.llamadas).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// LO QUE DE VERDAD CUIDA ESTE ARCHIVO.
// ---------------------------------------------------------------------------

describe("runReconcileMyCheckout — no se puede tocar un plan ajeno", () => {
  it("solo se consultan los planes CUYO uid es el del token", async () => {
    const mundo = MUNDO();
    mundo.mp_plans.ajeno = { uid: "otro-pf", tier: "plan3", cycle: "monthly" };
    mundo.users["otro-pf"] = { role: "trainer" };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA, ajeno: AUTORIZADA });

    await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(mp.llamadas).toEqual(["p1"]);
    // Y sobre todo: al otro PF no se le escribio nada.
    expect(store.users["otro-pf"].subscription).toBeUndefined();
  });

  it("un PF sin planes propios no ve los de nadie", async () => {
    const mundo = MUNDO();
    mundo.users.t2 = { role: "trainer" };
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t2", mp.deps());

    expect(r.estado).toBe("sin-checkout");
    expect(mp.llamadas).toHaveLength(0);
  });
});

describe("runReconcileMyCheckout — el cooldown corta ANTES de la red", () => {
  it("dentro de la ventana no se llama a MP y se avisa que esta enfriando", async () => {
    const mundo = MUNDO();
    mundo.mp_checkouts.t1.lastReconcileMs = AHORA - 1_000;
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.enfriando).toBe(true);
    expect(r.estado).toBe("pendiente");
    // Lo que importa: CERO llamadas. Si el cooldown fuera despues de
    // `reconcileSubscription`, acá habria una — el GET a MP es su primera linea.
    expect(mp.llamadas).toHaveLength(0);
  });

  it("pasada la ventana vuelve a preguntar", async () => {
    const mundo = MUNDO();
    mundo.mp_checkouts.t1.lastReconcileMs = AHORA - RECONCILE_COOLDOWN_MS - 1;
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.estado).toBe("acreditado");
    expect(mp.llamadas).toEqual(["p1"]);
  });

  it("el cooldown se marca ANTES de salir a MP: si MP revienta, igual queda", async () => {
    // Si se marcara al final, una llamada que falla dejaria la puerta abierta
    // para el proximo click — y el caso en el que mas se clickea es justo ese.
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: new MpApiError("MP caido", 503) });

    await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(store.mp_checkouts.t1.lastReconcileMs).toBe(AHORA);
  });

  it("marcar el cooldown NO borra el link de pago en curso", async () => {
    // `createPreapproval` reusa `initPoint` y `planId` dentro de su ventana de
    // 30 minutos. Un `set()` sin merge acá se los llevaria puestos y el PF
    // perderia el checkout que estaba por pagar.
    const { app, store, escrituras } = fakeApp(MUNDO());
    const mp = fakeMp({ p1: AUTORIZADA });

    await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(escrituras.find((e) => e.col === "mp_checkouts")?.merge).toBe(true);
    expect(store.mp_checkouts.t1.initPoint).toBe("https://mp/checkout/p1");
    expect(store.mp_checkouts.t1.planId).toBe("p1");
  });

  it("sin planes NO se marca cooldown: no hubo ninguna llamada que frenar", async () => {
    const { app, store } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_plans: {},
      mp_checkouts: {},
    });

    await runReconcileMyCheckout(app, "t1", fakeMp({}).deps());

    expect(store.mp_checkouts.t1).toBeUndefined();
  });
});

describe("runReconcileMyCheckout — que planes se saltean, y cual se rescata", () => {
  it("un `terminal` SIN motivo es una baja: no se le vuelve a preguntar", async () => {
    // Una baja no se revierte en MP — se crea un preapproval nuevo con otro id.
    const mundo = MUNDO();
    mundo.mp_plans.p1.terminal = true;
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(mp.llamadas).toHaveLength(0);
    expect(r.estado).toBe("sin-checkout");
  });

  it("un `terminal` POR ABANDONO si se consulta: es el unico rescate posible", async () => {
    // El barrido lo dio por abandonado a los 30 dias y no lo va a mirar nunca
    // mas. Si el PF guardo el `init_point` y pago al dia 31, este callable es lo
    // unico que puede enterarse.
    const mundo = MUNDO();
    mundo.mp_plans.p1.terminal = true;
    mundo.mp_plans.p1.terminalReason = "checkout abandonado";
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ p1: AUTORIZADA });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(mp.llamadas).toEqual(["p1"]);
    expect(r.estado).toBe("acreditado");
  });
});

describe("estadoDesdeResultados — `written` no es exito", () => {
  const base = (over: Partial<ReconcileResult>): ReconcileResult => ({
    planId: "p1",
    outcome: "written",
    ...over,
  });

  it("written + pending NO es acreditado — es el caso que hundia todo", async () => {
    expect(estadoDesdeResultados([base({ status: "pending" })]).estado)
      .toBe("pendiente");
  });

  for (const status of ["active", "grace"] as const) {
    it(`written + ${status} es acreditado`, () => {
      const r = estadoDesdeResultados([
        base({ status, tier: "plan2" }),
      ]);
      expect(r.estado).toBe("acreditado");
      expect(r.tier).toBe("plan2");
    });
  }

  it("unchanged + active tambien es acreditado: ya lo tenia", async () => {
    expect(estadoDesdeResultados([base({ outcome: "unchanged", status: "active" })])
      .estado).toBe("acreditado");
  });

  for (const status of ["paused", "cancelled"] as const) {
    it(`written + ${status} NO es acreditado`, () => {
      expect(estadoDesdeResultados([base({ status })]).estado).toBe("pendiente");
    });
  }

  it("con DOS planes gana el que esta vigente, no el ultimo", async () => {
    // El PF que hace upgrade tiene el viejo `active` y el nuevo `pending`.
    // Decirle "estamos confirmando" seria mentirle sobre lo que YA tiene.
    const r = estadoDesdeResultados([
      base({ planId: "nuevo", outcome: "skipped-pending-no-pisa", status: "pending", tier: "plan3" }),
      base({ planId: "viejo", outcome: "unchanged", status: "active", tier: "plan2" }),
    ]);

    expect(r.estado).toBe("acreditado");
    expect(r.tier).toBe("plan2");
  });

  it("un error de MP tapa al `pendiente`: reintentar sirve, esperar no", async () => {
    expect(estadoDesdeResultados([
      base({ outcome: "sin-suscripcion" }),
      base({ planId: "p2", outcome: "error-mp" }),
    ]).estado).toBe("no-disponible");
  });

  it("pero un acreditado le gana al error: ya sabemos que tiene plan", async () => {
    expect(estadoDesdeResultados([
      base({ outcome: "error-mp" }),
      base({ planId: "p2", outcome: "written", status: "active", tier: "plan1" }),
    ]).estado).toBe("acreditado");
  });

  it("sin resultados es sin-checkout, no pendiente", () => {
    expect(estadoDesdeResultados([]).estado).toBe("sin-checkout");
  });
});

describe("runReconcileMyCheckout — el upgrade completo, de punta a punta", () => {
  it("el pending del plan nuevo no le saca el plan viejo ni le miente", async () => {
    const { app, store } = fakeApp({
      users: {
        t1: {
          role: "trainer",
          subscription: { tier: "plan2", status: "active", currentPeriodEnd: ts(AHORA + 86_400_000) },
        },
      },
      mp_plans: {
        p1: { uid: "t1", tier: "plan2", cycle: "monthly" },
        p2: { uid: "t1", tier: "plan3", cycle: "monthly" },
      },
      mp_checkouts: { t1: { planId: "p2", createdAtMs: AHORA - 60_000 } },
    });
    const mp = fakeMp({
      p1: AUTORIZADA,
      p2: { ...AUTORIZADA, id: "sub-2", status: "pending",
        auto_recurring: { transaction_amount: 39000 } },
    });

    const r = await runReconcileMyCheckout(app, "t1", mp.deps());

    expect(r.estado).toBe("acreditado");
    expect(r.tier).toBe("plan2");
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(sub.status).toBe("active");
  });
});
