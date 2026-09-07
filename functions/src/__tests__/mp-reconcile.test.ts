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

// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba.
//
// `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Producción
// importa Timestamp/FieldValue de `firebase-admin/firestore`, y sin esto le
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
    get Timestamp() {
      return ns.firestore.Timestamp;
    },
    get FieldValue() {
      return ns.firestore.FieldValue;
    },
  };
});

import {
  reconcileAllSubscriptions,
  reconcileSubscription,
} from "../subscriptions/mp/reconcile";
import { MpApiError, MpPreapproval } from "../subscriptions/mp/client";
import { ReconcileDeps } from "../subscriptions/mp/reconcile";

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

/**
 * El reconciliador ya no pide UNA suscripcion por id: pide las que hay contra
 * un PLAN. `respuesta` es la unica suscripcion del plan, o `null` para el caso
 * normal de un plan que nadie pago todavia.
 */
/** Un "ahora" fijo. El barrido decide abandonos contra el reloj inyectado. */
const AHORA = Date.parse("2026-09-07T12:00:00.000Z");

function fakeMp(
  respuesta: MpPreapproval | Error | null,
  nowMs: number = AHORA,
): ReconcileDeps {
  return {
    nowMs,
    mpClient: {
      getPreapproval: async () => ({}),
      createPreapprovalPlan: async () => ({}),
      searchPreapprovalsByPlan: async () => {
        if (respuesta instanceof Error) throw respuesta;
        return respuesta === null ? [] : [respuesta];
      },
    },
  };
}

