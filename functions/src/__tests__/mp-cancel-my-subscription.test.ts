/**
 * mp-cancel-my-subscription.test.ts — la baja, para los dos productos.
 *
 * LOCAL: el cliente de MP y el reloj entran por `deps`.
 *
 * Lo que protege, en orden de que tan caro sale:
 *
 *   1. Que nadie pueda dar de baja la suscripcion de OTRO. En MP eso no se
 *      deshace: un preapproval cancelado no se reactiva.
 *   2. Que el usuario conserve el acceso hasta el fin del periodo que ya pago.
 *      Es la promesa publicada en `terminos-suscripcion.md` §7.
 *   3. Que una falla de MP no deje el estado a medias — unas canceladas y otras
 *      no es peor que ninguna: el usuario cree que se dio de baja y le sigue
 *      llegando el cobro.
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

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  FieldValue: { serverTimestamp: () => ({ __sentinel: "now" }) },
  Timestamp: {
    fromMillis: (ms: number) => ts(ms),
    fromDate: (d: Date) => ts(d.getTime()),
  },
}));

import type { App } from "firebase-admin/app";

import {
  CANCEL_COOLDOWN_MS,
  runCancelMySubscription,
} from "../subscriptions/mp/cancel-my-subscription";
import { decideSubscriptionMail } from "../subscriptions/subscription-mail";
import { toSubscriptionState } from "../subscriptions/subscription-state";

const AHORA = Date.parse("2026-09-17T12:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;
const UID = "u1";

type Store = Record<string, Record<string, unknown>>;

/** Lee un documento del store falso, tipado. Evita un cast por asercion. */
const doc = (store: Store, col: string, id: string) =>
  (store[col]?.[id] ?? {}) as Record<string, unknown>;

/** Lee un campo-mapa de un documento. */
const mapa = (store: Store, col: string, id: string, campo: string) =>
  (doc(store, col, id)[campo] ?? {}) as Record<string, unknown>;

function fakeApp(seed: Store = {}) {
  const store: Store = {};
  for (const [c, docs] of Object.entries(seed)) {
    store[c] = { ...docs };
  }
  const escrituras: { col: string; id: string }[] = [];

  const filtrada = (col: string, filtros: [string, unknown][]) => ({
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [...filtros, [campo, valor]]),
    limit: () => filtrada(col, filtros),
    get: async () => {
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) =>
          filtros.every(([c, v]) => (d as Record<string, unknown>)[c] === v))
        .map(([id, d]) => ({ id, exists: true, data: () => d }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const coleccion = (col: string) => ({
    doc: (id: string) => ({
      get: async () => ({
        exists: store[col]?.[id] !== undefined,
        data: () => store[col]?.[id],
      }),
      set: async (data: Record<string, unknown>) => {
        store[col] = store[col] ?? {};
        store[col][id] = { ...(store[col][id] as object ?? {}), ...data };
        escrituras.push({ col, id });
      },
    }),
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [[campo, valor]]),
  });

  const app = { firestore: () => ({ collection: coleccion }) } as unknown as App;
  return { app, store, escrituras };
}

/** Un PF con un plan vivo y una suscripcion activa detras. */
const MUNDO_PF = (): Store => ({
  users: { [UID]: { role: "trainer", subscription: { tier: "plan2", status: "active" } } },
  mp_plans: {
    p1: { producto: "trainer", uid: UID, tier: "plan2", cycle: "monthly" },
  },
});

/** Un alumno con su plan vivo. */
const MUNDO_ALUMNO = (): Store => ({
  users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
  mp_plans: { a1: { producto: "athlete", uid: UID, cycle: "monthly" } },
});

function fakeMp(
  over: {
    subs?: Record<string, unknown[]>;
    fallaBusqueda?: boolean;
    fallaBaja?: boolean;
  } = {},
  nowMs = AHORA,
) {
  const canceladas: string[] = [];
  const estado: Record<string, Record<string, unknown>[]> = {};
  for (const [plan, subs] of Object.entries(over.subs ?? {})) {
    estado[plan] = subs.map((s) => ({ ...(s as object) }));
  }
  return {
    canceladas,
    deps: {
      nowMs,
      mpClient: {
        getPreapproval: async () => ({}),
        createPreapprovalPlan: async () => ({}),
        searchPreapprovalsByPlan: async (planId: string) => {
          if (over.fallaBusqueda) throw new Error("MP 503");
          return estado[planId] ?? [];
        },
        cancelPreapproval: async (id: string) => {
          if (over.fallaBaja) throw new Error("MP 500");
          canceladas.push(id);
          for (const subs of Object.values(estado)) {
            for (const s of subs) {
              if (s.id === id) s.status = "cancelled";
            }
          }
          return { id, status: "cancelled" };
        },
      },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
  };
}

/** Una suscripcion viva en MP, con fecha de proximo cobro. */
const VIVA = (id: string, monto: number, enDias = 10) => ({
  id,
  status: "authorized",
  external_reference: UID,
  next_payment_date: new Date(AHORA + enDias * DIA_MS).toISOString(),
  auto_recurring: { transaction_amount: monto },
  summarized: { pending_charge_quantity: 0 },
});

beforeEach(() => jest.clearAllMocks());

describe("la baja de un ENTRENADOR", () => {
  it("cancela en MP y devuelve hasta cuando conserva el acceso", async () => {
    const { app } = fakeApp(MUNDO_PF());
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] } });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("dada-de-baja");
    expect(r.canceladas).toBe(1);
    expect(mp.canceladas).toEqual(["sub-1"]);
    // Diez dias de acceso por delante: es la promesa del §7 de los terminos.
    expect(Date.parse(r.accesoHastaIso!)).toBe(AHORA + 10 * DIA_MS);
  });

  it("conserva el LIMITE del plan pago hasta que venza", async () => {
    // No alcanza con devolver la fecha: el derecho tiene que seguir valiendo.
    const { app, store } = fakeApp(MUNDO_PF());

    await runCancelMySubscription(
      app, UID, fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] } }).deps,
    );

    const sub = mapa(store, "users", UID, "subscription");
    expect(sub.status).toBe("cancelled");
    expect(sub.tier).toBe("plan2");
    expect((sub.currentPeriodEnd as { toMillis(): number }).toMillis())
      .toBe(AHORA + 10 * DIA_MS);
  });
});

