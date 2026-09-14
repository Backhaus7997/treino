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
// importa Timestamp/FieldValue de `firebase-admin/firestore`, y sin esto le
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

  /**
   * Una query. El dato se CONGELA en el momento del `get`, igual que un
   * QuerySnapshot de Firestore.
   *
   * No es un detalle del fake: es la propiedad de la que depende el bug que el
   * barrido tiene que sobrevivir. `reconcileAllSubscriptions` toma el snapshot
   * una sola vez y despues recorre; para cuando llega al documento N, el 1 pudo
   * haber cambiado —lo cambia el propio barrido al dar de baja un plan
   * reemplazado— y el `terminal` que se acaba de escribir NO esta en la mano.
   *
   * Un fake que leyera el store vivo seria mas coherente que la realidad y
   * daria verde con la guarda de reemplazo o sin ella.
   */
  const docsDe = (
    col: string,
    filtro: (d: Record<string, unknown>) => boolean,
  ) => {
    const congelados = Object.keys(store[col] ?? {})
      .filter((id) => filtro(store[col][id] ?? {}))
      .map((id) => ({ id, datos: { ...(store[col][id] ?? {}) } }));
    return {
      docs: congelados.map(({ id, datos }) => ({ id, data: () => datos })),
    };
  };

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => docRef(col, id),
        get: async () => docsDe(col, () => true),
        /**
         * Solo igualdad sobre UN campo, que es lo unico que usa produccion
         * (`where('uid','==',uid)` para juntar los planes de un PF). Cualquier
         * otro operador TIENE que explotar: un fake que acepta de mas deja
         * pasar una query que Firestore rechazaria en produccion por falta de
         * indice, y el test daria verde sobre algo que no anda.
         */
        where: (campo: string, op: string, valor: unknown) => {
          if (op !== "==") {
            throw new Error(`fakeApp: operador no soportado en where: ${op}`);
          }
          return { get: async () => docsDe(col, (d) => d[campo] === valor) };
        },
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

/** Un dia en ms. Las fechas de alta de los planes se escriben contra esto. */
const DIA_MS = 24 * 60 * 60 * 1000;

function fakeMp(
  respuesta: MpPreapproval | Error | null,
  nowMs: number = AHORA,
): ReconcileDeps & { bajas: string[] } {
  const bajas: string[] = [];
  return {
    nowMs,
    bajas,
    mpClient: {
      getPreapproval: async () => ({}),
      createPreapprovalPlan: async () => ({}),
      searchPreapprovalsByPlan: async () => {
        if (respuesta instanceof Error) throw respuesta;
        return respuesta === null ? [] : [respuesta];
      },
      // Se ANOTA en vez de tirar. Un throw acá se lo comeria el catch del
      // reconciliador y quedaria como un log; anotarlo deja que cada test diga
      // explicitamente que no esperaba ninguna baja.
      cancelPreapproval: async (id: string) => {
        bajas.push(id);
        return { id, status: "cancelled" };
      },
    },
  };
}

/**
 * Un MP con una respuesta POR PLAN, que anota las bajas y —esto es lo que
 * importa— **muta el estado igual que MP**: la suscripcion que se cancela pasa a
 * `cancelled` para las busquedas siguientes.
 *
 * Sin esa mutacion no se puede distinguir la guarda de reemplazo de su ausencia:
 * el barrido volveria a ver `authorized` un plan que acabamos de dar de baja, y
 * el test daria verde con la guarda o sin ella.
 */
