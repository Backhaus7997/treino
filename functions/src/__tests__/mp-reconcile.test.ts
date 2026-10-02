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
import { decidirDiferimiento } from "../subscriptions/mp/diferir-primer-cobro";
import { MOTIVO_REEMPLAZO } from "../subscriptions/mp/motivos-terminal";
import { effectiveWeightLimit } from "../subscriptions/effective-limit";
import { toSubscriptionState } from "../subscriptions/subscription-state";

// ---------------------------------------------------------------------------

type Store = Record<string, Record<string, Record<string, unknown>>>;

function fakeApp(
  seed: Store = {},
  opts: {
    /**
     * Corre antes de CADA escritura y puede tirar: es como se reproduce una falla
     * transitoria de Firestore entre dos escrituras que no son atomicas.
     */
    alEscribir?: (col: string, id: string, data: Record<string, unknown>) => void;
  } = {},
) {
  const store: Store = seed;
  const escrituras: { col: string; id: string; data: unknown; merge: boolean }[] = [];

  const docRef = (col: string, id: string) => ({
    id,
    get: async () => ({
      exists: store[col]?.[id] !== undefined,
      data: () => store[col]?.[id],
    }),
    set: async (data: Record<string, unknown>, o?: { merge?: boolean }) => {
      opts.alEscribir?.(col, id, data);
      store[col] = store[col] ?? {};
      store[col][id] = o?.merge
        ? { ...(store[col][id] ?? {}), ...data }
        : data;
      escrituras.push({ col, id, data, merge: o?.merge === true });
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
      // Lo escribio p1. Sin la clave, el estado es de antes de que existiera y se
      // reescribe UNA vez para anotarla: ver "el evento tardio de un plan que ya
      // no manda".
      mpPlanId: "p1",
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

  it("una cuenta eliminada ya no escribe nada, ni sale a la red", async () => {
    // `deleteAccount` cancela en MP y marca los planes del usuario. El
    // `cancelled` que MP avisa enseguida por webhook no tiene a quien
    // escribirle: sin la guarda, `users/{uid}` se recrea vacio (`set` con
    // `merge`) despues de la cascada.
    const mundo = MUNDO();
    mundo.mp_plans.p1.cuentaEliminadaAtMs = AHORA;
    const { app, escrituras } = fakeApp(mundo);

    // Por el barrido: si saliera a la red daria `error-mp`.
    const r = await reconcileSubscription(
      app, "p1", fakeMp(new MpApiError("no deberia preguntarse", 500)));
    expect(r.outcome).toBe("skipped-cuenta-eliminada");

    // Por el webhook: llega con la suscripcion en mano y tampoco escribe.
    const w = await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA), AUTORIZADA);
    expect(w.outcome).toBe("skipped-cuenta-eliminada");

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
      // La escribio p2 anoche.
      mpPlanId: "p2",
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
// EL EVENTO TARDIO DE UN PLAN QUE YA NO MANDA.
//
// La guarda de reemplazo cubre la baja que decidimos NOSOTROS. La que hace el PF
// no deja `supersededBy` —`puedeSeguirCobrando` la saltea—, y el webhook TARDIO
// de ese plan (el dedupe de `mpWebhook` dura 10 minutos) pisaba el plan que el
// PF contrato despues. Lo encontro la revision del #1290.
//
// Los estados se construyen pasando por el reconciliador y no se siembran a mano:
// la clave que lee la guarda (`mpPlanId`) la tiene que haber escrito el
// reconciliador, o el test mide la fixture y no el codigo.
// ---------------------------------------------------------------------------

import {
  PlanEnDisputa,
  puedePisarAlVigente,
} from "../subscriptions/mp/reconcile";

/** Hasta cuando le dura al PF el periodo que pago con A, el plan que dio de baja. */
const FIN_DE_A = Date.parse("2026-09-20T12:00:00.000Z");

/** El proximo cobro de B, el plan con el que volvio. */
const PROXIMO_DE_B = "2026-10-07T12:00:00.000Z";

/** El PF que se fue y volvio: pA es de hace dos meses, pB lo abrio ayer. */
const VOLVIO = (tierDeB: "plan2" | "plan3"): Store => ({
  users: { t1: { role: "trainer", displayName: "Martin" } },
  mp_plans: {
    pA: {
      uid: "t1", tier: "plan2", cycle: "monthly",
      createdAt: ts(AHORA - 60 * DIA_MS),
    },
    pB: {
      uid: "t1", tier: tierDeB, cycle: "monthly",
      createdAt: ts(AHORA - 1 * DIA_MS),
    },
  },
});

/** La suscripcion de A mientras el PF la pagaba. */
const A_VIVA: MpPreapproval = {
  id: "sub-a",
  preapproval_plan_id: "pA",
  status: "authorized",
  external_reference: "t1",
  next_payment_date: new Date(FIN_DE_A).toISOString(),
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
};

/** A despues de la baja del PF. MP omite la fecha de una cancelada que pago. */
const A_DE_BAJA: MpPreapproval = {
  ...A_VIVA,
  status: "cancelled",
  next_payment_date: undefined,
};

/** B autorizada: el PF volvio a contratar. */
const B_VIVA: MpPreapproval = {
  ...A_VIVA,
  id: "sub-b",
  preapproval_plan_id: "pB",
  next_payment_date: PROXIMO_DE_B,
};

/** B despues de una baja del PF, ya pagada: sin fecha, igual que A. */
const B_DE_BAJA: MpPreapproval = {
  ...B_VIVA,
  status: "cancelled",
  next_payment_date: undefined,
};

/** B con el medio de pago todavia sin autorizar. */
const B_PENDIENTE: MpPreapproval = {
  ...B_VIVA,
  status: "pending",
  next_payment_date: undefined,
};

/** B cancelada sin haber cobrado nunca: esa SI trae fecha. */
const B_SIN_PAGAR: MpPreapproval = { ...B_VIVA, status: "cancelled" };

/** El mapa `subscription` tal como quedo, sin interpretar. */
const suscripcion = (store: Store) =>
  store.users.t1.subscription as Record<string, unknown>;

/** El limite que el PF tiene con lo que quedo escrito. `null` = sin tope. */
const limiteDe = (store: Store) =>
  effectiveWeightLimit(toSubscriptionState(store.users.t1, "t1").state, AHORA);

/**
 * Los pasos 1 y 2 del agujero, por el reconciliador de verdad: A se paga, el PF
 * la da de baja —A queda `terminal` y SIN `supersededBy`— y vuelve con B.
 */
async function seFueYVolvio(tierDeB: "plan2" | "plan3") {
  const { app, store, escrituras } = fakeApp(VOLVIO(tierDeB));
  await reconcileSubscription(app, "pA", fakeMp(A_VIVA));
  await reconcileSubscription(app, "pA", fakeMp(A_DE_BAJA));
  await reconcileSubscription(
    app, "pB", fakeMpMultiPlan({ pA: A_DE_BAJA, pB: B_VIVA }));
  return { app, store, escrituras };
}

describe("reconcileSubscription — el evento tardio de un plan que ya no manda", () => {
  it("el webhook tardio de A no pisa el `active` de B (decia «Plan dado de baja»)", async () => {
    const { app, store, escrituras } = await seFueYVolvio("plan2");
    // Por que la guarda de reemplazo no alcanzaba: la baja fue del PF, asi que A
    // quedo terminal y SIN `supersededBy`.
    expect(store.mp_plans.pA.terminal).toBe(true);
    expect(store.mp_plans.pA.supersededBy).toBeUndefined();
    const antes = escrituras.length;

    // Con la suscripcion leida por id en la mano, como llega desde `mpWebhook`.
    const r = await reconcileSubscription(app, "pA", fakeMp(A_DE_BAJA), A_DE_BAJA);

    expect(r.outcome).toBe("skipped-plan-no-vigente");
    // Nada: ni `users` ni `mp_plans`, que A ya era terminal.
    expect(escrituras.slice(antes)).toEqual([]);
    const sub = suscripcion(store);
    expect(sub).toMatchObject({ tier: "plan2", status: "active", mpPlanId: "pB" });
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(Date.parse(PROXIMO_DE_B));
  });

  it("con otro tier no le baja el cupo — ahi era el mail de degradacion", async () => {
    // Volvio con plan3, sin tope. Antes, el evento de A escribia plan2 con la
    // fecha de B: el limite caia y `syncEntitlementsOnSubscription` mandaba mail.
    const { app, store } = await seFueYVolvio("plan3");
    expect(limiteDe(store)).toBeNull();

    await reconcileSubscription(app, "pA", fakeMp(A_DE_BAJA), A_DE_BAJA);

    expect(suscripcion(store).tier).toBe("plan3");
    expect(limiteDe(store)).toBeNull();
  });

  it("si B tambien se dio de baja, A sigue sin pisar: con el mismo estado manda el mas nuevo", async () => {
    // Los dos `cancelled`, asi que no decide el estado sino `createdAt`. Antes, A
    // escribia su tier con la fecha que habia dejado B.
    const { app, store } = await seFueYVolvio("plan3");
    await reconcileSubscription(app, "pB", fakeMp(B_DE_BAJA));

    const r = await reconcileSubscription(app, "pA", fakeMp(A_DE_BAJA), A_DE_BAJA);

    expect(r.outcome).toBe("skipped-plan-no-vigente");
    expect(suscripcion(store)).toMatchObject({
      tier: "plan3", status: "cancelled", mpPlanId: "pB",
    });
  });

  // ── Lo que la guarda NO frena. Cada uno es un pago o una baja de verdad que, si
  // la guarda se pasara de rosca, no llegaria nunca a `users/{uid}`. ──

  it("el plan anotado escribe siempre: la baja de B se escribe y lo marca terminal", async () => {
    const { app, store } = await seFueYVolvio("plan3");

    const r = await reconcileSubscription(app, "pB", fakeMp(B_DE_BAJA), B_DE_BAJA);

    expect(r.outcome).toBe("written");
    expect(suscripcion(store)).toMatchObject({ status: "cancelled", mpPlanId: "pB" });
    expect(store.mp_plans.pB.terminal).toBe(true);
  });

  it("un plan MAS NUEVO pisa al anotado: el cambio de plan de siempre", async () => {
    const { app, store } = fakeApp(VOLVIO("plan3"));
    await reconcileSubscription(app, "pA", fakeMp(A_VIVA));
    const mp = fakeMpMultiPlan({ pA: A_VIVA, pB: B_VIVA });

    const r = await reconcileSubscription(app, "pB", mp);

    expect(r.outcome).toBe("written");
    expect(suscripcion(store)).toMatchObject({ tier: "plan3", mpPlanId: "pB" });
    expect(mp.bajas).toEqual(["sub-a"]);

    // Y la guarda de reemplazo sigue yendo primero: el `cancelled` que acabamos
    // de provocar en A sale como reemplazo, sin salir a la red.
    const tardio = await reconcileSubscription(
      app, "pA", fakeMp(new MpApiError("no deberia preguntarse", 500)));
    expect(tardio.outcome).toBe("skipped-reemplazado");
  });

  it("la pestaña vieja: un plan MAS VIEJO que cobra pisa a uno mas nuevo que no se pago", async () => {
    // El caso por el que la regla no puede ser solo `createdAt`. El PF abre A,
    // despues B —que llega a escribir `pending`— y al final paga la pestaña vieja
    // de A. Ordenando solo por fecha, A no podia escribir NUNCA: pagaba y no se le
    // acreditaba.
    const { app, store } = fakeApp(VOLVIO("plan3"));
    expect((await reconcileSubscription(app, "pB", fakeMp(B_PENDIENTE))).outcome)
      .toBe("written");

    const r = await reconcileSubscription(app, "pA", fakeMp(A_VIVA), A_VIVA);

    expect(r.outcome).toBe("written");
    expect(suscripcion(store)).toMatchObject({
      tier: "plan2", status: "active", mpPlanId: "pA",
    });

    // Y cuando el checkout de B se cae, su `cancelled` ya no pisa el plan que cobra.
    const caida = await reconcileSubscription(app, "pB", fakeMp(B_SIN_PAGAR), B_SIN_PAGAR);
    expect(caida.outcome).toBe("skipped-plan-no-vigente");
    expect(suscripcion(store)).toMatchObject({ tier: "plan2", status: "active" });
  });

  it("el upgrade que no se paga: su `cancelled` no pisa el plan que cobra, y queda terminal", async () => {
    // La regla es simetrica. El PF con A activo intenta pasar a B y el pago no se
    // autoriza. El `pending` ya lo frenaba la guarda de siempre; el `cancelled`
    // que viene despues no, y escribia {plan3, cancelled, fecha de B} encima de un
    // plan que sigue cobrando.
    const { app, store, escrituras } = fakeApp(VOLVIO("plan3"));
    await reconcileSubscription(app, "pA", fakeMp(A_VIVA));

    // La guarda de `pending` sigue explicando su caso: va antes que esta.
    expect((await reconcileSubscription(app, "pB", fakeMp(B_PENDIENTE))).outcome)
      .toBe("skipped-pending-no-pisa");

    const antes = escrituras.length;
    const mp = fakeMpMultiPlan({ pA: A_VIVA, pB: B_SIN_PAGAR });
    const r = await reconcileSubscription(app, "pB", mp, B_SIN_PAGAR);

    expect(r.outcome).toBe("skipped-plan-no-vigente");
    expect(suscripcion(store)).toMatchObject({
      tier: "plan2", status: "active", mpPlanId: "pA",
    });
    // La baja de B es un hecho de MP aunque no mande: se marca, y es lo UNICO que
    // se escribe. A no se toca.
    expect(escrituras.slice(antes)).toEqual([
      { col: "mp_plans", id: "pB", data: { terminal: true }, merge: true },
    ]);
    expect(mp.bajas).toEqual([]);
  });

  it("un estado de antes de la guarda (sin `mpPlanId`) se reescribe UNA vez para anotarlo", async () => {
    // Sin la clave no hay contra que comparar, y se escribe como siempre. La
    // escritura de mas es una sola: despues, sin cambios.
    const mundo = MUNDO();
    mundo.users.t1.subscription = {
      tier: "plan2",
      status: "active",
      currentPeriodEnd: ts(Date.parse("2026-10-03T12:00:00.000Z")),
    };
    const { app, store, escrituras } = fakeApp(mundo);

    expect((await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA))).outcome)
      .toBe("written");
    expect(suscripcion(store)).toMatchObject({
      tier: "plan2", status: "active", mpPlanId: "p1",
    });

    expect((await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA))).outcome)
      .toBe("unchanged");
    expect(escrituras).toHaveLength(1);
  });

  for (const orden of [["pA", "pB"], ["pB", "pA"]] as const) {
    it(`el arrepentimiento sigue cortando en el acto (${orden[0]} primero)`, async () => {
      // `cortarElAcceso` marca TODOS los planes de la cuenta y los reconcilia en el
      // orden que devuelva Firestore. El corte entra por el plan vigente; A, que
      // no manda, no le cambia el tier.
      const { app, store } = await seFueYVolvio("plan3");
      const ARREPENTIDO = AHORA - 60_000;
      store.mp_plans.pA.arrepentidoAtMs = ARREPENTIDO;
      store.mp_plans.pB.arrepentidoAtMs = ARREPENTIDO;
      const mp = fakeMpMultiPlan({ pA: A_DE_BAJA, pB: B_DE_BAJA });

      const r: Record<string, { outcome: string; accesoHastaMs?: number }> = {};
      for (const planId of orden) {
        r[planId] = await reconcileSubscription(app, planId, mp);
      }

      expect(r.pA.outcome).toBe("skipped-plan-no-vigente");
      expect(r.pB.accesoHastaMs).toBe(ARREPENTIDO);
      const sub = suscripcion(store);
      expect(sub).toMatchObject({ tier: "plan3", status: "cancelled", mpPlanId: "pB" });
      expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
        .toBe(ARREPENTIDO);
      expect(limiteDe(store)).toBe(effectiveWeightLimit(null, AHORA));
    });
  }
});

