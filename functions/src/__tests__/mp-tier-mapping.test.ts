/**
 * mp-tier-mapping.test.ts — como recuperamos de que plan es una suscripcion.
 * LOCAL, sin emulador y sin red.
 *
 * Este archivo existe porque MP no devuelve `preapproval_plan_id`. Si el mapeo
 * se rompe, el reconciliador sabe el ESTADO de una suscripcion pero no el
 * TIER — y sin tier no hay limite que escribir.
 */

const warnSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...a: unknown[]) => warnSpy(...a),
    info: jest.fn(),
    error: jest.fn(),
  },
}));
jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
  }),
}));

// La puerta modular de `firebase-admin/app`, traducida al doble namespaced.
//
// Producción dejó de hacer `admin.app()` y ahora usa `getApp()`; el
// `jest.mock("firebase-admin", …)` de arriba no cubre ese specifier. Los dobles
// salen del MISMO objeto, así que no pueden driftear.
//
// Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/app", () => {
  const ns = jest.requireMock("firebase-admin") as {
    app: () => unknown;
    initializeApp: () => unknown;
  };
  return {
    getApp: (...args: unknown[]) => (ns.app as (...a: unknown[]) => unknown)(...args),
    initializeApp: (...args: unknown[]) =>
      (ns.initializeApp as (...a: unknown[]) => unknown)(...args),
  };
});


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
jest.mock("firebase-admin/firestore", () => {
  const ns = jest.requireMock("firebase-admin") as {
    firestore: Record<string, unknown>;
  };
  return {
    getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
    get FieldValue() {
      return ns.firestore.FieldValue;
    },
  };
});

import {
  CYCLES,
  PAID_TIERS,
  amountFor,
  frequencyMonthsFor,
  lookupPlan,
  recordPlan,
  tierFromAmount,
} from "../subscriptions/mp/tier-mapping";
import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

function fakeApp(seed: Record<string, Record<string, unknown>> = {}) {
  const store: Record<string, Record<string, unknown>> = { ...seed };
  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => ({
          get: async () => ({
            exists: (store[col] as Record<string, unknown>)?.[id] !== undefined,
            data: () => (store[col] as Record<string, unknown>)?.[id],
          }),
          set: async (data: unknown) => {
            store[col] = (store[col] ?? {}) as Record<string, unknown>;
            (store[col] as Record<string, unknown>)[id] = data;
          },
        }),
      }),
    }),
  };
  return { app: app as never, store };
}

beforeEach(() => jest.clearAllMocks());

describe("frequencyMonthsFor", () => {
  it("mensual es 1 mes, anual son 12", () => {
    // 12 meses y NO `frequency_type: "years"`: "months" esta en los tipos del
    // SDK oficial y "years" no aparece. Es lo mismo sin depender de un valor
    // que no pudimos verificar.
    expect(frequencyMonthsFor("monthly")).toBe(1);
    expect(frequencyMonthsFor("annual")).toBe(12);
  });
});