function fakeMpMultiPlan(
  porPlan: Record<string, MpPreapproval | Error | null>,
  opts: { fallaLaBaja?: MpApiError } = {},
  nowMs: number = AHORA,
): ReconcileDeps & { bajas: string[] } {
  const estado: Record<string, MpPreapproval | Error | null> = { ...porPlan };
  const bajas: string[] = [];
  return {
    nowMs,
    bajas,
    mpClient: {
      getPreapproval: async () => ({}),
      createPreapprovalPlan: async () => ({}),
      searchPreapprovalsByPlan: async (planId: string) => {
        const r = estado[planId];
        if (r instanceof Error) throw r;
        return r == null ? [] : [r];
      },
      cancelPreapproval: async (preapprovalId: string) => {
        bajas.push(preapprovalId);
        if (opts.fallaLaBaja) throw opts.fallaLaBaja;
        for (const [plan, sub] of Object.entries(estado)) {
          if (sub !== null && !(sub instanceof Error) && sub.id === preapprovalId) {
            estado[plan] = { ...sub, status: "cancelled" };
          }
        }
        return { id: preapprovalId, status: "cancelled" };
      },
    },
  };
}

/**
 * Un mundo con el mapeo ya escrito y el PF sin suscripcion todavia.
 *
 * El `createdAt` NO es decorativo: la baja de un plan reemplazado solo se
 * dispara sobre planes ESTRICTAMENTE mas viejos que el confirmado, asi que un
 * mapeo sin fecha se comporta distinto. El mundo tiene que parecerse al real,
 * donde `recordPlan` siempre la escribe.
 */