describe("puedePisarAlVigente", () => {
  const VIEJO = { planId: "pA", altaMs: AHORA - 60 * DIA_MS };
  const NUEVO = { planId: "pB", altaMs: AHORA - DIA_MS };

  it("el plan anotado se pisa a si mismo siempre, aunque traiga algo peor", () => {
    // Su baja, su pausa, su cobro rebotado: si no, nadie perderia nunca el plan.
    expect(puedePisarAlVigente(
      { ...VIEJO, status: "cancelled" }, { ...VIEJO, status: "active" },
    )).toBe(true);
  });

  const casos: [string, PlanEnDisputa, PlanEnDisputa, boolean][] = [
    ["lo que cobra le gana a lo que termino, aunque sea mas viejo",
      { ...VIEJO, status: "active" }, { ...NUEVO, status: "cancelled" }, true],
    ["lo que termino no pisa lo que cobra, aunque sea mas nuevo",
      { ...NUEVO, status: "cancelled" }, { ...VIEJO, status: "active" }, false],
    ["lo que cobra le gana a lo que nace",
      { ...VIEJO, status: "active" }, { ...NUEVO, status: "pending" }, true],
    ["lo que nace no pisa lo que cobra",
      { ...NUEVO, status: "pending" }, { ...VIEJO, status: "active" }, false],
    ["lo que nace le gana a lo que termino",
      { ...VIEJO, status: "pending" }, { ...NUEVO, status: "cancelled" }, true],
    ["`grace` vale lo mismo que `active`: decide la fecha",
      { ...VIEJO, status: "grace" }, { ...NUEVO, status: "active" }, false],
    ["`paused` vale lo mismo que `cancelled`: decide la fecha",
      { ...VIEJO, status: "paused" }, { ...NUEVO, status: "cancelled" }, false],
    ["un estado guardado que no entendemos no protege: lo pisa lo que cobra",
      { ...VIEJO, status: "active" }, { ...NUEVO, status: "loquesea" }, true],
    ["con el mismo estado, el mas nuevo pisa",
      { ...NUEVO, status: "cancelled" }, { ...VIEJO, status: "cancelled" }, true],
    ["con el mismo estado, el mas viejo no",
      { ...VIEJO, status: "cancelled" }, { ...NUEVO, status: "cancelled" }, false],
    ["sin la fecha del entrante no hay orden: se escribe como antes de la guarda",
      { ...VIEJO, altaMs: null, status: "cancelled" }, { ...NUEVO, status: "cancelled" }, true],
    ["sin la fecha del vigente, tampoco",
      { ...VIEJO, status: "cancelled" }, { ...NUEVO, altaMs: null, status: "cancelled" }, true],
    ["con la misma fecha, tampoco",
      { ...VIEJO, status: "cancelled" },
      { ...NUEVO, altaMs: VIEJO.altaMs, status: "cancelled" }, true],
  ];
  for (const [caso, entrante, vigente, esperado] of casos) {
    it(caso, () => expect(puedePisarAlVigente(entrante, vigente)).toBe(esperado));
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

// ═══════════════════════════════════════════════════════════════════════════
// El escritor del ALUMNO.
//
// El alumno no tiene tiers ni cupo: tiene un interruptor de tres estados en
// `users/{uid}.athleteSubscription.status`. Lo que sigue prueba las tres cosas
// en que su escritor NO puede copiar al del PF.
// ═══════════════════════════════════════════════════════════════════════════

/** Un mundo con un plan de ALUMNO ya mapeado y el alumno sin derecho todavia. */
const MUNDO_ALUMNO = (): Store => ({
  users: { u1: { role: "athlete", displayName: "Ana" } },
  mp_plans: {
    a1: {
      producto: "athlete",
      uid: "u1",
      cycle: "monthly",
      createdAt: ts(AHORA - 60 * DIA_MS),
    },
  },
});

const ALUMNO_AUTORIZADA: MpPreapproval = {
  id: "a1",
  status: "authorized",
  external_reference: "u1",
  next_payment_date: "2026-10-03T12:00:00.000Z",
  auto_recurring: { transaction_amount: 3500 },
  summarized: { pending_charge_quantity: 0 },
};

describe("reconcileSubscription — el alumno", () => {
  it("escribe athleteSubscription con UNA SOLA clave", async () => {
    // La asercion mas importante del bloque, y por eso es sobre las CLAVES y
    // no sobre el valor. `athletePaywallInputChanged` compara el mapa entero
    // serializado, asi que cualquier campo de mas —`updatedAt`,
    // `currentPeriodEnd`, `lastEventId`— dispara `syncAthletePaywallOnUser` en
    // CADA evento de MP, y con el paywall prendido eso paga una query a
    // `trainer_links` por alumno y por evento.
    const { app, store } = fakeApp(MUNDO_ALUMNO());

    const r = await reconcileSubscription(app, "a1", fakeMp(ALUMNO_AUTORIZADA));

    expect(r.outcome).toBe("written");
    expect(r.producto).toBe("athlete");
    expect(r.athleteStatus).toBe("active");

    const escrito = store.users.u1.athleteSubscription as Record<string, unknown>;
    expect(Object.keys(escrito)).toEqual(["status"]);
    expect(escrito.status).toBe("active");
  });

  it("NUNCA escribe `subscription` — eso le daria cupo de entrenador", async () => {
    // El modo de falla que motivo el discriminador `producto`: el escritor del
    // PF sobre un alumno no es un no-op, le da un tier con cupo de alumnos.
    const { app, store } = fakeApp(MUNDO_ALUMNO());

    await reconcileSubscription(app, "a1", fakeMp(ALUMNO_AUTORIZADA));

    expect(store.users.u1.subscription).toBeUndefined();
  });

  it("escribe con MERGE — el documento de usuario tiene el perfil entero", async () => {
    const { app, store, escrituras } = fakeApp(MUNDO_ALUMNO());

    await reconcileSubscription(app, "a1", fakeMp(ALUMNO_AUTORIZADA));

    expect(escrituras.find((e) => e.col === "users")?.merge).toBe(true);
    expect(store.users.u1.role).toBe("athlete");
    expect(store.users.u1.displayName).toBe("Ana");
  });

  it("authorized CON cobro pendiente da grace, que SIGUE otorgando", async () => {
    const { app, store } = fakeApp(MUNDO_ALUMNO());

    await reconcileSubscription(app, "a1", fakeMp({
      ...ALUMNO_AUTORIZADA,
      summarized: { pending_charge_quantity: 1 },
    }));

    expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
      .toBe("grace");
  });

  it("la fecha de fin va a mp_plans, NO a users", async () => {
    // Consecuencia directa del test de la clave unica: la fecha no puede vivir
    // en el mapa, y un campo hermano en `users/{uid}` costaria dos pines en
    // `firestore.rules`. `mp_plans` ya es CF-only.
    const { app, store } = fakeApp(MUNDO_ALUMNO());

    await reconcileSubscription(app, "a1", fakeMp(ALUMNO_AUTORIZADA));

    const plan = store.mp_plans.a1 as Record<string, unknown>;
    expect((plan.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(Date.parse("2026-10-03T12:00:00.000Z"));
  });

  describe("la baja — donde el escritor del PF NO se puede copiar", () => {
    const CANCELADA_CON_PERIODO_VIVO: MpPreapproval = {
      ...ALUMNO_AUTORIZADA,
      status: "cancelled",
      next_payment_date: new Date(AHORA + 10 * DIA_MS).toISOString(),
    };

    it("dentro del periodo pagado el derecho SIGUE activo", async () => {
      // La promesa ya publicada en `terminos-suscripcion.md` seccion 7:
      // «Conservás el acceso hasta el final del período que ya pagaste».
      const { app, store } = fakeApp(MUNDO_ALUMNO());

      const r = await reconcileSubscription(
        app, "a1", fakeMp(CANCELADA_CON_PERIODO_VIVO),
      );

      expect(r.status).toBe("cancelled");
      expect(r.athleteStatus).toBe("active");
      expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
        .toBe("active");
    });

    it("NO marca `terminal` mientras el periodo siga corriendo", async () => {
      // ESTE ES EL TEST QUE JUSTIFICA EL PR.
      //
      // El escritor del PF marca `terminal` apenas MP dice `cancelled`, y eso
      // saca el plan del barrido PARA SIEMPRE. Para el PF es inofensivo: su
      // fecha vive en `users/{uid}.subscription` y `effectiveWeightLimit` la
      // relee en cada corrida, asi que el limite cae solo.
      //
      // El alumno no tiene ese mecanismo: su derecho es un string y solo una
      // ESCRITURA puede pasarlo a `expired`. La unica escritura que queda
      // despues de la baja es la del barrido. Copiar la guarda del PF le
      // regalaba acceso PERMANENTE a todo el que se diera de baja.
      const { app, store } = fakeApp(MUNDO_ALUMNO());

      await reconcileSubscription(app, "a1", fakeMp(CANCELADA_CON_PERIODO_VIVO));

      expect((store.mp_plans.a1 as Record<string, unknown>).terminal)
        .toBeUndefined();
    });

    it("pasado el periodo expira Y marca `terminal`", async () => {
      // El contrapeso del test de arriba. Sin esto, una guarda que NUNCA
      // marcara terminal pasaria igual, y el plan se quedaria en el barrido
      // para siempre gastando una llamada diaria a MP.
      const { app, store } = fakeApp(MUNDO_ALUMNO());

      const r = await reconcileSubscription(app, "a1", fakeMp({
        ...ALUMNO_AUTORIZADA,
        status: "cancelled",
        next_payment_date: new Date(AHORA - DIA_MS).toISOString(),
      }));

      expect(r.athleteStatus).toBe("expired");
      expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
        .toBe("expired");
      expect((store.mp_plans.a1 as Record<string, unknown>).terminal).toBe(true);
    });

    it("el barrido siguiente hace el flip que la baja dejo pendiente", async () => {
      // El escenario completo, que es lo que ninguno de los tests de arriba
      // prueba por separado: baja hoy con periodo vivo, y el derecho se apaga
      // solo cuando el barrido corre despues del vencimiento.
      const { app, store } = fakeApp(MUNDO_ALUMNO());

      // Dia 1: se da de baja. Conserva el acceso.
      await reconcileSubscription(app, "a1", fakeMp(CANCELADA_CON_PERIODO_VIVO));
      expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
        .toBe("active");

      // Dia 11: el barrido vuelve a mirar el MISMO plan, con el reloj movido.
      const r = await reconcileSubscription(
        app,
        "a1",
        fakeMp(CANCELADA_CON_PERIODO_VIVO, AHORA + 11 * DIA_MS),
      );

      expect(r.athleteStatus).toBe("expired");
      expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
        .toBe("expired");
    });
  });

  it("un `pending` no pisa un derecho vigente", async () => {
    // Mismo caso real que el del PF: nada impide abrir un checkout estando ya
    // suscripto, asi que un alumno que pasa de mensual a anual queda con DOS
    // documentos en `mp_plans`. Sin esta guarda, el `pending` del plan nuevo le
    // corta las funciones a alguien que acaba de intentar pagarnos mas.
    const mundo = MUNDO_ALUMNO();
    mundo.users.u1.athleteSubscription = { status: "active" };
    const { app, store, escrituras } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "a1", fakeMp({
      ...ALUMNO_AUTORIZADA,
      status: "pending",
    }));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect((store.users.u1.athleteSubscription as Record<string, unknown>).status)
      .toBe("active");
    expect(escrituras.find((e) => e.col === "users")).toBeUndefined();
  });

  it("sin cambios no escribe nada", async () => {
    const mundo = MUNDO_ALUMNO();
    mundo.users.u1.athleteSubscription = { status: "active" };
    (mundo.mp_plans.a1 as Record<string, unknown>).currentPeriodEnd =
      ts(Date.parse("2026-10-03T12:00:00.000Z"));
    const { app, escrituras } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "a1", fakeMp(ALUMNO_AUTORIZADA));

    expect(r.outcome).toBe("unchanged");
    expect(escrituras).toEqual([]);
  });

  it("un plan de PF sigue yendo al escritor del PF", async () => {
    // El contrapeso del corte por producto: sin esto, un corte de mas mandaria
    // a TODOS al escritor del alumno y nadie se enteraria.
    const { app, store } = fakeApp(MUNDO());

    const r = await reconcileSubscription(app, "p1", fakeMp(AUTORIZADA));

    expect(r.producto).toBe("trainer");
    expect(r.athleteStatus).toBeUndefined();
    expect(store.users.t1.subscription).toBeDefined();
    expect(store.users.t1.athleteSubscription).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// EL PISO PREPAGO: lo que el PF ya pagó y el cambio de plan estaba tirando.
//
// El #1027 cerró el cobro doble, pero su guarda de reemplazo dejó un agujero al
// lado: el plan viejo queda `supersededBy` y su `cancelled` —que llevaría su
// `currentPeriodEnd`— NUNCA se escribe. Está bien que no se escriba, pisaría el
// plan nuevo. Pero con eso se perdía el único registro del período pago.
//
// El daño no es que MP no reembolse (eso es inevitable): es que TREINO dejaba
// de honrar lo que el PF pagó. Un plan3 (SIN TOPE) que baja a plan1 (7) caía a
// 7 EN EL ACTO, y `syncEntitlementsOnSubscription` le bloqueaba alumnos en la
// misma invocación, más el mail de degradación.
// ---------------------------------------------------------------------------

/** Mundo del DOWNGRADE: plan3 pago y vigente, y un checkout de plan1. */
const BAJADA = (): Store => ({
  users: {
    t1: {
      role: "trainer",
      displayName: "Martin",
      subscription: {
        tier: "plan3",
        status: "active",
        currentPeriodEnd: ts(AHORA + 90 * DIA_MS),
      },
    },
  },
  mp_plans: {
    p1: {
      uid: "t1", tier: "plan3", cycle: "annual",
      createdAt: ts(AHORA - 60 * DIA_MS),
    },
    p2: {
      uid: "t1", tier: "plan1", cycle: "monthly",
      createdAt: ts(AHORA - 1 * DIA_MS),
    },
  },
});

/** La suscripción del plan1 nuevo, ya confirmada por MP. */
const BARATA: MpPreapproval = {
  ...VIEJA,
  id: "sub-barata",
  auto_recurring: { transaction_amount: 12000 },
};

describe("reconcileSubscription — el periodo prepago no se tira", () => {
  it("el downgrade conserva el cupo de plan3 hasta que vence lo pagado", async () => {
    const { app, store } = fakeApp(BAJADA());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: VIEJA,
      p2: BARATA,
    }));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    // La verdad se escribe: paga plan1 y está activo.
    expect(sub.tier).toBe("plan1");
    expect(sub.status).toBe("active");
    // Y lo que pagó queda registrado como piso.
    expect(sub.prepaidTier).toBe("plan3");
    expect((sub.prepaidUntil as { toMillis(): number }).toMillis())
      .toBe(AHORA + 90 * DIA_MS);
  });

  it("y el limite efectivo sigue SIN TOPE, que es el punto entero", async () => {
    const { app, store } = fakeApp(BAJADA());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: VIEJA, p2: BARATA,
    }));

    const { state } = toSubscriptionState(store.users.t1, "t1");
    expect(effectiveWeightLimit(state, AHORA)).toBeNull();
    // Y cuando vence el piso, recién ahí cae a los 7 que compró.
    expect(effectiveWeightLimit(state, AHORA + 91 * DIA_MS)).toBe(7);
  });

  it("es UNA SOLA escritura de users/{uid}, no dos", async () => {
    // Cada escritura dispara `syncEntitlementsOnSubscription`. En dos, la
    // primera le bloquea alumnos y le manda el mail de degradación, y la segunda
    // lo desbloquea. Por eso el piso va en el MISMO `set`.
    const { app, escrituras } = fakeApp(BAJADA());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: VIEJA, p2: BARATA,
    }));

    expect(escrituras.filter((e) => e.col === "users")).toHaveLength(1);
  });

  it("y la baja de la vieja corre igual: el cobro doble sigue cerrado", async () => {
    const { app } = fakeApp(BAJADA());
    const mp = fakeMpMultiPlan({ p1: VIEJA, p2: BARATA });

    const r = await reconcileSubscription(app, "p2", mp);

    expect(r.dadosDeBaja).toBe(1);
    expect(mp.bajas).toEqual(["sub-vieja"]);
  });

  it("el piso se escribe aunque MP rechace la baja", async () => {
    // El piso sale de Firestore, no de la red: no depende de que la baja
    // confirme. Un 429 de MP no le puede tocar el entitlement al PF.
    const { app, store } = fakeApp(BAJADA());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan(
      { p1: VIEJA, p2: BARATA },
      { fallaLaBaja: new MpApiError("MP caido", 500) },
    ));

    expect((store.users.t1.subscription as Record<string, unknown>).prepaidTier)
      .toBe("plan3");
  });

  it("el piso SOBREVIVE la reconciliacion siguiente, que no cambia nada mas", async () => {
    // El candado contra un `set` futuro que omita los campos confiando en que el
    // merge los preserve: `merge` es superficial sobre el mapa `subscription`.
    const { app, store, escrituras } = fakeApp(BAJADA());

    await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: VIEJA, p2: BARATA,
    }));
    const escriturasTrasLaPrimera = escrituras.length;

    const r = await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: { ...VIEJA, status: "cancelled" }, p2: BARATA,
    }));

    expect(r.outcome).toBe("unchanged");
    expect(escrituras.length).toBe(escriturasTrasLaPrimera);
    expect((store.users.t1.subscription as Record<string, unknown>).prepaidTier)
      .toBe("plan3");
  });

  it("el UPGRADE no arma piso: no hay nada que conservar", async () => {
    const mundo = UPGRADE();
    mundo.users.t1.subscription = {
      tier: "plan2", status: "active", currentPeriodEnd: ts(AHORA + 30 * DIA_MS),
    };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p2", fakeMpMultiPlan(DOS_VIVAS()));

    const sub = store.users.t1.subscription as Record<string, unknown>;
    expect(sub.tier).toBe("plan3");
    expect(sub.prepaidTier).toBeNull();
  });

  it("sin `currentPeriodEnd` no hay piso, y se logea el warn", async () => {
    // Los PF sembrados a mano con el Admin SDK no lo tienen. Degradan al
    // comportamiento de siempre, pero hay que poder encontrarlos: les acabamos
    // de bajar el cupo en el acto.
    const mundo = BAJADA();
    mundo.users.t1.subscription = { tier: "plan3", status: "active" };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p2", fakeMpMultiPlan({
      p1: VIEJA, p2: BARATA,
    }));

    expect((store.users.t1.subscription as Record<string, unknown>).prepaidTier)
      .toBeNull();
    expect(warnSpy).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// LA PRUEBA DIFERIDA.