/** Un mundo con el mapeo ya escrito y el PF sin suscripcion todavia. */
const MUNDO = (): Store => ({
  users: { t1: { role: "trainer", displayName: "Martin" } },
  mp_plans: { p1: { uid: "t1", tier: "plan2", cycle: "monthly" } },
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
    expect(store.mp_plans.p1.terminal).toBe(true);
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
      mp_plans: {},
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
      mp_plans: {},
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
      mp_plans: { p1: { tier: "plan2", cycle: "monthly" } },
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
      mp_plans: {
        p1: { uid: "t1", tier: "plan2", cycle: "monthly", terminal: true },
      },
    });

    expect(await reconcileAllSubscriptions(app, fakeMp(AUTORIZADA)))
      .toMatchObject({ total: 0, written: 0 });
  });

  it("cuenta escritos, sin cambios, salteados y errores por separado", async () => {
    const { app } = fakeApp({
      users: { t1: { role: "trainer" } },
      mp_plans: {
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
      mp_plans: {
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

// ---------------------------------------------------------------------------
// La cascada del fin de periodo.
//
// Sale de una prueba REAL contra Mercado Pago, y la asimetria que encontramos
// es fea: una suscripcion cancelada que PAGO viene SIN `next_payment_date`,
// mientras que una cancelada que NUNCA pago SI lo trae. Medido sobre dos
// suscripciones de la misma cuenta el 2026-09-07.
//
// O sea que el dato falta justo cuando importa, y el que se queda sin fecha es
// el que te pago. Si `currentPeriodEnd` queda en null, `effective-limit` le
// saca el plan EN EL ACTO a alguien que pago el mes entero.
// ---------------------------------------------------------------------------

import {
  finDePeriodoDesdeAltaMs,
  resolverFinDePeriodo,
} from "../subscriptions/mp/reconcile";

/** El `auto_recurring` tal cual lo devolvio MP en la prueba real. */
const AUTO_RECURRING_REAL = {
  frequency: 1,
  frequency_type: "months",
  transaction_amount: 12000.0,
  currency_id: "ARS",
  start_date: "2026-09-07T11:52:46.997-04:00",
  billing_day_proportional: false,
  has_billing_day: false,
};

describe("finDePeriodoDesdeAltaMs", () => {
  it("suma el periodo al alta, con el payload real de MP", () => {
    const ms = finDePeriodoDesdeAltaMs(AUTO_RECURRING_REAL);
    expect(ms).toBe(Date.parse("2026-10-07T11:52:46.997-04:00"));
  });

  it("respeta una frecuencia de 12 meses (el ciclo anual)", () => {
    const ms = finDePeriodoDesdeAltaMs({
      ...AUTO_RECURRING_REAL, frequency: 12,
    });
    expect(ms).toBe(Date.parse("2027-09-07T11:52:46.997-04:00"));
  });

  it("el desborde de mes lo normaliza el calendario, no nosotros", () => {
    // 31 de enero + 1 mes no existe. `setUTCMonth` lo lleva al 3 de marzo, que
    // es como cuenta el calendario — no hay que corregirlo a mano.
    const ms = finDePeriodoDesdeAltaMs({
      ...AUTO_RECURRING_REAL, start_date: "2026-01-31T00:00:00.000Z",
    });
    expect(new Date(ms as number).toISOString()).toBe("2026-03-03T00:00:00.000Z");
  });

  const noDerivables: [string, unknown][] = [
    ["frequency_type days — no lo entendemos y no lo adivinamos",
      { ...AUTO_RECURRING_REAL, frequency_type: "days" }],
    ["sin start_date", { frequency: 1, frequency_type: "months" }],
    ["start_date que no es fecha",
      { ...AUTO_RECURRING_REAL, start_date: "mañana" }],
    ["frequency cero", { ...AUTO_RECURRING_REAL, frequency: 0 }],
    ["frequency negativa", { ...AUTO_RECURRING_REAL, frequency: -1 }],
    ["frequency fraccionaria", { ...AUTO_RECURRING_REAL, frequency: 1.5 }],
    ["frequency absurda (24 meses es el tope)",
      { ...AUTO_RECURRING_REAL, frequency: 999 }],
    ["null", null],
    ["un string", "auto_recurring"],
  ];
  for (const [caso, ar] of noDerivables) {
    it(`da null con ${caso}`, () => {
      expect(finDePeriodoDesdeAltaMs(ar)).toBeNull();
    });
  }
});

describe("resolverFinDePeriodo — la cascada", () => {
  const base = {
    deMp: null,
    yaGuardada: undefined,
    autoRecurring: AUTO_RECURRING_REAL,
    status: "cancelled" as const,
    planId: "p1",
  };

  it("1. lo que dijo MP gana sobre todo lo demas", () => {
    const deMp = ts(1_000);
    const r = resolverFinDePeriodo({
      ...base,
      deMp: deMp as never,
      yaGuardada: ts(2_000),
    });
    expect(r?.toMillis()).toBe(1_000);
  });

  it("2. sin fecha de MP, gana la que ya teniamos", () => {
    // El caso del PF que estuvo meses suscripto: el barrido diario le fue
    // refrescando la fecha mientras estaba activo.
    const r = resolverFinDePeriodo({ ...base, yaGuardada: ts(9_999) });
    expect(r?.toMillis()).toBe(9_999);
  });

  it("3. sin nada guardado, se deriva del alta — la baja el MISMO DIA", () => {
    // Este es el agujero que encontro la prueba real: se suscribio y cancelo
    // antes de que el barrido corriera una sola vez, asi que no hay nada que
    // conservar. Sin esta rama pierde el mes que pago.
    const r = resolverFinDePeriodo(base);
    expect(r?.toMillis()).toBe(Date.parse("2026-10-07T11:52:46.997-04:00"));
  });

  it("4. si no hay ningun camino, null y un warn que lo grita", () => {
    const r = resolverFinDePeriodo({ ...base, autoRecurring: null });
    expect(r).toBeNull();
    expect(errorSpy.mock.calls.length + warnSpy.mock.calls.length)
      .toBeGreaterThan(0);
  });

  it("con la suscripcion VIVA no se inventa fecha", () => {
    // Mientras MP no dijo nada terminal, que falte la fecha es informacion:
    // no la sabemos. Conservar una vieja seria regalar un periodo que quizas
    // no se pago.
    for (const status of ["active", "pending", "grace"] as const) {
      const r = resolverFinDePeriodo({ ...base, status, yaGuardada: ts(9_999) });
      expect(r).toBeNull();
    }
  });

  it("`paused` tambien conserva: suspender no es no haber pagado", () => {
    const r = resolverFinDePeriodo({ ...base, status: "paused" });
    expect(r).not.toBeNull();
  });

  it("una fecha guardada con forma rota no se usa, se deriva", () => {
    const r = resolverFinDePeriodo({ ...base, yaGuardada: "2026-10-07" });
    expect(r?.toMillis()).toBe(Date.parse("2026-10-07T11:52:46.997-04:00"));
  });
});

// ---------------------------------------------------------------------------
// El caso completo, con los DOS payloads reales de la prueba del 2026-09-07.
// ---------------------------------------------------------------------------

describe("reconcileSubscription — las dos cancelaciones reales", () => {
  it("la que PAGO y no trae fecha conserva el periodo que compro", async () => {
    const { app, store } = fakeApp(MUNDO());

    await reconcileSubscription(app, "p1", fakeMp({
      id: "79e2fbf31595407f839dd772b59ae34a",
      status: "cancelled",
      external_reference: "t1",
      // Vacio, tal cual vino de MP para la suscripcion pagada.
      next_payment_date: undefined,
      auto_recurring: { ...AUTO_RECURRING_REAL, transaction_amount: 22000 },
      summarized: { pending_charge_quantity: 0 },
    }));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.status).toBe("cancelled");
    // No pierde el mes: la fecha sale del alta.
    expect(sub.currentPeriodEnd).not.toBeNull();
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(Date.parse("2026-10-07T11:52:46.997-04:00"));
  });

  it("la que NUNCA pago si trae fecha, y se usa esa", async () => {
    const { app, store } = fakeApp(MUNDO());

    await reconcileSubscription(app, "p1", fakeMp({
      id: "3af60648011f4deab385043c20b290af",
      status: "cancelled",
      external_reference: "t1",
      // Igual a `date_created`: el "proximo" cobro era el primero, que nunca
      // ocurrio. Queda en el pasado, y esta bien — no pago nada.
      next_payment_date: "2026-09-07T11:52:46.000-04:00",
      auto_recurring: AUTO_RECURRING_REAL,
      summarized: { pending_charge_quantity: 0 },
    }));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(Date.parse("2026-09-07T11:52:46.000-04:00"));
  });
});

// ---------------------------------------------------------------------------
// El abandono de planes.
//
// Es el costo del diseño de UN PLAN POR CHECKOUT: cada PF que toca "ELEGIR
// PLAN" y no paga deja un plan que el barrido consultaria contra MP todas las
// noches PARA SIEMPRE. Sin esto, el trabajo nocturno crece con la CURIOSIDAD de
// la gente, no con las ventas.
// ---------------------------------------------------------------------------

import { esAbandonado } from "../subscriptions/mp/reconcile";

const DIA = 24 * 60 * 60 * 1000;

describe("esAbandonado", () => {
  it("un plan recien creado NO se abandona", () => {
    expect(esAbandonado(ts(AHORA - DIA), AHORA)).toBe(false);
  });

  it("a los 31 dias si", () => {
    expect(esAbandonado(ts(AHORA - 31 * DIA), AHORA)).toBe(true);
  });

  it("justo en el limite de 30 dias todavia NO", () => {
    // El corte es estricto: 30 dias exactos sigue vivo. Es la direccion segura
    // — esperar de mas cuesta llamadas, cortar temprano cuesta un cobro.
    expect(esAbandonado(ts(AHORA - 30 * DIA), AHORA)).toBe(false);
  });

  const sinFecha: [string, unknown][] = [
    ["sin createdAt", undefined],
    ["null", null],
    ["el sentinel de serverTimestamp sin resolver", "__ts__"],
    ["un numero suelto", 1_700_000_000],
    ["un string", "2026-09-07"],
  ];
  for (const [caso, v] of sinFecha) {
    it(`NO abandona con ${caso} — ante la duda se sigue mirando`, () => {
      // Gastar una llamada de mas es infinitamente mas barato que dejar de
      // mirar una suscripcion que si existe.
      expect(esAbandonado(v, AHORA)).toBe(false);
    });
  }
});

describe("reconcileAllSubscriptions — saca del barrido lo abandonado", () => {
  const mundoConPlanViejo = (edadDias: number): Store => ({
    users: { t1: { role: "trainer" } },
    mp_plans: {
      p1: {
        uid: "t1", tier: "plan2", cycle: "monthly",
        createdAt: ts(AHORA - edadDias * DIA),
      },
    },
  });

  it("un checkout abandonado hace 31 dias se marca terminal", async () => {
    const { app, store } = fakeApp(mundoConPlanViejo(31));

    // `null` = el plan no tiene ninguna suscripcion. Nadie pago.
    const r = await reconcileAllSubscriptions(app, fakeMp(null));

    expect(r.abandonados).toBe(1);
    expect(store.mp_plans.p1.terminal).toBe(true);
    expect(store.mp_plans.p1.terminalReason).toContain("abandonado");
  });

  it("pero conserva el mapeo — sirve para auditar quien compro que", async () => {
    const { app, store } = fakeApp(mundoConPlanViejo(31));

    await reconcileAllSubscriptions(app, fakeMp(null));

    expect(store.mp_plans.p1.uid).toBe("t1");
    expect(store.mp_plans.p1.tier).toBe("plan2");
  });

  it("uno de ayer NO se toca — el init_point puede seguir sirviendo", async () => {
    const { app, store } = fakeApp(mundoConPlanViejo(1));

    const r = await reconcileAllSubscriptions(app, fakeMp(null));

    expect(r.abandonados).toBe(0);
    expect(store.mp_plans.p1.terminal).toBeUndefined();
  });

  it("un plan VIEJO pero CON suscripcion no se abandona jamas", async () => {
    // El caso que no puede fallar: un PF suscripto hace un año. Marcarlo
    // terminal lo sacaria del barrido y su suscripcion dejaria de
    // reconciliarse — se daria de baja y nunca nos enterariamos.
    const { app, store } = fakeApp(mundoConPlanViejo(400));

    const r = await reconcileAllSubscriptions(app, fakeMp(AUTORIZADA));

    expect(r.abandonados).toBe(0);
    expect(store.mp_plans.p1.terminal).toBeUndefined();
    expect(r.written).toBe(1);
  });

  it("lo marcado deja de consultarse en la corrida siguiente", async () => {
    const { app } = fakeApp(mundoConPlanViejo(31));

    const primera = await reconcileAllSubscriptions(app, fakeMp(null));
    const segunda = await reconcileAllSubscriptions(app, fakeMp(null));

    expect(primera.total).toBe(1);
    expect(segunda.total).toBe(0);
  });
});