const MUNDO = (): Store => ({
  users: { t1: { role: "trainer", displayName: "Martin" } },
  mp_plans: {
    p1: {
      uid: "t1",
      tier: "plan2",
      cycle: "monthly",
      createdAt: ts(AHORA - 60 * DIA_MS),
    },
  },
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
// LA GUARDA DE NO-REGRESION: un `pending` no pisa un entitlement pago.
//
// El caso que la motiva es el PF que CAMBIA DE PLAN. Nada impide abrir un
// checkout estando ya suscripto, asi que queda con DOS documentos en `mp_plans`
// con su uid: el viejo (`authorized`) y el nuevo (`pending` hasta que carga el
// medio de pago). El barrido recorre los dos y escribe por cada uno.
//
// Como `effective-limit` le da el limite FREE a un `pending`, sin la guarda el
// plan nuevo le bajaba el limite a 2 y `syncEntitlementsOnSubscription` le
// bloqueaba alumnos EN LA MISMA INVOCACION — mas un mail de degradacion. A
// alguien que acababa de intentar pagarnos mas.
// ---------------------------------------------------------------------------

/** El plan nuevo, abierto y todavia sin autorizar. */
const PENDIENTE: MpPreapproval = {
  ...AUTORIZADA,
  id: "p2",
  status: "pending",
  auto_recurring: { transaction_amount: 39000 },
};

/** Mundo del upgrade: plan2 vigente y un checkout de plan3 recien abierto. */
const UPGRADE = (): Store => ({
  users: {
    t1: {
      role: "trainer",
      displayName: "Martin",
      subscription: { tier: "plan2", status: "active", currentPeriodEnd: null },
    },
  },
  mp_plans: {
    p1: {
      uid: "t1", tier: "plan2", cycle: "monthly",
      createdAt: ts(AHORA - 60 * DIA_MS),
    },
    p2: {
      uid: "t1", tier: "plan3", cycle: "monthly",
      createdAt: ts(AHORA - 1 * DIA_MS),
    },
  },
});

/**
 * El mismo mundo pero con el plan NUEVO primero en el store.
 *
 * `fakeApp` recorre las claves en orden de insercion, asi que esto fuerza que el
 * barrido procese p2 antes que p1 — el orden en el que la guarda de reemplazo es
 * lo unico que separa "el PF quedo en plan3" de "el PF quedo en cancelled".
 * Firestore no promete ningun orden, y las dos ramas tienen que dar lo mismo.
 */
const UPGRADE_NUEVO_PRIMERO = (): Store => {
  const m = UPGRADE();
  const { p1, p2 } = m.mp_plans;
  m.mp_plans = { p2, p1 };
  return m;
};

describe("reconcileSubscription — un `pending` no pisa un entitlement pago", () => {
  it("el upgrade en curso NO le baja el plan al que ya paga", async () => {
    const { app, store, escrituras } = fakeApp(UPGRADE());

    const r = await reconcileSubscription(app, "p2", fakeMp(PENDIENTE));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect(escrituras).toHaveLength(0);
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(sub.status).toBe("active");
  });

  it("tambien protege a plan3, que no tiene tope y valia 0 al comparar", async () => {
    // `effectiveWeightLimit` devuelve `null` para plan3 = SIN TOPE. Comparado
    // con `>` a secas, `null` se trata como 0 y la guarda no protegia justo al
    // PF que mas paga. Es el mismo pozo que documenta `limitRank`.
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan3", status: "active", currentPeriodEnd: null,
    };
    const { app, store } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p2", fakeMp(PENDIENTE));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect((store.users.t1.subscription as Record<string, unknown>).tier)
      .toBe("plan3");
  });

  it("un `grace` tambien esta protegido: el cobro se esta reintentando", async () => {
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "grace", currentPeriodEnd: null,
    };
    const { app } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p2", fakeMp(PENDIENTE));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
  });

  it("un `cancelled` DENTRO del periodo pago tambien esta protegido", async () => {
    // Se dio de baja pero le queda mes comprado: `effective-limit` le sigue
    // dando el tier pago hasta `currentPeriodEnd`. Un `pending` de un checkout
    // nuevo no puede quitarselo antes de tiempo.
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "cancelled", currentPeriodEnd: ts(AHORA + 86_400_000),
    };
    const { app } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p2", fakeMp(PENDIENTE));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
  });

  it("sobre un PF sin suscripcion SI escribe: ahi `pending` es informacion", async () => {
    // Su limite ya era Free, asi que no le saca nada — y deja registrado que
    // hay un alta en curso. La guarda frena la REGRESION, no el `pending`.
    const { app, store } = fakeApp(MUNDO());

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...AUTORIZADA,
      status: "pending",
    }));

    expect(r.outcome).toBe("written");
    expect((store.users.t1.subscription as Record<string, unknown>).status)
      .toBe("pending");
  });

  it("un `cancelled` VENCIDO no esta protegido: su limite ya era Free", async () => {
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "cancelled", currentPeriodEnd: ts(AHORA - 1),
    };
    const { app } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p2", fakeMp(PENDIENTE));

    expect(r.outcome).toBe("written");
  });

  for (const status of ["paused", "cancelled"] as const) {
    it(`\`${status}\` SI puede bajar el limite: MP dijo algo terminal`, async () => {
      // La guarda es solo para `pending`. Un estado terminal habla de la
      // suscripcion que el PF TENIA, no de una que esta naciendo — si no
      // pudiera bajar el limite, nadie perderia nunca el plan.
      const { app, store } = fakeApp(UPGRADE());

      const r = await reconcileSubscription(app, "p1", fakeMp({
        ...AUTORIZADA,
        status,
        auto_recurring: { transaction_amount: 22000 },
      }));

      expect(r.outcome).toBe("written");
      expect((store.users.t1.subscription as Record<string, unknown>).status)
        .toBe(status);
    });
  }

  it("el BARRIDO completo deja el plan vigente, sin importar el orden", async () => {
    // El bug entero en una corrida: los dos planes del mismo uid se recorren en
    // el orden en que Firestore los devuelva, y antes ganaba el ultimo. El PF
    // terminaba en el tier que decidiera el id opaco que MP le dio al plan.
    const { app, store } = fakeApp(UPGRADE());

    const r = await reconcileAllSubscriptions(app, fakeMpMultiPlan({
      p1: { ...AUTORIZADA, auto_recurring: { transaction_amount: 22000 } },
      p2: PENDIENTE,
    }));

    expect(r.total).toBe(2);
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan2");
    expect(sub.status).toBe("active");
  });
});

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// EL COBRO DOBLE.
//
// La guarda de arriba le salvo el padron al que cambia de plan, pero tapaba la
// otra mitad: la suscripcion VIEJA seguia viva en Mercado Pago y le cobraba
// igual. Un plan2 que pasaba a plan3 terminaba con DOS debitos por mes, y nada
// en el repo las daba de baja — `MpClient` no sabia cancelar.
//
// Estos tests son los que faltaban. El harness de este archivo NUNCA tenia dos
// planes del mismo uid contestando distinto, y ese hueco es exactamente por
// donde se colo el bug: sin un segundo plan AUTORIZADO no hay cobro doble que
// ver.
//
// La pregunta que fijan no es "sabe cancelar" sino **A QUIEN y CUANDO**, que es
// donde estan los dos errores que cuestan plata: cancelar antes de que el PF
// compre, y cancelar el plan equivocado por el orden del barrido.
// ---------------------------------------------------------------------------