describe("la baja de un ALUMNO", () => {
  it("el derecho sigue activo hasta que termine el periodo", async () => {
    const { app, store } = fakeApp(MUNDO_ALUMNO());
    const mp = fakeMp({ subs: { a1: [VIVA("sub-a", 3500)] } });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("dada-de-baja");
    // El punto entero: se dio de baja y SIGUE teniendo acceso.
    expect(mapa(store, "users", UID, "athleteSubscription").status)
      .toBe("active");
    expect(Date.parse(r.accesoHastaIso!)).toBe(AHORA + 10 * DIA_MS);
  });

  it("no marca el plan como terminal mientras el periodo siga corriendo", async () => {
    // El bug del PR anterior, visto desde acá: si la baja marcara terminal, el
    // barrido no volveria a mirar el plan y el derecho quedaria `active` para
    // siempre.
    const { app, store } = fakeApp(MUNDO_ALUMNO());

    await runCancelMySubscription(
      app, UID, fakeMp({ subs: { a1: [VIVA("sub-a", 3500)] } }).deps,
    );

    expect(doc(store, "mp_plans", "a1").terminal).toBeUndefined();
  });
});

describe("quien puede dar de baja QUE", () => {
  it("solo toca los planes del uid del token", async () => {
    const mundo = MUNDO_PF();
    mundo.mp_plans.ajeno = {
      producto: "trainer", uid: "otro", tier: "plan3", cycle: "annual",
    };
    const { app } = fakeApp(mundo);
    const mp = fakeMp({
      subs: { p1: [VIVA("sub-1", 22000)], ajeno: [VIVA("sub-ajena", 390000)] },
    });

    await runCancelMySubscription(app, UID, mp.deps);

    // LA asercion de seguridad del archivo. En MP esto no se deshace.
    expect(mp.canceladas).toEqual(["sub-1"]);
    expect(mp.canceladas).not.toContain("sub-ajena");
  });

  it("sin planes devuelve `sin-suscripcion` y no llama a MP", async () => {
    const { app } = fakeApp({ users: { [UID]: { role: "athlete" } } });
    const mp = fakeMp();

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("sin-suscripcion");
    expect(mp.canceladas).toEqual([]);
  });

  it("un plan sin suscripcion viva detras no es un error", async () => {
    // Pasa cuando alguien abrio un checkout y nunca lo completo: el plan
    // existe, la suscripcion no.
    const { app } = fakeApp(MUNDO_PF());

    const r = await runCancelMySubscription(app, UID, fakeMp({ subs: { p1: [] } }).deps);

    expect(r.estado).toBe("sin-suscripcion");
    expect(r.canceladas).toBe(0);
  });

  it("una suscripcion YA cancelada no se vuelve a cancelar", async () => {
    const { app } = fakeApp(MUNDO_PF());
    const mp = fakeMp({
      subs: { p1: [{ ...VIVA("sub-1", 22000), status: "cancelled" }] },
    });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(mp.canceladas).toEqual([]);
    expect(r.estado).toBe("sin-suscripcion");
  });

  it("un plan terminal por ABANDONO si se cancela", async () => {
    // `puedeSeguirCobrando` y no `terminal !== true` pelado: el terminal por
    // abandono puede tener una suscripcion viva detras, porque un `init_point`
    // no vence.
    const mundo = MUNDO_PF();
    (mundo.mp_plans.p1 as Record<string, unknown>).terminal = true;
    // El valor real de MOTIVO_ABANDONO en reconcile.ts:432. Escribirlo a mano
    // es a proposito: si alguien lo cambia alla, este test se pone rojo y avisa
    // que hay un contrato entre los dos archivos.
    (mundo.mp_plans.p1 as Record<string, unknown>).terminalReason =
      "checkout abandonado";
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] } });

    await runCancelMySubscription(app, UID, mp.deps);

    expect(mp.canceladas).toEqual(["sub-1"]);
  });
});

