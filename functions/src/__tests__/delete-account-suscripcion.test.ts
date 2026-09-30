/**
 * delete-account-suscripcion.test.ts — eliminar la cuenta da de baja la
 * suscripcion ANTES de borrar nada.
 *
 * LOCAL: el cliente de MP y el reloj entran por parametro.
 *
 * Lo que protege, en orden de que tan caro sale:
 *
 *   1. Que una cuenta NO se borre con el cobro vivo. Es lo que hacia antes
 *      `deleteAccount`: el preapproval seguia vivo en Mercado Pago, seguia
 *      cobrando, y la persona ya no tenia puerta para darse de baja.
 *   2. Que si no se pudo cancelar, la cuenta quede EXACTAMENTE como estaba: sin
 *      marcador, para que el reconciliador siga mirando una suscripcion que
 *      todavia cobra.
 *   3. Que el cooldown de la baja no se pueda usar de atajo: un intento que
 *      fallo a medias + un segundo toque enseguida no puede terminar en «sin
 *      suscripcion».
 */

const infoSpy = jest.fn();
const errorSpy = jest.fn();
const warnSpy = jest.fn();

jest.mock("firebase-functions", () => ({
  logger: {
    info: (...a: unknown[]) => infoSpy(...a),
    error: (...a: unknown[]) => errorSpy(...a),
    warn: (...a: unknown[]) => warnSpy(...a),
  },
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "token-falso" }),
}));

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: () => ({}),
}));

jest.mock("firebase-functions/v2/https", () => {
  class HttpsError extends Error {
    constructor(readonly code: string, message: string) {
      super(message);
    }
  }
  return { HttpsError, onCall: () => ({}) };
});

jest.mock("firebase-admin/app", () => ({
  getApp: () => ({}),
  initializeApp: () => ({}),
}));

const ts = (ms: number) => ({ toMillis: () => ms, __ts: true });
const mockBorrar = { __borrar: true };

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  FieldValue: {
    serverTimestamp: () => ({ __sentinel: "now" }),
    delete: () => mockBorrar,
  },
  Timestamp: {
    fromMillis: (ms: number) => ts(ms),
    fromDate: (d: Date) => ts(d.getTime()),
  },
}));

import type { App } from "firebase-admin/app";

import {
  MENSAJE_NO_SE_PUDO_CANCELAR,
  cancelarSuscripcionesAntesDeEliminar,
} from "../cascade/subscriptions";
import { CAMPO_CUENTA_ELIMINADA } from "../subscriptions/mp/reconcile";