import { sigueViva } from "../subscriptions/mp/reconcile";

/** La suscripcion del plan viejo (plan2), viva y cobrando. */
const VIEJA: MpPreapproval = {
  id: "sub-vieja",
  status: "authorized",
  external_reference: "t1",
  next_payment_date: "2026-10-03T12:00:00.000Z",
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
};

/** La del plan nuevo (plan3), ya confirmada por MP. */
const NUEVA: MpPreapproval = {
  ...VIEJA,
  id: "sub-nueva",
  auto_recurring: { transaction_amount: 39000 },
};

/** El upgrade consumado: las DOS autorizadas al mismo tiempo. */
const DOS_VIVAS = () => ({ p1: VIEJA, p2: NUEVA });

describe("sigueViva", () => {
  it("solo `cancelled` esta muerta", () => {
    expect(sigueViva("cancelled")).toBe(false);
  });

  for (const s of ["authorized", "pending", "paused"]) {
    it(`\`${s}\` todavia puede cobrar`, () => expect(sigueViva(s)).toBe(true));
  }

  it("un estado DESCONOCIDO cuenta como viva — al reves que el resto del archivo", () => {
    // La asimetria es deliberada. En todos los demas lados no entender un dato
    // significa no escribir; acá significa CANCELAR igual, porque a esta altura
    // ya sabemos que la suscripcion quedo reemplazada. Un PUT de mas sobre algo
    // muerto es un error en el log; uno de menos es plata del PF todos los meses.
    expect(sigueViva("loquesea")).toBe(true);
    expect(sigueViva(undefined)).toBe(true);
  });
});