describe("cuando MP falla", () => {
  it("si no se puede consultar, NO se cancela nada", async () => {
    const { app } = fakeApp(MUNDO_PF());
    const mp = fakeMp({ fallaBusqueda: true });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("no-disponible");
    expect(mp.canceladas).toEqual([]);
  });

  it("si la baja falla, el derecho NO se toca", async () => {
    // El usuario sigue pagando, asi que sigue teniendo lo que pago. Escribir
    // una baja que MP no acepto seria sacarle el servicio y cobrarle igual.
    const { app, store } = fakeApp(MUNDO_PF());
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] }, fallaBaja: true });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("no-disponible");
    expect(mapa(store, "users", UID, "subscription").status).toBe("active");
  });

  it("con DOS planes, si el segundo falla corta y reporta no-disponible", async () => {
    // Dejar uno cancelado y otro no es el PEOR estado posible: el usuario cree
    // que se dio de baja y le sigue llegando un cobro. Mejor que reintente
    // entero.
    const mundo = MUNDO_PF();
    mundo.mp_plans.p2 = {
      producto: "trainer", uid: UID, tier: "plan1", cycle: "monthly",
    };
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ subs: { p1: [VIVA("s1", 22000)] }, fallaBaja: true });

    const r = await runCancelMySubscription(app, UID, mp.deps);

    expect(r.estado).toBe("no-disponible");
  });
});

describe("el cooldown", () => {
  it("dos bajas seguidas: la segunda no llama a MP", async () => {
    const { app } = fakeApp(MUNDO_PF());
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] } });

    await runCancelMySubscription(app, UID, mp.deps);
    const segunda = await runCancelMySubscription(app, UID, mp.deps);

    expect(segunda.enfriando).toBe(true);
    // Una sola baja en MP, no dos.
    expect(mp.canceladas).toEqual(["sub-1"]);
  });

  it("pasado el cooldown vuelve a mirar", async () => {
    const { app } = fakeApp(MUNDO_PF());
    await runCancelMySubscription(
      app, UID, fakeMp({ subs: { p1: [VIVA("sub-1", 22000)] } }).deps,
    );

    const despues = fakeMp(
      { subs: { p1: [] } },
      AHORA + CANCEL_COOLDOWN_MS + 1,
    );
    const r = await runCancelMySubscription(app, UID, despues.deps);

    expect(r.enfriando).toBeUndefined();
  });

  it("sin planes NO se toca el cooldown", async () => {
    // No hubo ninguna llamada a MP que valga la pena frenar, y gastarlo dejaria
    // a alguien sin poder darse de baja diez segundos despues de suscribirse.
    const { app, store } = fakeApp({ users: { [UID]: { role: "athlete" } } });

    await runCancelMySubscription(app, UID, fakeMp().deps);

    expect(store.mp_cancelaciones?.[UID]).toBeUndefined();
  });
});

describe("⚠️ la baja NO dispara un mail de degradacion", () => {
  // El punto que el plan de este epico dejo explicitamente abierto: la
  // escritura de `cancelled` dispara `syncEntitlementsOnSubscription`, que
  // llama a `decideSubscriptionMail`. ¿Le llega al PF un mail diciendole que
  // bajo de plan, el mismo dia que cancela, teniendo todavia el periodo pago?
  //
  // La respuesta es NO, y el motivo es que `decideSubscriptionMail` compara
  // LIMITES EFECTIVOS y no status — y `effectiveWeightLimit` le da a un
  // `cancelled` dentro del periodo el mismo limite que a un `active`.
  //
  // Estaba cubierto por diseño, pero no habia ningun test que lo dijera, asi
  // que alguien podia romperlo sin enterarse.

  const estadoDe = (sub: Record<string, unknown> | null) =>
    toSubscriptionState(sub === null ? {} : { subscription: sub }, UID);

  it("cancelar con el periodo VIVO no manda nada", async () => {
    const antes = estadoDe({ tier: "plan2", status: "active" });
    const despues = estadoDe({
      tier: "plan2",
      status: "cancelled",
      currentPeriodEnd: ts(AHORA + 10 * DIA_MS),
    });

    expect(decideSubscriptionMail(antes, despues, AHORA)).toBeNull();
  });

  it("pero el VENCIMIENTO si baja el limite — el contrapeso", async () => {
    // Sin este caso, un `decideSubscriptionMail` que devolviera null SIEMPRE
    // pasaria el test de arriba y nadie se enteraria de que el mail de
    // degradacion dejo de existir.
    const antes = estadoDe({ tier: "plan2", status: "active" });
    const despues = estadoDe({
      tier: "plan2",
      status: "cancelled",
      currentPeriodEnd: ts(AHORA - DIA_MS),
    });

    expect(decideSubscriptionMail(antes, despues, AHORA)).not.toBeNull();
  });
});