//
// Un PF dado de baja que vuelve al mismo plan con dias ya pagos abre un plan CON
// PRUEBA (`diferir-primer-cobro.ts`): se espera que MP cobre recien cuando vence
// lo que ya estaba pago (supuesto que no esta medido). Eso le pide tres cosas al
// reconciliador, y las tres vienen de MP:
//
//   - el link de un checkout no vence, asi que uno viejo pagado tarde NO puede
//     darle plan pago al PF hasta el primer cobro real;
//   - durante la prueba no se debe nada, asi que un cobro "pendiente" no es
//     `grace` (ni un mail de "no pudimos cobrar");
//   - una prueba cancelada antes de cobrar no estira el fin de periodo mas alla
//     de lo que el PF ya pago.
//
// Las reglas puras se prueban en `mp-diferir-primer-cobro.test.ts`. Acá se fija
// lo que el RECONCILIADOR hace con ellas, incluido lo que NO tiene que cambiar.
// ---------------------------------------------------------------------------

describe("reconcileSubscription: la prueba diferida", () => {
  const HORA_MS = 60 * 60 * 1000;
  /** E: hasta cuando tenia pago el periodo cuando se abrio el checkout diferido. */
  const FIN_PAGO = AHORA + 13 * DIA_MS;
  /** Autorizada hace 30 minutos: el plan se abrio hace 1 hora. */
  const AUTORIZADA_HACE_30_MIN = new Date(AHORA - 30 * 60 * 1000).toISOString();
  /**
   * El primer cobro programado de la prueba. Con dias de calendario argentino cae el
   * mismo dia que E pero a la hora en que se autorizo, o sea ANTES de la hora exacta
   * de E: en el caso real (autorizada a las 09:35 ART, E a las 11:47 ART) 2 h 12 min
   * antes. Es lo que MP devuelve como `next_payment_date` durante la prueba.
   */
  const PRIMER_COBRO = FIN_PAGO - (2 * 60 + 12) * 60 * 1000;

  /**
   * El PF dado de baja que vuelve. `p0` es el plan que pago (terminal, como lo
   * deja la baja) y `p1` el checkout diferido que abrio hace 1 hora.
   */
  const DIFERIDO = (): Store => ({
    users: {
      t1: {
        role: "trainer",
        subscription: {
          tier: "plan2",
          status: "cancelled",
          currentPeriodEnd: ts(FIN_PAGO),
        },
      },
    },
    mp_plans: {
      p0: {
        uid: "t1",
        tier: "plan2",
        cycle: "monthly",
        createdAt: ts(AHORA - 20 * DIA_MS),
        terminal: true,
      },
      p1: {
        uid: "t1",
        tier: "plan2",
        cycle: "monthly",
        createdAt: ts(AHORA - HORA_MS),
        diferidoHastaMs: FIN_PAGO,
      },
    },
  });

  /** La suscripcion de `p1` recien autorizada, en prueba: el primer cobro es unas horas antes de E. */
  const EN_PRUEBA_MP: MpPreapproval = {
    id: "sub-prueba",
    status: "authorized",
    external_reference: "t1",
    date_created: AUTORIZADA_HACE_30_MIN,
    next_payment_date: new Date(PRIMER_COBRO).toISOString(),
    auto_recurring: {
      ...AUTO_RECURRING_REAL,
      start_date: AUTORIZADA_HACE_30_MIN,
      transaction_amount: 22000,
    },
    summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
  };

  const subDe = (store: Store) =>
    store.users.t1.subscription as Record<string, unknown>;
  const finDe = (store: Store) =>
    (subDe(store).currentPeriodEnd as { toMillis(): number }).toMillis();

  // ── Autorizada a tiempo: es una prueba y no se debe nada ──

  it("a tiempo y con un cobro 'pendiente' queda active, NO grace", async () => {
    // Si MP cuenta el primer cobro programado como pendiente, el mapeo de
    // siempre diria `grace` y el PF recibiria un "no pudimos cobrar" sin que se
    // le haya intentado cobrar nada.
    const { app, store } = fakeApp(DIFERIDO());
    const deps = fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    });

    const r = await reconcileSubscription(app, "p1", deps);

    expect(r.outcome).toBe("written");
    expect(r.status).toBe("active");
    expect(subDe(store).status).toBe("active");
    expect(subDe(store).tier).toBe("plan2");
    // El proximo cobro de MP es el primer cobro de la prueba, y eso es lo que se guarda.
    expect(finDe(store)).toBe(PRIMER_COBRO);
    // Volver a suscribirse no da de baja nada: el plan anterior ya esta cancelado.
    expect(deps.bajas).toEqual([]);
    expect(r.dadosDeBaja).toBe(0);
  });

  it("el MISMO payload sin el marcador de prueba SI es grace (el control del test anterior)", async () => {
    // Es lo que prueba que es la regla de la prueba, y no otra cosa, la que
    // impide el grace.
    const mundo = DIFERIDO();
    delete mundo.mp_plans.p1.diferidoHastaMs;
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    }));

    expect(subDe(store).status).toBe("grace");
  });

  it("pasado E + 3 dias un cobro pendiente vuelve a ser grace", async () => {
    // El primer cobro ya tendria que haber salido: el aviso es verdad.
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    }, FIN_PAGO + 4 * DIA_MS));

    expect(subDe(store).status).toBe("grace");
  });

  it("un milisegundo antes del horizonte sigue siendo active", async () => {
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    }, FIN_PAGO + 3 * DIA_MS - 1));

    expect(subDe(store).status).toBe("active");
  });

  // ── Un link viejo pagado tarde ──

  /** El plan se abrio hace 4 dias y el pagador lo autorizo hace 1: 3 dias despues. */
  const LINK_VIEJO = (): { mundo: Store; mp: MpPreapproval } => {
    const mundo = DIFERIDO();
    mundo.mp_plans.p1.createdAt = ts(AHORA - 4 * DIA_MS);
    return {
      mundo,
      mp: {
        ...EN_PRUEBA_MP,
        date_created: new Date(AHORA - DIA_MS).toISOString(),
      },
    };
  };

  it("autorizada varios dias despues: pending, y NO pisa lo que el PF ya tenia pago", async () => {
    // El `init_point` no vence y MP no deja dar de baja un plan. Pagado tarde, el
    // primer cobro caeria tarde (suponiendo que la prueba corre desde la
    // autorizacion): darle plan pago al PF todo ese tiempo sin que MP haya cobrado
    // nada seria regalarlo. La guarda de `pending` le conserva lo que si pago.
    const { mundo, mp } = LINK_VIEJO();
    const { app, store, escrituras } = fakeApp(mundo);
    const deps = fakeMp(mp);

    const r = await reconcileSubscription(app, "p1", deps);

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect(r.status).toBe("pending");
    expect(escrituras).toHaveLength(0);
    expect(subDe(store).status).toBe("cancelled");
    expect(finDe(store)).toBe(FIN_PAGO);
    // No se da de baja nada en MP: el pagador autorizo de buena fe y la baja es
    // terminal.
    expect(deps.bajas).toEqual([]);
  });

  it("sin periodo pago vigente que proteger, el link viejo escribe `pending`: nada de este plan", async () => {
    // El PF ya no tiene dias pagos. La suscripcion tardia no le da plan hasta
    // que MP cobre de verdad.
    const { mundo, mp } = LINK_VIEJO();
    (mundo.users.t1.subscription as Record<string, unknown>).currentPeriodEnd =
      ts(AHORA - 1);
    const { app, store } = fakeApp(mundo);
    const deps = fakeMp(mp);

    const r = await reconcileSubscription(app, "p1", deps);

    expect(r.outcome).toBe("written");
    expect(subDe(store).status).toBe("pending");
    expect(deps.bajas).toEqual([]);
    // Y como no esta confirmada, no da de baja nada de lo anterior.
    expect(r.dadosDeBaja).toBe(0);
  });

  it("el BARRIDO tampoco se la acredita: el link viejo no cambia el estado del PF", async () => {
    const { mundo, mp } = LINK_VIEJO();
    const { app, store } = fakeApp(mundo);

    const r = await reconcileAllSubscriptions(app, fakeMp(mp));

    // p0 es terminal y no se consulta; p1 es la unica y se saltea.
    expect(r.total).toBe(1);
    expect(r.skipped).toBe(1);
    expect(r.written).toBe(0);
    expect(subDe(store).status).toBe("cancelled");
  });

  it("pagado tarde y con el primer cobro hecho, es un plan como cualquier otro", async () => {
    // Desde el primer cobro real las reglas se apagan solas: el PF esta pagando
    // este plan, y no hay prueba que cuidar.
    const { mundo, mp } = LINK_VIEJO();
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...mp,
      summarized: {
        charged_quantity: 1,
        last_charged_date: new Date(AHORA).toISOString(),
        pending_charge_quantity: 0,
      },
    }));

    expect(subDe(store).status).toBe("active");
  });

  it("con el primer cobro hecho y un cobro pendiente, es grace como siempre", async () => {
    const { mundo, mp } = LINK_VIEJO();
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...mp,
      summarized: { charged_quantity: 1, pending_charge_quantity: 1 },
    }));

    expect(subDe(store).status).toBe("grace");
  });

  // ── Cancelada durante la prueba: el PF solo pago hasta E ──

  /**
   * El PF autorizo el plan diferido y despues lo cancelo, antes del primer cobro.
   * Mientras estaba en prueba el reconciliador le escribio `active` con el
   * proximo cobro de MP (el primer cobro de la prueba, unas horas antes de E): eso
   * es lo que hay guardado.
   */
  const CANCELA_EN_PRUEBA = (): Store => {
    const mundo = DIFERIDO();
    mundo.users.t1.subscription = {
      tier: "plan2",
      status: "active",
      currentPeriodEnd: ts(PRIMER_COBRO),
    };
    return mundo;
  };

  const CANCELADA_MP: MpPreapproval = {
    ...EN_PRUEBA_MP,
    status: "cancelled",
    // MP omite la fecha de una cancelada que cobro; de una que NO cobro, la trae.
    next_payment_date: undefined,
  };

  it("cancelada sin fecha de MP: conserva hasta E, no hasta el primer cobro guardado (antes de E)", async () => {
    // Lo guardado es la fecha del primer cobro, que ya no va a ocurrir, y cae unas
    // horas ANTES de E: cortar ahi le sacaria al PF horas de un periodo que ya pago.
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    const r = await reconcileSubscription(app, "p1", fakeMp(CANCELADA_MP));

    expect(subDe(store).status).toBe("cancelled");
    expect(finDe(store)).toBe(FIN_PAGO);
    expect(r.accesoHastaMs).toBe(FIN_PAGO);
    expect(store.mp_plans.p1.terminal).toBe(true);
  });

  it("cancelada sin nada guardado: ni el mes derivado del alta lo estira mas alla de E", async () => {
    // El agujero de la cascada: sin fecha de MP ni guardada, `resolverFinDePeriodo`
    // deriva alta + un periodo entero, o sea un mes que nunca se pago.
    const mundo = CANCELA_EN_PRUEBA();
    mundo.users.t1.subscription = { tier: "plan2", status: "active" };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(CANCELADA_MP));

    // Sin el tope hubiera sido el alta + 1 mes (el test de regresion de abajo
    // fija que esa es la cuenta de un plan normal).
    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("cancelada CON una fecha de MP pasada de E (la del primer cobro, si cae despues): se acota a E", async () => {
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      next_payment_date: new Date(FIN_PAGO + DIA_MS).toISOString(),
    }));

    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("cancelada CON la fecha del primer cobro unas horas ANTES de E: conserva hasta E", async () => {
    // El caso real: MP trae el primer cobro que no ocurrio, 2 h 12 min antes de E. El
    // PF pago hasta E con el plan anterior, y su acceso no se corta antes.
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      next_payment_date: new Date(PRIMER_COBRO).toISOString(),
    }));

    expect(subDe(store).status).toBe("cancelled");
    expect(finDe(store)).toBe(FIN_PAGO);
    expect(r.accesoHastaMs).toBe(FIN_PAGO);
  });

  it("cancelada con una fecha MUY anterior a E (5 dias): se respeta, no la explica ningun calendario", async () => {
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      next_payment_date: new Date(FIN_PAGO - 5 * DIA_MS).toISOString(),
    }));

    expect(finDe(store)).toBe(FIN_PAGO - 5 * DIA_MS);
  });

  it("cancelada sin fecha por ningun camino: E, no `null` (que le sacaria el plan en el acto)", async () => {
    const mundo = CANCELA_EN_PRUEBA();
    delete mundo.users.t1.subscription;
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      auto_recurring: null,
    }));

    expect(subDe(store).status).toBe("cancelled");
    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("pausada durante la prueba se acota igual", async () => {
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      status: "paused",
      next_payment_date: new Date(FIN_PAGO + 20 * DIA_MS).toISOString(),
    }));

    expect(subDe(store).status).toBe("paused");
    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("pausada con el primer cobro unas horas ANTES de E tambien conserva hasta E", async () => {
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      status: "paused",
      next_payment_date: new Date(PRIMER_COBRO).toISOString(),
    }));

    expect(subDe(store).status).toBe("paused");
    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("el arrepentimiento conserva su precedencia: su instante gana sobre el tope", async () => {
    // Quien se arrepintio pierde el acceso en ese instante; el tope no lo
    // adelanta ni lo atrasa. Aca el arrepentimiento es DESPUES de E a proposito:
    // si el tope aplicara, el fin quedaria en E.
    const mundo = CANCELA_EN_PRUEBA();
    mundo.mp_plans.p1.arrepentidoAtMs = FIN_PAGO + 2 * DIA_MS;
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(CANCELADA_MP));

    expect(finDe(store)).toBe(FIN_PAGO + 2 * DIA_MS);
  });

  it("cancelada DESPUES del primer cobro: no se acota, es un plan que se pago", async () => {
    // El PF pago este plan. Su fin ya no es "hasta E" sino lo que MP cobro, y
    // acotarlo a E le sacaria dias que si pago.
    const mundo = CANCELA_EN_PRUEBA();
    mundo.users.t1.subscription = {
      tier: "plan2",
      status: "active",
      currentPeriodEnd: ts(FIN_PAGO + 25 * DIA_MS),
    };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      summarized: {
        charged_quantity: 1,
        last_charged_date: new Date(PRIMER_COBRO).toISOString(),
        pending_charge_quantity: 0,
      },
    }));

    expect(finDe(store)).toBe(FIN_PAGO + 25 * DIA_MS);
  });

  // ── Lo que NO cambia: un plan sin marcador se lee exactamente como antes ──

  it("REGRESION: un plan normal autorizado 'tarde' sigue siendo active", async () => {
    // Sin `diferidoHastaMs` la ventana de autorizacion no existe: es el caso de
    // todos los PF que no vuelven de una baja, y el de TODOS los planes que ya
    // hay en produccion.
    const { mundo, mp } = LINK_VIEJO();
    delete mundo.mp_plans.p1.diferidoHastaMs;
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(mp));

    expect(subDe(store).status).toBe("active");
  });

  it("REGRESION: un plan normal cancelado no se acota: lo deriva la cascada de siempre", async () => {
    const mundo = CANCELA_EN_PRUEBA();
    delete mundo.mp_plans.p1.diferidoHastaMs;
    mundo.users.t1.subscription = { tier: "plan2", status: "active" };
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(CANCELADA_MP));

    // Alta + 1 mes, tal cual `resolverFinDePeriodo`: mas alla de E.
    expect(finDe(store)).toBeGreaterThan(FIN_PAGO);
    expect(finDe(store))
      .toBe(finDePeriodoDesdeAltaMs(EN_PRUEBA_MP.auto_recurring));
  });

  it("un `diferidoHastaMs` que no es un numero deja el plan como uno normal", async () => {
    // El documento es de Firestore: "lo escribimos nosotros" no es una garantia.
    const { mundo, mp } = LINK_VIEJO();
    mundo.mp_plans.p1.diferidoHastaMs = "mañana";
    const { app, store } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(mp));

    expect(subDe(store).status).toBe("active");
  });

  it("un plan de ALUMNO nunca pasa por estas reglas", async () => {
    // El checkout del alumno no escribe el marcador, pero aunque alguien lo
    // pusiera el corte por producto va antes: el alumno se lee con su escritor.
    const { app, store } = fakeApp({
      users: { u1: { role: "athlete" } },
      mp_plans: {
        a1: {
          producto: "athlete",
          uid: "u1",
          cycle: "monthly",
          createdAt: ts(AHORA - 4 * DIA_MS),
          diferidoHastaMs: FIN_PAGO,
        },
      },
    });

    const r = await reconcileSubscription(app, "a1", fakeMp({
      id: "sub-alumno",
      status: "authorized",
      external_reference: "u1",
      date_created: new Date(AHORA - DIA_MS).toISOString(),
      next_payment_date: new Date(AHORA + 30 * DIA_MS).toISOString(),
      auto_recurring: { transaction_amount: 4500 },
      summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
    }));

    expect(r.producto).toBe("athlete");
    expect(r.athleteStatus).toBe("active");
    expect(store.users.u1.athleteSubscription).toEqual({ status: "active" });
    expect(store.users.u1.subscription).toBeUndefined();
  });

  // ── Una autorizacion de $0 no es un cobro: las reglas de la prueba siguen ──
  //
  // MP podria reportar la autorizacion de la prueba como `charged_quantity >= 1`
  // con `charged_amount: 0` (no esta medido). Si contara como un pago, las reglas
  // se apagarian antes de que MP haya cobrado un peso.

  const AUTORIZACION_EN_CERO = {
    charged_quantity: 1,
    charged_amount: 0,
    pending_charge_quantity: 1,
  };

  it("a tiempo y con una autorizacion de $0 queda active, NO grace", async () => {
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: AUTORIZACION_EN_CERO,
    }));

    expect(subDe(store).status).toBe("active");
  });

  it("un link viejo con una autorizacion de $0 sigue siendo pending", async () => {
    const { mundo, mp } = LINK_VIEJO();
    const { app, escrituras } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p1", fakeMp({
      ...mp,
      summarized: AUTORIZACION_EN_CERO,
    }));

    expect(r.outcome).toBe("skipped-pending-no-pisa");
    expect(escrituras).toHaveLength(0);
  });

  it("cancelada con una autorizacion de $0 se acota igual a E", async () => {
    const { app, store } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      summarized: AUTORIZACION_EN_CERO,
    }));

    expect(finDe(store)).toBe(FIN_PAGO);
  });

  it("el mismo payload con un monto POSITIVO es un cobro real: las reglas se apagan", async () => {
    // El control del test anterior: es el monto, y no otra cosa, lo que decide.
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { ...AUTORIZACION_EN_CERO, charged_amount: 22000 },
    }));

    expect(subDe(store).status).toBe("grace");
  });

  // ── Los warns: lo que podria dejar a alguien sin plan o con plan gratis ──

  const HORIZONTE = FIN_PAGO + 3 * DIA_MS;

  it("autorizada fuera de ventana: WARN (no info), con el plan y la fecha", async () => {
    // Deja sin el plan a alguien que autorizo un pago: tiene que poder verse.
    const { mundo, mp } = LINK_VIEJO();
    const { app } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(mp));

    expect(warnSpy).toHaveBeenCalledWith(
      "mp/reconcile: prueba diferida autorizada fuera de ventana, se trata " +
        "como pending",
      expect.objectContaining({
        planId: "p1",
        uid: "t1",
        mpStatus: "authorized",
        desde: "active",
        hacia: "pending",
        diferidoHastaIso: new Date(FIN_PAGO).toISOString(),
        autorizadaEn: mp.date_created,
      }),
    );
  });

  it("prueba vencida sin ningun cobro ni cobro pendiente: WARN de posible acceso gratis", async () => {
    // Pasado E + 3 dias, a tiempo, sin cobro exitoso y sin cobro pendiente: el
    // mapeo de siempre deja `active`, o sea plan pago sin que MP haya cobrado ni
    // intentado cobrar nada. No se corrige (no hay evidencia de error) pero se avisa.
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
    }, HORIZONTE));

    expect(subDe(store).status).toBe("active");
    expect(warnSpy).toHaveBeenCalledWith(
      "mp/reconcile: prueba diferida vencida sin ningun cobro exitoso ni cobro " +
        "pendiente, posible acceso gratis",
      expect.objectContaining({
        planId: "p1",
        uid: "t1",
        diferidoHastaIso: new Date(FIN_PAGO).toISOString(),
        horizonteIso: new Date(HORIZONTE).toISOString(),
      }),
    );
  });

  it("un milisegundo antes del horizonte NO avisa: todavia es una prueba", async () => {
    const { app } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
    }, HORIZONTE - 1));

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("vencida PERO con un cobro pendiente es grace, y no avisa de acceso gratis", async () => {
    // El caso normal de un cobro que rebota: ya lo cubre `grace`.
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    }, HORIZONTE));

    expect(subDe(store).status).toBe("grace");
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("vencida con una autorizacion de $0 tambien avisa: sigue sin haber un cobro real", async () => {
    const { app } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 1, charged_amount: 0, pending_charge_quantity: 0 },
    }, HORIZONTE));

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("posible acceso gratis"),
      expect.anything(),
    );
  });

  it("vencida pero con el primer cobro hecho NO avisa: es un plan como cualquier otro", async () => {
    const { app } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 1, charged_amount: 22000, pending_charge_quantity: 0 },
    }, HORIZONTE));

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("a tiempo y en prueba no avisa nada: solo se ajusta el estado de grace a active", async () => {
    const { app } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    }));

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("un plan normal nunca dispara estos avisos", async () => {
    // Ni con el mismo payload que una autorizacion tardia, ni vencido: sin
    // `diferidoHastaMs` las reglas no existen.
    const { mundo, mp } = LINK_VIEJO();
    delete mundo.mp_plans.p1.diferidoHastaMs;
    const { app } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp(mp, HORIZONTE + 30 * DIA_MS));

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("una prueba cancelada no dispara el aviso de vencida: MP ya dijo algo terminal", async () => {
    const { app } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp(CANCELADA_MP, HORIZONTE));

    expect(warnSpy).not.toHaveBeenCalledWith(
      expect.stringContaining("posible acceso gratis"),
      expect.anything(),
    );
  });

  // ── MP ignoro o acorto la prueba: el PF cobro antes de tiempo y pago dos veces ──
  //
  // Es la medicion del supuesto central del diferimiento. La suscripcion de un plan
  // con prueba cobro cuando todavia faltaba mas de dos dias para el fin de lo que
  // el PF tenia pago: pago ese periodo dos veces. El margen de dos dias es ancho a
  // proposito: el primer cobro esperado cae el mismo dia que E, hasta casi un dia
  // antes de su hora exacta, y si MP cuenta en su propio calendario (no esta
  // medido) puede caer un dia de calendario mas temprano todavia.

  const COBRO_ANTES_DE_TIEMPO = {
    charged_quantity: 1,
    charged_amount: 22000,
    last_charged_date: AUTORIZADA_HACE_30_MIN,
    last_charged_amount: 22000,
    pending_charge_quantity: 0,
  };
  const MENSAJE_COBRO_DOBLE =
    "mp/reconcile: un plan con prueba YA cobro antes de que venza lo que el PF " +
    "tenia pago, MP ignoro o acorto la prueba y el PF pago dos veces";

  it("un plan con prueba que ya cobro cuando faltan 13 dias: WARN de cobro doble", async () => {
    const { app, store } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: COBRO_ANTES_DE_TIEMPO,
    }));

    expect(warnSpy).toHaveBeenCalledWith(
      MENSAJE_COBRO_DOBLE,
      expect.objectContaining({
        planId: "p1",
        uid: "t1",
        mpStatus: "authorized",
        cobros: 1,
        diferidoHastaIso: new Date(FIN_PAGO).toISOString(),
        nowIso: new Date(AHORA).toISOString(),
      }),
    );
    // No cambia el estado: un plan que ya cobro se lee como cualquier otro.
    expect(subDe(store).status).toBe("active");
  });

  it("el borde: a exactamente dos dias de E todavia no avisa, un milisegundo antes si", async () => {
    for (const [nowMs, avisa] of [
      [FIN_PAGO - 2 * DIA_MS, false],
      [FIN_PAGO - 2 * DIA_MS - 1, true],
    ] as const) {
      warnSpy.mockClear();
      const { app } = fakeApp(DIFERIDO());

      await reconcileSubscription(app, "p1", fakeMp({
        ...EN_PRUEBA_MP,
        summarized: COBRO_ANTES_DE_TIEMPO,
      }, nowMs));

      expect(warnSpy.mock.calls.some((c) => c[0] === MENSAJE_COBRO_DOBLE))
        .toBe(avisa);
    }
  });

  it("el primer cobro esperado, unas horas antes de E o en un dia y medio, NO avisa", async () => {
    // Antes el margen era de un dia justo, a un milisegundo de un cobro legitimo.
    // PRIMER_COBRO es el del caso real (2 h 12 min antes de E); los otros dos son el
    // peor caso del modelo (23 h 58 min antes) y un dia y medio, entre los dos margenes.
    for (const nowMs of [
      PRIMER_COBRO,
      FIN_PAGO - (DIA_MS - 2 * 60_000),
      FIN_PAGO - 1.5 * DIA_MS,
    ]) {
      warnSpy.mockClear();
      const { app } = fakeApp(DIFERIDO());

      await reconcileSubscription(app, "p1", fakeMp({
        ...EN_PRUEBA_MP,
        summarized: COBRO_ANTES_DE_TIEMPO,
      }, nowMs));

      expect(warnSpy).not.toHaveBeenCalledWith(MENSAJE_COBRO_DOBLE, expect.anything());
    }
  });

  it("el primer cobro que se esperaba (en E o despues) NO avisa", async () => {
    for (const nowMs of [FIN_PAGO, FIN_PAGO + 2 * DIA_MS]) {
      warnSpy.mockClear();
      const { app } = fakeApp(DIFERIDO());

      await reconcileSubscription(app, "p1", fakeMp({
        ...EN_PRUEBA_MP,
        summarized: COBRO_ANTES_DE_TIEMPO,
      }, nowMs));

      expect(warnSpy).not.toHaveBeenCalledWith(MENSAJE_COBRO_DOBLE, expect.anything());
    }
  });

  it("avisa tambien si despues el PF cancelo: ya pago dos veces", async () => {
    const { app } = fakeApp(CANCELA_EN_PRUEBA());

    await reconcileSubscription(app, "p1", fakeMp({
      ...CANCELADA_MP,
      summarized: COBRO_ANTES_DE_TIEMPO,
    }));

    expect(warnSpy).toHaveBeenCalledWith(MENSAJE_COBRO_DOBLE, expect.anything());
  });

  it("una autorizacion de $0 no es un cobro: no avisa", async () => {
    const { app } = fakeApp(DIFERIDO());

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: { charged_quantity: 1, charged_amount: 0, pending_charge_quantity: 0 },
    }));

    expect(warnSpy).not.toHaveBeenCalledWith(MENSAJE_COBRO_DOBLE, expect.anything());
  });

  it("un plan normal, que cobra al autorizar, nunca avisa", async () => {
    // Sin `diferidoHastaMs` no hay prueba que MP pueda haber ignorado.
    const mundo = DIFERIDO();
    delete mundo.mp_plans.p1.diferidoHastaMs;
    const { app } = fakeApp(mundo);

    await reconcileSubscription(app, "p1", fakeMp({
      ...EN_PRUEBA_MP,
      summarized: COBRO_ANTES_DE_TIEMPO,
    }));

    expect(warnSpy).not.toHaveBeenCalledWith(MENSAJE_COBRO_DOBLE, expect.anything());
  });
});