describe("reconcileSubscription — la baja de la suscripcion reemplazada", () => {
  it("cuando la NUEVA queda confirmada, la vieja se da de baja en MP", async () => {
    const { app } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan(DOS_VIVAS());

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.outcome).toBe("written");
    expect(r.dadosDeBaja).toBe(1);
    // El id de la SUSCRIPCION, no el del plan. Confundirlos es un 404 de MP y
    // el cobro doble intacto.
    expect(mp.bajas).toEqual(["sub-vieja"]);
  });

  it("el plan viejo queda REEMPLAZADO, no solo terminal", async () => {
    // `terminal` solo lo saca del barrido. `supersededBy` es lo que dice que la
    // baja la decidimos nosotros, y es lo unico que despues distingue su
    // `cancelled` del de un PF que se dio de baja de verdad.
    const { app, store } = fakeApp(UPGRADE());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan(DOS_VIVAS()));

    expect(store.mp_plans.p1.terminal).toBe(true);
    expect(store.mp_plans.p1.supersededBy).toBe("p2");
    // El mapeo sobrevive: sirve para auditar quien compro que.
    expect(store.mp_plans.p1.tier).toBe("plan2");
  });

  it("un plan reemplazado ya no escribe nada, ni sale a la red", async () => {
    // La otra mitad de la guarda. El `cancelled` que MP va a contestar sobre ese
    // plan es el que provocamos nosotros: escribirlo le bajaria el limite al PF
    // por el plan que acaba de DEJAR.
    const mundo = UPGRADE();
    mundo.mp_plans.p1.supersededBy = "p2";
    const { app, escrituras } = fakeApp(mundo);

    // Si saliera a la red daria `error-mp`, no `skipped-reemplazado`.
    const r = await reconcileSubscription(
      app, "p1", fakeMp(new MpApiError("no deberia preguntarse", 500)));

    expect(r.outcome).toBe("skipped-reemplazado");
    expect(escrituras).toHaveLength(0);
  });

  it("un `pending` NO da de baja nada — todavia no compro", async () => {
    // El error que este diseño evita: cancelar sobre una INTENCION. El PF que
    // abre el checkout, mira el precio y cierra la pestaña se quedaria sin el
    // plan que ya pagaba, y la baja en MP no se deshace.
    const { app } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan({ p1: VIEJA, p2: { ...NUEVA, status: "pending" } });

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect(mp.bajas).toEqual([]);
  });

  it("un `pending` que SI llega a escribirse tampoco da de baja nada", async () => {
    // El caso de arriba corta antes, en la guarda de no-regresion, asi que no
    // llega a ejercitar la condicion de la baja. Este si: el PF tiene la vieja
    // PAUSADA, o sea limite Free, asi que el `pending` de la nueva se escribe
    // sin pisar nada — y recien ahi se ve si la baja mira el estado o no.
    //
    // Y una pausada es justo la que NO hay que tocar: el PF la puede reanudar.
    // Cancelarsela porque miro otro plan es el error de actuar sobre una
    // intencion, con el agravante de que en MP no se deshace.
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "paused", currentPeriodEnd: null,
    };
    const { app } = fakeApp(mundo);
    const mp = fakeMpMultiPlan({
      p1: { ...VIEJA, status: "paused" },
      p2: { ...NUEVA, status: "pending" },
    });

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.outcome).toBe("written");
    expect(r.status).toBe("pending");
    expect(mp.bajas).toEqual([]);
  });

  // Un estado TERMINAL en el plan nuevo tampoco da de baja nada, y esto lo
  // encontró una revisión adversarial: la condición `status === "active" ||
  // status === "grace"` se podía relajar a `status !== "pending"` y la suite
  // entera quedaba en VERDE. La simetría estaba a medias — el caso `pending`
  // tenía dos tests y el terminal ninguno.
  //
  // Lo que habilitaba esa mutación es el peor defecto posible acá: el PF tiene
  // su plan2 vivo y cobrando, abre un checkout de plan3 que NO paga, MP lo deja
  // en `cancelled`, y al reconciliarlo le daríamos de baja la suscripción que SÍ
  // le estaba cobrando. Por un plan que abandonó. Y en MP no se revierte.
  for (const status of ["cancelled", "paused"] as const) {
    it(`un plan \`${status}\` NO da de baja a su hermano mas viejo`, async () => {
      const { app } = fakeApp(UPGRADE());
      const mp = fakeMpMultiPlan({
        p1: VIEJA,
        p2: { ...NUEVA, status },
      });

      const r = await reconcileSubscription(app, "p2", mp);

      expect(r.status).toBe(status);
      expect(mp.bajas).toEqual([]);
      expect(r.dadosDeBaja).toBe(0);
    });
  }

  it("un `grace` SI da de baja: hay medio de pago y la nueva va a cobrar", async () => {
    // `active` y `grace` son las dos caras del `authorized` de MP. En grace el
    // cobro se esta reintentando, pero la suscripcion existe — dejar viva la
    // vieja seria cobrarle las dos.
    const { app } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan({
      p1: VIEJA,
      p2: { ...NUEVA, summarized: { pending_charge_quantity: 1 } },
    });

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.status).toBe("grace");
    expect(mp.bajas).toEqual(["sub-vieja"]);
  });

  it("el plan MAS VIEJO nunca da de baja al mas nuevo", async () => {
    // El bug que "cancelar las otras del uid" habria introducido: el barrido
    // recorre en el orden que Firestore devuelva, asi que con las dos
    // autorizadas el viejo puede tocar primero. Si cancelara "la otra", le
    // daria de baja al PF el plan que ACABA de comprar.
    const { app } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan(DOS_VIVAS());

    const r = await reconcileSubscription(app, "p1", mp);

    expect(r.outcome).toBe("written");
    expect(r.dadosDeBaja).toBe(0);
    expect(mp.bajas).toEqual([]);
  });

  it("no se toca el plan de OTRO entrenador aunque sea mas viejo", async () => {
    const mundo = UPGRADE();
    mundo.users.t2 = { role: "trainer" };
    mundo.mp_plans.pOtro = {
      uid: "t2", tier: "plan1", cycle: "monthly",
      createdAt: ts(AHORA - 200 * DIA_MS),
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMpMultiPlan({
      ...DOS_VIVAS(),
      pOtro: { ...VIEJA, id: "sub-ajena", external_reference: "t2" },
    });

    await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual(["sub-vieja"]);
    expect(store.mp_plans.pOtro.terminal).toBeUndefined();
  });

  it("sin `createdAt` en el plan confirmado no se da de baja NADA", async () => {
    // Sin las dos fechas no hay forma de saber cual es el viejo, y adivinar es
    // cancelarle a alguien el plan que recien compro. Se prefiere el cobro
    // doble —que se ve y se devuelve— a una baja equivocada, que es terminal.
    const mundo = UPGRADE();
    delete mundo.mp_plans.p2.createdAt;
    const { app } = fakeApp(mundo);
    const mp = fakeMpMultiPlan(DOS_VIVAS());

    await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual([]);
    expect(warnSpy).toHaveBeenCalled();
  });

  it("un plan viejo TERMINAL POR ABANDONO que despues se pago SI se da de baja", async () => {
    // El agujero del filtro `terminal === true` pelado. Esta población existe y
    // el repo la construyó a propósito: `esAbandonado` marca terminal a los 30
    // días, pero el `init_point` NO VENCE, así que el PF puede encontrar la
    // pestaña vieja al día 35 y pagarla — y `reconcile-my-checkout.ts` existe
    // justamente para rescatar ese caso.
    //
    // Con el filtro pelado, ese plan viejo —vivo y cobrando— quedaba fuera de la
    // baja PARA SIEMPRE, porque el barrido tampoco lo reconcilia. Cobro doble
    // permanente, en el caso exacto que este archivo viene a cerrar.
    const mundo = UPGRADE();
    mundo.mp_plans.p1.terminal = true;
    mundo.mp_plans.p1.terminalReason = "checkout abandonado";
    const { app } = fakeApp(mundo);
    const mp = fakeMpMultiPlan(DOS_VIVAS());

    const r = await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual(["sub-vieja"]);
    expect(r.dadosDeBaja).toBe(1);
  });

  it("pero un terminal que SI es un hecho no se vuelve a tocar", async () => {
    // La otra mitad de `puedeSeguirCobrando`. Un terminal SIN motivo es la baja
    // que hizo el PF y que MP ya confirmó; uno con motivo de REEMPLAZO es una
    // baja nuestra que MP aceptó. Los dos son hechos: preguntar de nuevo es
    // gastar una llamada a MP todas las noches para siempre.
    for (const terminalDeVerdad of [
      { terminal: true },
      { terminal: true, terminalReason: "reemplazado por otro plan" },
    ]) {
      const mundo = UPGRADE();
      Object.assign(mundo.mp_plans.p1, terminalDeVerdad);
      const { app } = fakeApp(mundo);
      const mp = fakeMpMultiPlan(DOS_VIVAS());

      await reconcileSubscription(app, "p2", mp);

      expect(mp.bajas).toEqual([]);
    }
  });

  it("el plan viejo queda marcado ANTES de pedirle la baja a MP", async () => {
    // El orden es el arreglo, no un detalle. Con la marca DESPUÉS del PUT,
    // cualquier respuesta perdida —un 204, un 2xx sin body, el timeout de 10s
    // con la baja ya aplicada— dejaba la suscripción cancelada en MP y el plan
    // sin marcar. Y al día siguiente MP contesta `cancelled`, que SÍ baja el
    // límite: el downgrade sobre el que acaba de pagar.
    //
    // Se comprueba con una baja que FALLA: si igual quedó marcado, es porque se
    // escribió antes.
    const { app, store } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan(DOS_VIVAS(), {
      fallaLaBaja: new MpApiError("la respuesta no es un objeto JSON", 204),
    });

    await reconcileSubscription(app, "p2", mp);

    expect(store.mp_plans.p1.supersededBy).toBe("p2");
    // Pero NO terminal: eso es un hecho de MP, y MP no confirmó nada.
    expect(store.mp_plans.p1.terminal).toBeUndefined();
  });

  it("y por eso el `cancelled` de una baja sin confirmar ya no pisa el plan nuevo", async () => {
    // El escenario completo, que es el que duele. Corrida N: se confirma p2, se
    // manda la baja de p1 y la respuesta se pierde (MP igual la aplicó).
    // Corrida N+1: MP contesta `cancelled` por p1. Sin la marca escrita antes,
    // esa corrida escribía {plan2, cancelled} encima de {plan3, active}.
    const { app, store } = fakeApp(UPGRADE());

    // Corrida N: la baja no confirma, pero MP la aplicó igual.
    const mpN = fakeMpMultiPlan(DOS_VIVAS(), {
      fallaLaBaja: new MpApiError("timeout", 0),
    });
    await reconcileSubscription(app, "p2", mpN);

    // Corrida N+1: así ve MP el mundo — p1 cancelada de verdad.
    const r = await reconcileSubscription(app, "p1", fakeMpMultiPlan({
      p1: { ...VIEJA, status: "cancelled" },
      p2: NUEVA,
    }));

    expect(r.outcome).toBe("skipped-reemplazado");
    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan3");
    expect(sub.status).toBe("active");
  });

  it("y la baja sin confirmar converge sola: se reintenta y termina cerrando", async () => {
    // La otra mitad. El plan sigue en el barrido (no es terminal), así que
    // mañana se vuelve a intentar. Si MP ya la había cancelado, el search lo
    // dice, no se manda ningún PUT, y recién ahí se marca terminal.
    const { app, store } = fakeApp(UPGRADE());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan(DOS_VIVAS(), {
      fallaLaBaja: new MpApiError("timeout", 0),
    }));
    expect(store.mp_plans.p1.terminal).toBeUndefined();

    // Corrida siguiente: MP ya la da por cancelada.
    const mp = fakeMpMultiPlan({
      p1: { ...VIEJA, status: "cancelled" },
      p2: NUEVA,
    });
    await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual([]);
    expect(store.mp_plans.p1.terminal).toBe(true);
  });

  it("si MP rechaza la baja, el plan viejo NO se marca terminal", async () => {
    // Es la mitad util del catch: el plan sigue en el barrido y mañana se
    // reintenta. Marcarlo acá convertiria un 429 de una noche en un cobro doble
    // para siempre.
    const { app, store } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan(DOS_VIVAS(), {
      fallaLaBaja: new MpApiError("MP caido", 500),
    });

    const r = await reconcileSubscription(app, "p2", mp);

    // La suscripcion nueva SI se escribe: el PF pago y le corresponde.
    expect(r.outcome).toBe("written");
    expect(r.dadosDeBaja).toBe(0);
    expect(mp.bajas).toEqual(["sub-vieja"]);
    expect(store.mp_plans.p1.terminal).toBeUndefined();
    expect(errorSpy).toHaveBeenCalled();
  });

  it("y la reintenta la noche siguiente, aunque ya no haya nada que escribir", async () => {
    // El caso que se pierde si la baja cuelga del `written`: la suscripcion
    // nueva ya quedo escrita anoche, asi que hoy da `unchanged`. Sin esto, un
    // unico fallo transitorio dejaba el cobro doble vivo para siempre.
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan3",
      status: "active",
      currentPeriodEnd: ts(Date.parse("2026-10-03T12:00:00.000Z")),
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMpMultiPlan(DOS_VIVAS());

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.outcome).toBe("unchanged");
    expect(mp.bajas).toEqual(["sub-vieja"]);
    expect(store.mp_plans.p1.supersededBy).toBe("p2");
  });

  it("una vieja que MP ya daba por cancelada no se vuelve a cancelar", async () => {
    const { app, store } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan({
      p1: { ...VIEJA, status: "cancelled" },
      p2: NUEVA,
    });

    await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual([]);
    // Igual sale del barrido: no queda nada que cobre.
    expect(store.mp_plans.p1.terminal).toBe(true);
  });

  it("un plan viejo SIN suscripcion no se marca terminal", async () => {
    // Nunca cobro: es un checkout que el PF abrio y abandono. Pero un `[]`
    // tambien puede ser MP contestando raro, y sacarlo del barrido por eso
    // seria dejar de mirar algo que quizas si cobra. De esos se encarga
    // `esAbandonado` a los 30 dias.
    const { app, store } = fakeApp(UPGRADE());
    const mp = fakeMpMultiPlan({ p1: null, p2: NUEVA });

    await reconcileSubscription(app, "p2", mp);

    expect(mp.bajas).toEqual([]);
    expect(store.mp_plans.p1.terminal).toBeUndefined();
  });
});

