/**
 * mp-reconcile.test.ts — lo que hace que pagar signifique algo.
 * LOCAL, sin emulador y SIN RED: el cliente de MP entra por parametro.
 *
 * La mitad de estos tests verifican que el reconciliador NO escribe. No es
 * paranoia: escribir un estado que no entendimos baja al PF al limite Free, y
 * el barrido de las 04:00 le bloquea alumnos. Un dato raro de MP terminaria
 * cortandole el servicio a alumnos que no tienen nada que ver.
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

/** Timestamp de mentira con la unica operacion que el codigo usa. */
const ts = (ms: number) => ({ toMillis: () => ms });

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(jest.fn(), {
    FieldValue: { serverTimestamp: () => "__ts__" },
    Timestamp: { fromMillis: (ms: number) => ({ toMillis: () => ms }) },
  }),
  app: jest.fn(),
  initializeApp: jest.fn(),
}));

import {
  reconcileAllSubscriptions,
  reconcileSubscription,
} from "../subscriptions/mp/reconcile";
import { MpApiError, MpClient, MpPreapproval } from "../subscriptions/mp/client";

// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

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

function fakeMp(respuesta: MpPreapproval | Error): { mpClient: MpClient } {
  return {
    mpClient: {
      getPreapproval: async () => {
        if (respuesta instanceof Error) throw respuesta;
        return respuesta;
      },
      createPreapproval: async () => ({}),
    },
  };
}

/** Un mundo con el mapeo ya escrito y el PF sin suscripcion todavia. */
const MUNDO = (): Store => ({
  users: { t1: { role: "trainer", displayName: "Martin" } },
  mp_preapprovals: { p1: { uid: "t1", tier: "plan2", cycle: "monthly" } },
});

const AUTORIZADA: MpPreapproval = {
  id: "p1",
  status: "authorized",
  external_reference: "t1",
  next_payment_date: "2026-10-03T12:00:00.000Z",
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
};

beforeEach(() => jest.clearAllMocks());

describe("reconcileSubscription — el camino que hace que cobrar sirva", () => {
  it("authorized escribe tier + active + la fecha de fin de periodo", async () => {
    const { app, store } = fakeApp(MUNDO());

    const r = await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA));

    expect(r.outcome).toBe("written");
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(sub.status).toBe("active");
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(Date.parse("2026-10-03T12:00:00.000Z"));
  });

  it("escribe con MERGE — sin eso, reconciliar una suscripcion borra el perfil", async () => {
    const { app, store, escrituras } = fakeApp(MUNDO());

    await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA));

    expect(escrituras.find((e) => e.col === "users")?.merge).toBe(true);
    // Lo que ya estaba en el documento sigue estando.
    expect(store.users.t1.role).toBe("trainer");
    expect(store.users.t1.displayName).toBe("Martin");
  });

  it("authorized CON cobro pendiente da grace, no active", async () => {
    // MP no mueve `status` cuando un cobro rebota: deja la suscripcion en
    // authorized y reintenta. Si esta rama se pierde, un PF que no pago se ve
    // igual que uno al dia.
    const { app, store } = fakeApp(MUNDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      summarized: { pending_charge_quantity: 1 },
    }));

    expect((store.users.t1.subscription as Record<string, unknown>).status)
      .toBe("grace");
  });

  it("cancelled escribe cancelled y marca el mapeo como terminal", async () => {
    // Una baja no se revierte en MP: se crea un preapproval nuevo con otro id.
    // Marcarlo lo saca del barrido y ahorra una llamada diaria para siempre.
    const { app, store } = fakeApp(MUNDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      status: "cancelled",
    }));

    expect((store.users.t1.subscription as Record<string, unknown>).status)
      .toBe("cancelled");
    expect(store.mp_preapprovals.p1.terminal).toBe(true);
  });

  it("una baja SIN proxima fecha conserva la que ya teniamos", async () => {
    // Es la regla de no castigar: `effective-limit` le da el plan pago a un
    // cancelled HASTA currentPeriodEnd. Perder la fecha se lo saca en el acto a
    // alguien que pago el periodo entero.
    const mundo = MUNDO();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "active", currentPeriodEnd: ts(9_999_999),
    };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      status: "cancelled",
      next_payment_date: undefined,
    }));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.status).toBe("cancelled");
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(9_999_999);
  });

  it("el uid puede salir de external_reference cuando el mapeo cayo al monto", async () => {
    // Sin documento de mapeo, el MONTO dice el plan pero no la persona. El uid
    // lo pone MP en external_reference, que se lo mandamos nosotros al crear.
    const { app, store } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_preapprovals: {},
    });

    const r = await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA));

    expect(r.outcome).toBe("written");
    expect((store.users.t1.subscription as Record<string, unknown>).tier)
      .toBe("plan2");
  });
});

// ---------------------------------------------------------------------------
// LO QUE NO ESCRIBE. Cada uno de estos, si escribiera, le bloquearia alumnos a
// un entrenador por un dato que no entendimos.
// ---------------------------------------------------------------------------