// ---------------------------------------------------------------------------
// La baja del PF deja el plan listo para ser evidencia de un pago.
//
// El diferimiento solo mira planes `terminal`: es lo que distingue un plan que tuvo
// una suscripcion de verdad de un checkout que nadie pago. Hasta aca TODAS las
// fixtures del diferimiento escribian `terminal: true` a mano, asi que si el
// reconciliador dejara de escribirlo (o le agregara un motivo que el filtro
// descarta) el diferimiento se apagaria sin que ningun test se pusiera rojo.
//
// Estos corren el reconciliador de verdad y despues `decidirDiferimiento` de verdad
// contra el MISMO store.
// ---------------------------------------------------------------------------

/** El mapa `subscription` que dejo el reconciliador, sin interpretar. */
const subDe = (store: Store) =>
  store.users.t1.subscription as Record<string, unknown>;

describe("reconcile + diferimiento: la baja del PF deja el plan listo para contar como pago", () => {
  const FIN_X = Date.parse("2026-09-20T12:00:00.000Z");
  const COBRO_DE_AGOSTO = "2026-08-20T12:00:00.000Z";

  /** Un PF activo que pago el 20/8 con su plan p0. Nada marcado `terminal`: eso lo hace la baja. */
  const PF_QUE_PAGA = (): Store => ({
    users: {
      t1: {
        role: "trainer",
        subscription: {
          tier: "plan2",
          status: "active",
          currentPeriodEnd: ts(FIN_X),
          prepaidTier: null,
          prepaidUntil: null,
          // Lo escribio p0, y el reconciliador lo anota.
          mpPlanId: "p0",
        },
      },
    },
    mp_plans: {
      p0: {
        uid: "t1",
        tier: "plan2",
        cycle: "monthly",
        createdAt: ts(AHORA - 18 * DIA_MS),
      },
    },
  });

  /** La suscripcion de p0 despues de que el PF se dio de baja. MP omite la fecha de una cancelada que pago. */
  const BAJA_DE_P0: MpPreapproval = {
    id: "s0",
    status: "cancelled",
    external_reference: "t1",
    date_created: COBRO_DE_AGOSTO,
    next_payment_date: undefined,
    auto_recurring: {
      ...AUTO_RECURRING_REAL,
      start_date: COBRO_DE_AGOSTO,
      transaction_amount: 22000,
    },
    summarized: {
      charged_quantity: 1,
      charged_amount: 22000,
      last_charged_date: COBRO_DE_AGOSTO,
      last_charged_amount: 22000,
      pending_charge_quantity: 0,
    },
  };

  /**
   * `decidirDiferimiento` tal como lo arma `create-preapproval.ts`, pero leyendo del
   * store que acaba de escribir el reconciliador: los planes de la cuenta y el
   * documento del usuario. Lo unico que viene de afuera es lo que dice MP.
   */
  const decidir = (store: Store, deps: ReconcileDeps, userData = store.users.t1) =>
    decidirDiferimiento({
      uid: "t1",
      tier: "plan2",
      userData,
      nowMs: AHORA,
      habilitado: true,
      leerPlanes: async () =>
        Object.entries(store.mp_plans)
          .filter(([, datos]) => datos.uid === "t1")
          .map(([id, data]) => ({ id, data })),
      leerSuscripciones: (planId) => deps.mpClient.searchPreapprovalsByPlan(planId),
    });

  it("la baja deja el plan `terminal` SIN motivo, y el siguiente checkout lleva prueba", async () => {
    const { app, store } = fakeApp(PF_QUE_PAGA());
    const deps = fakeMp(BAJA_DE_P0);

    const r = await reconcileSubscription(app, "p0", deps);

    expect(r.outcome).toBe("written");
    expect(subDe(store).status).toBe("cancelled");
    // Lo que escribe el reconciliador, sin ayuda de la fixture.
    expect(store.mp_plans.p0.terminal).toBe(true);
    expect(store.mp_plans.p0).not.toHaveProperty("terminalReason");

    // Y de ahi sale el diferimiento: el plan cuenta como evidencia de pago.
    expect(await decidir(store, deps))
      .toEqual({ diferir: true, diferidoHastaMs: FIN_X });
  });

  it("si el reconciliador dejara de marcar la baja, el diferimiento NO se dispararia (el control)", async () => {
    // Prueba que el test anterior depende de lo que escribe el reconciliador: el
    // mismo mundo con el plan sin marcar no difiere.
    const { app, store } = fakeApp(PF_QUE_PAGA());
    const deps = fakeMp(BAJA_DE_P0);
    await reconcileSubscription(app, "p0", deps);
    delete store.mp_plans.p0.terminal;

    expect(await decidir(store, deps))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("una falla ENTRE la escritura del usuario y la del plan se repara en la corrida siguiente", async () => {
    // El bug: la marca estaba adentro del `if (!sinCambios)`. Una falla entre las
    // dos escrituras dejaba el usuario escrito y el plan sin marcar, y la corrida
    // siguiente veia `sinCambios` y nunca la reintentaba: el plan que pago dejaba
    // de contar como evidencia PARA SIEMPRE.
    let fallo = false;
    const { app, store } = fakeApp(PF_QUE_PAGA(), {
      alEscribir: (col, id, data) => {
        if (!fallo && col === "mp_plans" && id === "p0" && data.terminal === true) {
          fallo = true;
          throw new Error("UNAVAILABLE");
        }
      },
    });
    const deps = fakeMp(BAJA_DE_P0);

    await expect(reconcileSubscription(app, "p0", deps)).rejects.toThrow("UNAVAILABLE");
    // El estado exacto que dejaba el bug: el usuario escrito, el plan sin marcar.
    expect(subDe(store).status).toBe("cancelled");
    expect(store.mp_plans.p0.terminal).toBeUndefined();
    expect(await decidir(store, deps))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });

    const r = await reconcileSubscription(app, "p0", deps);

    expect(r.outcome).toBe("unchanged");
    expect(store.mp_plans.p0.terminal).toBe(true);
    expect(await decidir(store, deps))
      .toEqual({ diferir: true, diferidoHastaMs: FIN_X });
  });

  it("la marca es idempotente: un plan que ya es terminal no se vuelve a escribir", async () => {
    // Ya esta marcado y el usuario ya tiene la baja: no hay nada que escribir, ni en
    // `users` ni en `mp_plans`.
    const mundo = PF_QUE_PAGA();
    (mundo.users.t1.subscription as Record<string, unknown>).status = "cancelled";
    (mundo.mp_plans.p0 as Record<string, unknown>).terminal = true;
    const { app, escrituras } = fakeApp(mundo);

    const r = await reconcileSubscription(app, "p0", fakeMp(BAJA_DE_P0));

    expect(r.outcome).toBe("unchanged");
    expect(escrituras).toHaveLength(0);
  });

  it("solo la baja marca: un plan que MP no dio de baja queda sin terminal", async () => {
    // `terminal` saca al plan del barrido para siempre. Marcarlo en cualquier otro
    // estado dejaria de mirar una suscripcion que sigue viva y cobrando.
    const { app, store } = fakeApp(PF_QUE_PAGA());

    await reconcileSubscription(app, "p0", fakeMp({
      ...BAJA_DE_P0,
      status: "authorized",
      next_payment_date: new Date(FIN_X).toISOString(),
    }));

    expect(store.mp_plans.p0.terminal).toBeUndefined();
  });

  it("el barrido de la noche tambien la repara, y despues el plan sale del barrido", async () => {
    const mundo = PF_QUE_PAGA();
    (mundo.users.t1.subscription as Record<string, unknown>).status = "cancelled";
    const { app, store } = fakeApp(mundo);
    const deps = fakeMp(BAJA_DE_P0);

    const primera = await reconcileAllSubscriptions(app, deps);

    expect(primera.total).toBe(1);
    expect(primera.unchanged).toBe(1);
    expect(store.mp_plans.p0.terminal).toBe(true);

    // Ya marcado: el barrido no vuelve a visitarlo.
    const segunda = await reconcileAllSubscriptions(app, deps);
    expect(segunda.total).toBe(0);
  });

  // ── Un plan pagado que despues se reemplazo tambien tiene que contar ──

  it("un plan pagado que se reemplazo queda `terminal` con MOTIVO_REEMPLAZO y SIGUE dando evidencia", async () => {
    // p0 (pago el 20/8) sigue vivo cuando el PF compra p1: al confirmarse p1, el
    // reconciliador da de baja p0 y lo marca terminal CON motivo. Ese plan pagado
    // es la evidencia del pago, y el filtro no puede descartarlo.
    const mundo = PF_QUE_PAGA();
    mundo.mp_plans.p1 = {
      uid: "t1",
      tier: "plan2",
      cycle: "annual",
      createdAt: ts(AHORA - DIA_MS),
    };
    const { app, store } = fakeApp(mundo);
    const deps = fakeMpMultiPlan({
      p0: {
        ...BAJA_DE_P0,
        status: "authorized",
        next_payment_date: new Date(FIN_X).toISOString(),
      },
      p1: {
        id: "s1",
        status: "authorized",
        external_reference: "t1",
        next_payment_date: new Date(AHORA + 365 * DIA_MS).toISOString(),
        auto_recurring: { transaction_amount: 220000 },
        summarized: { charged_quantity: 1, charged_amount: 220000, pending_charge_quantity: 0 },
      },
    });

    const r = await reconcileSubscription(app, "p1", deps);

    expect(r.dadosDeBaja).toBe(1);
    expect(deps.bajas).toEqual(["s0"]);
    expect(store.mp_plans.p0.terminal).toBe(true);
    // El motivo que escribe el reconciliador es la constante compartida.
    expect(store.mp_plans.p0.terminalReason).toBe(MOTIVO_REEMPLAZO);

    // El PF cancela el plan nuevo (p1 sigue sin cerrar en este store): el unico
    // plan que puede ser evidencia es p0, el reemplazado.
    const cancelado = {
      subscription: { tier: "plan2", status: "cancelled", currentPeriodEnd: ts(FIN_X) },
    };
    expect(await decidir(store, deps, cancelado))
      .toEqual({ diferir: true, diferidoHastaMs: FIN_X });
  });
});