describe("amountFor", () => {
  it("sale de TIER_PRICES_ARS y de ningun otro lado", () => {
    for (const tier of PAID_TIERS) {
      for (const cycle of CYCLES) {
        expect(amountFor(tier, cycle)).toBe(
          TIER_PRICES_ARS[tier as "plan1" | "plan2" | "plan3"][cycle],
        );
      }
    }
  });

  it("`free` no tiene precio — no se cobra", () => {
    expect(amountFor("free", "monthly")).toBeNull();
    expect(amountFor("free", "annual")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// La biyeccion monto ↔ plan. Es la red de seguridad para cuando el documento
// de mapeo falta, y solo funciona si NINGUN par comparte monto.
// ---------------------------------------------------------------------------

describe("tierFromAmount", () => {
  it("los seis montos son distintos entre si — si no, el monto no identifica nada", () => {
    const montos = PAID_TIERS.flatMap((t) =>
      CYCLES.map((c) => amountFor(t, c)),
    );
    expect(new Set(montos).size).toBe(montos.length);
  });

  it("ida y vuelta: todo par se recupera desde su monto", () => {
    for (const tier of PAID_TIERS) {
      for (const cycle of CYCLES) {
        expect(tierFromAmount(amountFor(tier, cycle))).toEqual({ tier, cycle });
      }
    }
  });

  const basura: [string, unknown][] = [
    ["un monto que no es de ningun plan", 9999],
    ["cero", 0],
    ["negativo", -12000],
    ["un string con el numero", "12000"],
    ["null", null],
    ["undefined", undefined],
    ["NaN", Number.NaN],
    ["Infinity", Number.POSITIVE_INFINITY],
    ["un objeto", { amount: 12000 }],
  ];
  for (const [caso, monto] of basura) {
    it(`da null con ${caso} — adivinar un plan seria regalar entitlement`, () => {
      expect(tierFromAmount(monto)).toBeNull();
    });
  }
});

describe("recordPlan", () => {
  it("guarda uid, tier y cycle bajo el id del preapproval", () => {
    // El id de documento ES el preapprovalId: un webhook trae solo eso, y asi
    // el lookup es directo — sin query, sin indice, sin collection group.
    const { app, store } = fakeApp();

    return recordPlan(app, "2c93", {
      uid: "t1", tier: "plan2", cycle: "annual",
    }).then(() => {
      expect(store.mp_plans).toHaveProperty("2c93");
      expect((store.mp_plans as Record<string, unknown>)["2c93"])
        .toMatchObject({ uid: "t1", tier: "plan2", cycle: "annual" });
    });
  });
});

describe("lookupPlan", () => {
  it("el documento es la fuente PRIMARIA", async () => {
    const { app } = fakeApp({
      mp_plans: {
        "2c93": { uid: "t1", tier: "plan3", cycle: "annual" },
      },
    });

    // Se le pasa un monto de plan1 a proposito: el documento tiene que ganar.
    expect(await lookupPlan(app, "2c93", 12000)).toEqual({
      uid: "t1", tier: "plan3", cycle: "annual",
    });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("sin documento cae al MONTO, y GRITA", async () => {
    // Esta es la ventana real: MP creo la suscripcion y nuestra escritura del
    // mapeo fallo despues. Sin la red, ese PF paga y no recibe nada.
    const { app } = fakeApp();

    const r = await lookupPlan(app, "2c93", 22000);

    expect(r).toEqual({ uid: "", tier: "plan2", cycle: "monthly" });
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain("derivado del monto");
  });

  it("el fallback devuelve uid vacio — el monto sabe el PLAN, no la PERSONA", async () => {
    const { app } = fakeApp();
    const r = await lookupPlan(app, "2c93", 39000);
    // Quien llame tiene que sacar el uid del `external_reference`.
    expect(r?.uid).toBe("");
  });

  it("sin documento y sin monto reconocible da null, no un tier por defecto", async () => {
    const { app } = fakeApp();

    expect(await lookupPlan(app, "2c93", 777)).toBeNull();
    expect(await lookupPlan(app, "2c93")).toBeNull();
  });

  const ilegibles: [string, Record<string, unknown>][] = [
    ["tier desconocido", { uid: "t1", tier: "plan9", cycle: "monthly" }],
    ["tier `free`", { uid: "t1", tier: "free", cycle: "monthly" }],
    ["cycle desconocido", { uid: "t1", tier: "plan1", cycle: "semanal" }],
    ["uid vacio", { uid: "", tier: "plan1", cycle: "monthly" }],
    ["sin uid", { tier: "plan1", cycle: "monthly" }],
    ["tier numerico", { uid: "t1", tier: 1, cycle: "monthly" }],
    ["documento vacio", {}],
  ];
  for (const [caso, doc] of ilegibles) {
    it(`un documento con ${caso} se valida y cae al monto`, async () => {
      // Se valida aunque lo hayamos escrito nosotros: "lo escribimos nosotros"
      // no es una garantia de runtime. Misma leccion que subscription-state.ts.
      const { app } = fakeApp({ mp_plans: { "2c93": doc } });

      const r = await lookupPlan(app, "2c93", 12000);

      expect(r).toEqual({ uid: "", tier: "plan1", cycle: "monthly" });
      expect(warnSpy).toHaveBeenCalled();
      expect(warnSpy.mock.calls[0][0]).toContain("ilegible");
    });
  }

  it("un documento ilegible SIN monto de respaldo da null", async () => {
    const { app } = fakeApp({
      mp_plans: { "2c93": { uid: "t1", tier: "plan9" } },
    });

    expect(await lookupPlan(app, "2c93")).toBeNull();
  });
});