describe("reconcileSubscription — cuando NO hay que escribir", () => {
  it("un estado de MP ininteligible NO se escribe", async () => {
    const { app, escrituras, store } = fakeApp(MUNDO());

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      status: "loquesea",
    }));

    expect(r.outcome).toBe("skipped-degraded");
    expect(escrituras).toHaveLength(0);
    expect(store.users.t1.subscription).toBeUndefined();
    expect(errorSpy).toHaveBeenCalled();
  });

  it("degradar sobre una suscripcion que YA existe la deja intacta", async () => {
    // El caso que de verdad duele: el PF tiene plan3 activo y MP contesta algo
    // raro. Escribir el fallback lo baja a Free y a las 04:00 pierde alumnos.
    const mundo = MUNDO();
    mundo.users.t1.subscription = {
      tier: "plan3", status: "active", currentPeriodEnd: ts(9_999_999),
    };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      status: "???",
    }));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan3");
    expect(sub.status).toBe("active");
  });

  it("sin plan determinable NO se escribe", async () => {
    const { app, escrituras } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_preapprovals: {},
    });

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      auto_recurring: { transaction_amount: 777 },
    }));

    expect(r.outcome).toBe("skipped-sin-plan");
    expect(escrituras).toHaveLength(0);
  });

  it("sin uid en ningun lado NO se escribe", async () => {
    const { app, escrituras } = fakeApp({
      users: {},
      mp_preapprovals: { p1: { tier: "plan2", cycle: "monthly" } },
    });

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      external_reference: undefined,
    }));

    expect(r.outcome).toBe("skipped-sin-plan");
    expect(escrituras).toHaveLength(0);
  });

  it("si el uid del mapeo NO coincide con el de MP, se rechaza", async () => {
    // Escribir acá le daria el plan de una persona a otra.
    const { app, escrituras } = fakeApp(MUNDO());

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      external_reference: "OTRO-PF",
    }));

    expect(r.outcome).toBe("skipped-uid-no-coincide");
    expect(escrituras).toHaveLength(0);
    expect(errorSpy).toHaveBeenCalled();
  });

  it("si nada cambio NO reescribe — cada write dispara el trigger que manda mail", async () => {
    const mundo = MUNDO();
    mundo.users.t1.subscription = {
      tier: "plan2",
      status: "active",
      currentPeriodEnd: ts(Date.parse("2026-10-03T12:00:00.000Z")),
    };
    const { app, escrituras } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA));

    expect(r.outcome).toBe("unchanged");
    expect(escrituras).toHaveLength(0);
  });

  it("un cambio de SOLO la fecha si se escribe", async () => {
    const mundo = MUNDO();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "active", currentPeriodEnd: ts(1),
    };
    const { app } = fakeApp(mundo);

    expect((await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA))).outcome)
      .toBe("written");
  });

  it("si MP no contesta NO se escribe nada", async () => {
    const { app, escrituras } = fakeApp(MUNDO());

    const r = await reconcileSubscription(
      app, "p1", fakeMp(new MpApiError("MP caido", 503)));

    expect(r.outcome).toBe("error-mp");
    expect(escrituras).toHaveLength(0);
  });

  const fechasRotas: [string, unknown][] = [
    ["un numero", 1_700_000_000],
    ["un string que no es fecha", "mañana"],
    ["un objeto", { date: "2026-10-03" }],
  ];
  for (const [caso, fecha] of fechasRotas) {
    it(`una next_payment_date que es ${caso} se ignora, no se inventa`, async () => {
      const { app, store } = fakeApp(MUNDO());

      await reconcileSubscription(app, "p1", fakeMp({
        ...AUTORIZADA,
        next_payment_date: fecha,
      }));

      expect((store.users.t1.subscription as Record<string, unknown>)
        .currentPeriodEnd).toBeNull();
      expect(warnSpy).toHaveBeenCalled();
    });
  }
});

// ---------------------------------------------------------------------------

describe("reconcileAllSubscriptions — el barrido", () => {
  it("saltea los terminales: una baja no se le vuelve a preguntar a MP", async () => {
    const { app } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_preapprovals: {
        p1: { uid: "t1", tier: "plan2", cycle: "monthly", terminal: true },
      },
    });

    expect(await reconcileAllSubscriptions(app, fakeMp(AUTORIZADA)))
      .toMatchObject({ total: 0, written: 0 });
  });

  it("cuenta escritos, sin cambios, salteados y errores por separado", async () => {
    const { app } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_preapprovals: {
        p1: { uid: "t1", tier: "plan2", cycle: "monthly" },
        p2: { uid: "t1", tier: "plan2", cycle: "monthly", terminal: true },
      },
    });

    const r = await reconcileAllSubscriptions(app, fakeMp(AUTORIZADA));

    expect(r.total).toBe(1);
    expect(r.written).toBe(1);
  });

  it("un preapproval que falla no frena el barrido de los demas", async () => {
    // Misma leccion que el catch por-PF de `entitlement-triggers`.
    const { app } = fakeApp({
      users: { t1: { role: "trainer" }, t2: { role: "trainer" } },
      mp_preapprovals: {
        p1: { uid: "t1", tier: "plan2", cycle: "monthly" },
        p2: { uid: "t2", tier: "plan1", cycle: "monthly" },
      },
    });

    const r = await reconcileAllSubscriptions(
      app, fakeMp(new MpApiError("MP caido", 500)));

    expect(r.total).toBe(2);
    expect(r.errors).toBe(2);
  });
});