describe("reconcileAllSubscriptions — el cobro doble, en una corrida entera", () => {
  /** El barrido, con los dos planes del mismo uid autorizados a la vez. */
  const barrer = async (mundo: Store) => {
    const { app, store } = fakeApp(mundo);
    const mp = fakeMpMultiPlan(DOS_VIVAS());
    const r = await reconcileAllSubscriptions(app, mp);
    return { r, store, mp };
  };

  // El orden importa y por eso se prueban los dos: Firestore no promete
  // ninguno, y cada rama rompe de una forma distinta.
  //
  //   - viejo primero: el riesgo es que el viejo cancele al nuevo.
  //   - nuevo primero: el barrido sigue con el snapshot VIEJO en la mano, va a
  //     reconciliar el plan que acabamos de dar de baja, y MP le va a contestar
  //     `cancelled`. Sin la guarda de reemplazo, la ultima escritura de la
  //     noche seria un `cancelled` encima del plan recien comprado.
  for (const [caso, mundo] of [
    ["el viejo primero", UPGRADE],
    ["el nuevo primero", UPGRADE_NUEVO_PRIMERO],
  ] as const) {
    it(`con ${caso}, el PF queda en el plan que compro y con UN solo cobro`, async () => {
      const { r, store, mp } = await barrer(mundo());

      const sub = store.users.t1.subscription as Record<string, unknown>;
      expect(sub.tier).toBe("plan3");
      expect(sub.status).toBe("active");
      // Una sola baja, y es la vieja.
      expect(mp.bajas).toEqual(["sub-vieja"]);
      expect(r.dadosDeBaja).toBe(1);
    });
  }

  it("la corrida siguiente no vuelve a preguntar por el plan reemplazado", async () => {
    const { app, store } = fakeApp(UPGRADE());

    await reconcileAllSubscriptions(app, fakeMpMultiPlan(DOS_VIVAS()));
    const segunda = await reconcileAllSubscriptions(
      app, fakeMpMultiPlan(DOS_VIVAS()));

    expect(segunda.total).toBe(1);
    expect(segunda.dadosDeBaja).toBe(0);
    expect((store.users.t1.subscription as Record<string, unknown>).tier)
      .toBe("plan3");
  });
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

describe("esAbandonado", () => {
  it("un plan recien creado NO se abandona", () => {
    expect(esAbandonado(ts(AHORA - DIA_MS), AHORA)).toBe(false);
  });

  it("a los 31 dias si", () => {
    expect(esAbandonado(ts(AHORA - 31 * DIA_MS), AHORA)).toBe(true);
  });

  it("justo en el limite de 30 dias todavia NO", () => {
    // El corte es estricto: 30 dias exactos sigue vivo. Es la direccion segura
    // — esperar de mas cuesta llamadas, cortar temprano cuesta un cobro.
    expect(esAbandonado(ts(AHORA - 30 * DIA_MS), AHORA)).toBe(false);
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
        createdAt: ts(AHORA - edadDias * DIA_MS),
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