const AHORA = Date.parse("2026-09-30T12:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;
const UID = "u1";
const OTRO = "u2";

type Store = Record<string, Record<string, Record<string, unknown>>>;

const plan = (store: Store, id: string) => store.mp_plans?.[id] ?? {};

function fakeApp(seed: Store = {}) {
  const store: Store = {};
  for (const [c, docs] of Object.entries(seed)) {
    store[c] = {};
    for (const [id, d] of Object.entries(docs)) store[c][id] = { ...d };
  }

  const escribir = (col: string, id: string, data: Record<string, unknown>) => {
    store[col] = store[col] ?? {};
    const actual = { ...(store[col][id] ?? {}) };
    for (const [k, v] of Object.entries(data)) {
      if (v === mockBorrar) delete actual[k];
      else actual[k] = v;
    }
    store[col][id] = actual;
  };

  const refDe = (col: string, id: string) => ({
    get: async () => ({
      exists: store[col]?.[id] !== undefined,
      data: () => store[col]?.[id],
    }),
    set: async (data: Record<string, unknown>) => escribir(col, id, data),
  });

  const filtrada = (col: string, filtros: [string, unknown][]) => ({
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [...filtros, [campo, valor]]),
    limit: () => filtrada(col, filtros),
    get: async () => {
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) => filtros.every(([c, v]) => d[c] === v))
        .map(([id, d]) => ({ id, exists: true, data: () => d, ref: refDe(col, id) }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const coleccion = (col: string) => ({
    doc: (id: string) => refDe(col, id),
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [[campo, valor]]),
  });

  const app = { firestore: () => ({ collection: coleccion }) } as unknown as App;
  return { app, store };
}

/** Una alumna con un plan vivo, otro plan cancelado y un plan de OTRA persona. */
const MUNDO = (): Store => ({
  users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
  mp_plans: {
    a1: { producto: "athlete", uid: UID, cycle: "monthly" },
    a2: { producto: "athlete", uid: UID, cycle: "monthly", terminal: true },
    b1: { producto: "athlete", uid: OTRO, cycle: "monthly" },
  },
});

const VIVA = (id: string) => ({
  id,
  status: "authorized",
  external_reference: UID,
  next_payment_date: new Date(AHORA + 10 * DIA_MS).toISOString(),
  auto_recurring: { transaction_amount: 3500 },
  summarized: { pending_charge_quantity: 0 },
});

function fakeMp(
  over: { subs?: Record<string, unknown[]>; fallaBusqueda?: boolean; fallaBaja?: boolean } = {},
) {
  const canceladas: string[] = [];
  const armados = { cuantas: 0 };
  const estado: Record<string, Record<string, unknown>[]> = {};
  for (const [p, subs] of Object.entries(over.subs ?? {})) {
    estado[p] = subs.map((s) => ({ ...(s as object) }));
  }
  const mpClient = {
    getPreapproval: async () => ({}),
    createPreapprovalPlan: async () => ({}),
    searchPreapprovalsByPlan: async (planId: string) => {
      if (over.fallaBusqueda) throw new Error("MP 503");
      return estado[planId] ?? [];
    },
    cancelPreapproval: async (id: string) => {
      if (over.fallaBaja) throw new Error("MP 500");
      canceladas.push(id);
      return { id, status: "cancelled" };
    },
  };
  return {
    canceladas,
    armados,
    deps: {
      nowMs: AHORA,
      getMpClient: () => {
        armados.cuantas += 1;
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return mpClient as any;
      },
    },
  };
}

beforeEach(() => jest.clearAllMocks());

describe("eliminar la cuenta da de baja la suscripcion primero", () => {
  it("sin planes no sale a Mercado Pago ni arma el cliente", async () => {
    const { app, store } = fakeApp({ users: { [UID]: { role: "athlete" } } });
    const mp = fakeMp();

    const n = await cancelarSuscripcionesAntesDeEliminar(app, UID, mp.deps);

    expect(n).toBe(0);
    // El token vacio tira en `createMpClient`: armarlo de mas romperia el
    // borrado de las miles de cuentas que nunca pagaron.
    expect(mp.armados.cuantas).toBe(0);
    expect(store.mp_plans).toBeUndefined();
  });

  it("cancela la suscripcion viva en MP", async () => {
    const { app } = fakeApp(MUNDO());
    const mp = fakeMp({ subs: { a1: [VIVA("sub-1")] } });

    const n = await cancelarSuscripcionesAntesDeEliminar(app, UID, mp.deps);

    expect(n).toBe(1);
    expect(mp.canceladas).toEqual(["sub-1"]);
  });

  it("marca TODOS los planes de la cuenta —tambien los que ya no cobran—, y solo los suyos", async () => {
    // a2 esta terminal y no tiene nada vivo, pero el marcador va igual: un plan
    // cancelado dentro del periodo pagado no es terminal, el barrido lo sigue
    // visitando, y seria el que recree el usuario fantasma.
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp({ subs: { a1: [VIVA("sub-1")] } });

    await cancelarSuscripcionesAntesDeEliminar(app, UID, mp.deps);

    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBe(AHORA);
    expect(plan(store, "a2")[CAMPO_CUENTA_ELIMINADA]).toBe(AHORA);
    // El de OTRA persona no se toca nunca.
    expect(plan(store, "b1")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });

  it("un checkout abandonado (plan sin suscripcion) no es una falla", async () => {
    const { app, store } = fakeApp(MUNDO());
    const mp = fakeMp({ subs: {} });

    const n = await cancelarSuscripcionesAntesDeEliminar(app, UID, mp.deps);

    expect(n).toBe(0);
    expect(mp.canceladas).toEqual([]);
    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBe(AHORA);
  });
});

describe("si no se pudo cancelar, la cuenta NO se toca", () => {
  async function fallo(mp: ReturnType<typeof fakeMp>, seed: Store = MUNDO()) {
    const { app, store } = fakeApp(seed);
    await expect(cancelarSuscripcionesAntesDeEliminar(app, UID, mp.deps)).rejects.toMatchObject({
      code: "unavailable",
      message: MENSAJE_NO_SE_PUDO_CANCELAR,
    });
    return store;
  }

  it("MP no contesta la busqueda", async () => {
    const store = await fallo(fakeMp({ subs: { a1: [VIVA("sub-1")] }, fallaBusqueda: true }));

    // Sin marcador: el reconciliador tiene que seguir mirando esa suscripcion.
    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
    expect(plan(store, "a2")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });

  it("MP rechaza la baja", async () => {
    const mp = fakeMp({ subs: { a1: [VIVA("sub-1")] }, fallaBaja: true });

    const store = await fallo(mp);

    expect(mp.canceladas).toEqual([]);
    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });

  it("el cliente ni se puede armar (token vacio o ausente)", async () => {
    const mp = fakeMp({ subs: { a1: [VIVA("sub-1")] } });
    mp.deps.getMpClient = () => {
      throw new Error("mp/client: MP_ACCESS_TOKEN vacio o ausente");
    };

    const store = await fallo(mp);

    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });

  it("el cooldown de la baja cuenta como falla, no como «sin suscripcion»", async () => {
    // Un intento anterior marco el cooldown y fallo a medias; el usuario toca
    // ELIMINAR otra vez enseguida. Sin esto, la baja contesta «sin suscripcion»
    // sin haber cancelado nada y la cuenta se borra con el cobro vivo.
    const mundo = MUNDO();
    mundo.mp_cancelaciones = { [UID]: { lastCancelMs: AHORA - 1_000 } };
    const mp = fakeMp({ subs: { a1: [VIVA("sub-1")] } });

    const store = await fallo(mp, mundo);

    expect(mp.canceladas).toEqual([]);
    expect(plan(store, "a1")[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });
});
