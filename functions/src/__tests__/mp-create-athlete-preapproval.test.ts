/**
 * mp-create-athlete-preapproval.test.ts — el checkout del ALUMNO.
 *
 * LOCAL, sin emulador y sin red: el cliente de MP y el reloj entran por `deps`.
 *
 * Lo que este archivo protege, en orden de que tan caro sale si se rompe:
 *
 *   1. Que el monto NUNCA salga del body. Es la propiedad que sostiene la
 *      exencion de App Check de este callable.
 *   2. Que la URL de retorno la arme el servidor. Un `backUrl` que venga del
 *      cliente es un open redirect firmado por nosotros.
 *   3. Que el alumno VINCULADO no pueda pagar. Su PF ya paga por el, y cobrarle
 *      seria cobrar dos veces lo mismo.
 *   4. Que el plan se escriba con `producto: "athlete"`. Sin eso, el
 *      reconciliador del PF le escribe un `subscription` de entrenador.
 */

const warnSpy = jest.fn();
const infoSpy = jest.fn();
const errorSpy = jest.fn();

jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...a: unknown[]) => warnSpy(...a),
    info: (...a: unknown[]) => infoSpy(...a),
    error: (...a: unknown[]) => errorSpy(...a),
  },
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "token-falso" }),
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

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  FieldValue: { serverTimestamp: () => ({ __sentinel: "now" }) },
}));

import type { App } from "firebase-admin/app";

import {
  backUrlPara,
  runCreateAthletePreapproval,
} from "../subscriptions/mp/create-athlete-preapproval";
import { MOTIVO_ABANDONO } from "../subscriptions/mp/motivos-terminal";
import { ATHLETE_PRICES_ARS } from "../subscriptions/athlete-plan-config";
import { MpPreapproval } from "../subscriptions/mp/client";
import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

const AHORA = Date.parse("2026-09-17T12:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;
const UID = "u1";

type Store = Record<string, Record<string, unknown>>;

/** Timestamp de mentira con la unica operacion que el codigo usa. */
const ts = (ms: number) => ({ toMillis: () => ms });

/**
 * Copia profunda de los objetos planos, que deja las funciones como estan.
 *
 * No es `JSON.parse(JSON.stringify(...))` a proposito: eso borra el `toMillis` de
 * los Timestamp de mentira, y un `currentPeriodEnd` sin el se lee como "sin fecha".
 * El diferimiento no se dispararia nunca y sus tests darian verde por el motivo
 * equivocado.
 */
function clonar<T>(v: T): T {
  if (Array.isArray(v)) return v.map(clonar) as T;
  if (v !== null && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) {
    return Object.fromEntries(
      Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, clonar(x)]),
    ) as T;
  }
  return v;
}

/**
 * Firestore de mentira: documentos por coleccion + una query de `trainer_links`
 * que filtra por los dos `where` que usa el callable.
 */
function fakeApp(seed: Store = {}) {
  const store: Store = clonar(seed);
  const escrituras: { col: string; id: string; data: unknown }[] = [];
  /** Que colecciones se consultaron por query. Para probar el camino feliz. */
  const queries: string[] = [];

  const coleccion = (col: string) => ({
    doc: (id: string) => ({
      get: async () => ({
        exists: store[col]?.[id] !== undefined,
        data: () => store[col]?.[id],
      }),
      set: async (data: Record<string, unknown>) => {
        store[col] = store[col] ?? {};
        store[col][id] = { ...(store[col][id] as object ?? {}), ...data };
        escrituras.push({ col, id, data });
      },
    }),
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [[campo, valor]]),
  });

  const filtrada = (col: string, filtros: [string, unknown][]) => ({
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [...filtros, [campo, valor]]),
    limit: () => filtrada(col, filtros),
    get: async () => {
      queries.push(col);
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) =>
          filtros.every(([c, v]) => (d as Record<string, unknown>)[c] === v))
        .map(([id, d]) => ({ id, data: () => d }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const app = { firestore: () => ({ collection: coleccion }) } as unknown as App;
  return { app, store, escrituras, queries: () => queries };
}

/** Un alumno SUELTO: existe, es `athlete`, y no tiene vinculo activo. */
const ALUMNO_SUELTO = (): Store => ({
  users: { [UID]: { role: "athlete", displayName: "Ana" } },
});

function fakeMp(
  over: Partial<{
    falla: Error;
    /** Que suscripciones tiene MP por plan, solo con `status`. Sin esto, ninguno tiene. */
    suscripciones: Record<string, { status: string }[]>;
    /** Lo que MP contesta por plan, completo (con cobros). Gana sobre `suscripciones`. */
    subs: Record<string, MpPreapproval[] | Error>;
    /** Hace fallar la CONSULTA a MP (no la apertura del checkout). */
    fallaLaBusqueda: Error;
    /** Hace fallar la consulta de UN plan puntual. */
    fallaEnPlan: Record<string, Error>;
    diferirHabilitado: boolean;
  }> = {},
) {
  const pedidos: Record<string, unknown>[] = [];
  /** De que planes se le pidieron las suscripciones a MP, en orden. */
  const busquedas: string[] = [];
  const opcionesDeBusqueda: unknown[] = [];
  return {
    pedidos,
    busquedas,
    opcionesDeBusqueda,
    deps: {
      nowMs: AHORA,
      // Explicito: los tests no dependen del valor de la constante, asi que
      // flipearla (el rollback) no los pone rojos.
      diferirHabilitado: over.diferirHabilitado ?? true,
      mpClient: {
        getPreapproval: async () => ({}),
        searchPreapprovalsByPlan: async (planId: string, opciones?: unknown) => {
          busquedas.push(planId);
          opcionesDeBusqueda.push(opciones);
          if (over.fallaLaBusqueda) throw over.fallaLaBusqueda;
          if (over.fallaEnPlan?.[planId]) throw over.fallaEnPlan[planId];
          const r = over.subs?.[planId];
          if (r instanceof Error) throw r;
          return r ?? over.suscripciones?.[planId] ?? [];
        },
        cancelPreapproval: async () => ({}),
        createPreapprovalPlan: async (p: Record<string, unknown>) => {
          pedidos.push(p);
          if (over.falla) throw over.falla;
          return { id: "plan-nuevo", init_point: "https://mp/checkout/xyz" };
        },
      },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
  };
}

const correr = (app: App, body: unknown, deps: ReturnType<typeof fakeMp>) =>
  runCreateAthletePreapproval(app, UID, body, deps.deps);

beforeEach(() => jest.clearAllMocks());

describe("el monto y la URL — lo que sostiene la exencion de App Check", () => {
  it("el monto sale de ATHLETE_PRICES_ARS y NUNCA del body", async () => {
    // LA asercion del archivo. Si un dia el monto se lee del request, un
    // atacante autenticado se suscribe por 1 peso.
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    await correr(app, { cycle: "monthly", amount: 1, transactionAmount: 1 }, mp);

    expect(mp.pedidos[0].transactionAmount).toBe(ATHLETE_PRICES_ARS.monthly);
    expect(mp.pedidos[0].transactionAmount).toBe(3500);
  });

  it("el anual cobra diez meses, no doce", async () => {
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    await correr(app, { cycle: "annual" }, mp);

    expect(mp.pedidos[0].transactionAmount).toBe(ATHLETE_PRICES_ARS.annual);
    expect(mp.pedidos[0].frequencyMonths).toBe(12);
  });

  it("el precio del alumno no coincide con ninguno del PF", () => {
    // Lo hace cumplir el throw de BY_AMOUNT al importar `tier-mapping`, pero
    // dicho en voz alta acá el mensaje explica QUE regla se rompio.
    const delPf = Object.values(TIER_PRICES_ARS)
      .flatMap((p) => [p.monthly, p.annual]);
    expect(delPf).not.toContain(ATHLETE_PRICES_ARS.monthly);
    expect(delPf).not.toContain(ATHLETE_PRICES_ARS.annual);
  });

  it("la URL de retorno la arma el SERVIDOR desde una lista blanca", () => {
    expect(backUrlPara("es")).toBe(
      "https://gettreino.com/es/suscripcion/resultado",
    );
    expect(backUrlPara("en")).toBe(
      "https://gettreino.com/en/suscripcion/resultado",
    );
  });

  it("un locale que no esta en la lista cae al default, no se convierte en destino", () => {
    // El caso que importa: un `backUrl` que venga del cliente es un open
    // redirect FIRMADO POR NOSOTROS — el atacante manda a la victima a un
    // checkout real de TREINO y la devuelve a su propio dominio, con la
    // confianza ya construida.
    for (const veneno of [
      "https://evil.tld",
      "../../evil",
      "es/../../evil",
      "",
      null,
      undefined,
      42,
      { toString: () => "en" },
    ]) {
      expect(backUrlPara(veneno)).toBe(
        "https://gettreino.com/es/suscripcion/resultado",
      );
    }
  });

  it("el locale del body llega al backUrl, y sigue saliendo de la lista", async () => {
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    await correr(app, { cycle: "monthly", locale: "en" }, mp);
    expect(mp.pedidos[0].backUrl)
      .toBe("https://gettreino.com/en/suscripcion/resultado");

    // App NUEVA: con la misma, el segundo pedido cae en la ventana de reuso y
    // MP nunca se entera — que es, de hecho, lo que hace bien el codigo.
    const { app: app2 } = fakeApp(ALUMNO_SUELTO());
    const mp2 = fakeMp();
    await correr(app2, { cycle: "monthly", locale: "https://evil.tld" }, mp2);
    expect(mp2.pedidos[0].backUrl)
      .toBe("https://gettreino.com/es/suscripcion/resultado");
  });

  it("NO manda a /gracias — esa pagina dispara el evento de waitlist", () => {
    // `ThankYou.tsx` de la landing dispara gtag("generate_lead") y fbq("Lead")
    // al montar. Mandar ahi el retorno de un pago cuenta cada cobro como un
    // lead de lista de espera en GA4 y en Meta.
    expect(backUrlPara("es")).not.toContain("/gracias");
  });
});

describe("quien puede contratar", () => {
  it("un alumno suelto, si", async () => {
    const { app, store } = fakeApp(ALUMNO_SUELTO());

    const r = await correr(app, { cycle: "monthly" }, fakeMp());

    expect(r.status).toBe("created");
    expect(r.initPoint).toBe("https://mp/checkout/xyz");
    expect(store.mp_plans["plan-nuevo"]).toMatchObject({
      producto: "athlete", uid: UID, cycle: "monthly",
    });
  });

  it("un ENTRENADOR no — tiene su propio checkout", async () => {
    const { app } = fakeApp({ users: { [UID]: { role: "trainer" } } });

    await expect(correr(app, { cycle: "monthly" }, fakeMp()))
      .rejects.toMatchObject({ code: "permission-denied" });
  });

  it("un usuario sin documento tampoco", async () => {
    const { app } = fakeApp({});

    await expect(correr(app, { cycle: "monthly" }, fakeMp()))
      .rejects.toMatchObject({ code: "permission-denied" });
  });

  it("un rol desconocido tampoco — el gate es positivo, no negativo", async () => {
    // `!== "athlete"` y no `=== "trainer"`: un rol que todavia no existe no
    // puede comprar por default.
    const { app } = fakeApp({ users: { [UID]: { role: "admin" } } });

    await expect(correr(app, { cycle: "monthly" }, fakeMp()))
      .rejects.toMatchObject({ code: "permission-denied" });
  });

  it("⚠️ un alumno VINCULADO no paga — su PF ya paga por el", async () => {
    // `docs/paywall-alumno-suelto.md` §2: el alumno vinculado no paga NUNCA.
    // Sin esta guarda le cobramos por algo que ya tiene gratis, y el
    // reconciliador se lo acredita igual porque el derecho pago y la exencion
    // por vinculo son dos caminos distintos al mismo resultado.
    const { app } = fakeApp({
      ...ALUMNO_SUELTO(),
      trainer_links: {
        l1: { athleteId: UID, trainerId: "t1", status: "active" },
      },
    });

    await expect(correr(app, { cycle: "monthly" }, fakeMp()))
      .rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("un vinculo PENDIENTE no lo frena — todavia no lo paga nadie", async () => {
    // El contrapeso: una guarda que mirara cualquier vinculo dejaria sin poder
    // pagar al que le mando una solicitud a un PF y nunca se la aceptaron.
    const { app } = fakeApp({
      ...ALUMNO_SUELTO(),
      trainer_links: {
        l1: { athleteId: UID, trainerId: "t1", status: "pending" },
      },
    });

    const r = await correr(app, { cycle: "monthly" }, fakeMp());
    expect(r.status).toBe("created");
  });

  it("el vinculo de OTRO alumno no lo frena", async () => {
    const { app } = fakeApp({
      ...ALUMNO_SUELTO(),
      trainer_links: {
        l1: { athleteId: "otro", trainerId: "t1", status: "active" },
      },
    });

    const r = await correr(app, { cycle: "monthly" }, fakeMp());
    expect(r.status).toBe("created");
  });
});

describe("la entrada", () => {
  const basura: [string, unknown][] = [
    ["un ciclo que no existe", "semanal"],
    ["un tier del PF", "plan2"],
    ["vacio", ""],
    ["null", null],
    ["un numero", 1],
    ["un objeto", { cycle: "monthly" }],
    ["ausente", undefined],
  ];
  for (const [caso, cycle] of basura) {
    it(`rechaza ${caso} con invalid-argument`, async () => {
      const { app } = fakeApp(ALUMNO_SUELTO());

      await expect(correr(app, { cycle }, fakeMp()))
        .rejects.toMatchObject({ code: "invalid-argument" });
    });
  }

  it("un body vacio tambien", async () => {
    const { app } = fakeApp(ALUMNO_SUELTO());

    await expect(correr(app, undefined, fakeMp()))
      .rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("el ciclo se valida ANTES de mirar el rol — no filtra si existe la cuenta", async () => {
    // Un `permission-denied` con un ciclo invalido le diria a un atacante que
    // el uid del token no es de un alumno. El orden importa.
    const { app } = fakeApp({ users: { [UID]: { role: "trainer" } } });

    await expect(correr(app, { cycle: "semanal" }, fakeMp()))
      .rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("cuando MP falla", () => {
  it("un error retryable sale como `unavailable`", async () => {
    // Para que el cliente pueda ofrecer «probá de nuevo» sin mentir.
    const { app } = fakeApp(ALUMNO_SUELTO());
    const falla = Object.assign(new Error("503"), {
      status: 503, retryable: true, body: {},
    });

    await expect(correr(app, { cycle: "monthly" }, fakeMp({ falla })))
      .rejects.toMatchObject({ code: "unavailable" });
  });

  it("un error nuestro sale como `internal`", async () => {
    // Un 401 no se arregla porque el alumno vuelva a tocar el boton.
    const { app } = fakeApp(ALUMNO_SUELTO());
    const falla = Object.assign(new Error("401"), {
      status: 401, retryable: false, body: {},
    });

    await expect(correr(app, { cycle: "monthly" }, fakeMp({ falla })))
      .rejects.toMatchObject({ code: "internal" });
  });

  it("si MP falla NO se escribe nada", async () => {
    const { app, escrituras } = fakeApp(ALUMNO_SUELTO());
    const falla = Object.assign(new Error("503"), {
      status: 503, retryable: true, body: {},
    });

    await expect(correr(app, { cycle: "monthly" }, fakeMp({ falla })))
      .rejects.toThrow();
    expect(escrituras).toEqual([]);
  });
});

describe("la ventana de reuso", () => {
  it("dos pedidos del mismo ciclo devuelven el MISMO checkout", async () => {
    // Sin esto, dos clicks abren DOS suscripciones en MP y el que completa las
    // dos paga dos veces. MP no deduplica.
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    const a = await correr(app, { cycle: "monthly" }, mp);
    const b = await correr(app, { cycle: "monthly" }, mp);

    expect(a.status).toBe("created");
    expect(b.status).toBe("reused");
    expect(b.planId).toBe(a.planId);
    // Y lo que importa: MP recibio UN solo pedido.
    expect(mp.pedidos).toHaveLength(1);
  });

  it("cambiar de ciclo SI abre uno nuevo", async () => {
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    await correr(app, { cycle: "monthly" }, mp);
    const b = await correr(app, { cycle: "annual" }, mp);

    expect(b.status).toBe("created");
    expect(mp.pedidos).toHaveLength(2);
  });

  it("la huella del alumno lleva `producto`, la del PF no puede llevarlo", async () => {
    // La del PF es EXACTAMENTE {tier, cycle} y no puede ganar campos: los docs
    // de `mp_checkouts` que hay en produccion tienen esos dos y ninguno mas.
    // La del alumno es distinta a proposito, y no colisiona porque `role` es
    // inmutable y el doc esta keyeado por uid.
    const { app, store } = fakeApp(ALUMNO_SUELTO());

    await correr(app, { cycle: "monthly" }, fakeMp());

    expect(store.mp_checkouts[UID]).toMatchObject({
      producto: "athlete", cycle: "monthly",
    });
    expect(store.mp_checkouts[UID]).not.toHaveProperty("tier");
  });
});

describe("no se puede comprar dos veces el MISMO ciclo", () => {
  /** Un alumno que YA paga, con su plan vivo en `mp_plans`. */
  const YA_PAGA = (cycle = "monthly"): Store => ({
    users: {
      [UID]: {
        role: "athlete",
        displayName: "Ana",
        athleteSubscription: { status: "active" },
      },
    },
    mp_plans: { viejo: { producto: "athlete", uid: UID, cycle } },
  });

  it("rechaza el mismo ciclo que ya paga", async () => {
    // El caso real: vuelve a la pagina de precios un mes despues y aprieta de
    // nuevo, porque no se acuerda o porque nada se lo dice. La ventana de
    // `abrirCheckout` no lo cubre — dura 30 minutos.
    const { app } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp();

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject({ code: "failed-precondition" });
    // Y no se abrio ningun cobro en MP.
    expect(mp.pedidos).toEqual([]);
  });

  it("PERMITE volver a suscribirse si el derecho ya vencio", async () => {
    // Sin la condicion del derecho, alguien cuyo plan vencio no podria
    // suscribirse NUNCA MAS, porque el documento de `mp_plans` sigue ahi.
    const mundo = YA_PAGA("monthly");
    (mundo.users[UID] as Record<string, unknown>).athleteSubscription = {
      status: "expired",
    };
    const { app } = fakeApp(mundo);

    const r = await correr(app, { cycle: "monthly" }, fakeMp());

    expect(r.status).toBe("created");
  });

  it("`grace` tambien cuenta como que ya paga", async () => {
    // `grace` OTORGA derecho: el cobro rebota y MP reintenta. Dejarlo comprar
    // ahi le abriria un segundo cobro mientras el primero todavia se resuelve.
    const mundo = YA_PAGA("monthly");
    (mundo.users[UID] as Record<string, unknown>).athleteSubscription = {
      status: "grace",
    };
    const { app } = fakeApp(mundo);

    await expect(correr(app, { cycle: "monthly" }, fakeMp()))
      .rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("un plan TERMINAL no lo traba", async () => {
    // Un plan que ya no cobra no puede impedir contratar uno nuevo.
    const mundo = YA_PAGA("monthly");
    (mundo.mp_plans.viejo as Record<string, unknown>).terminal = true;
    const { app } = fakeApp(mundo);

    const r = await correr(app, { cycle: "monthly" }, fakeMp());

    expect(r.status).toBe("created");
  });

  it("el plan de OTRO alumno no lo traba", async () => {
    const mundo = YA_PAGA("monthly");
    (mundo.mp_plans.viejo as Record<string, unknown>).uid = "otro";
    const { app } = fakeApp(mundo);

    const r = await correr(app, { cycle: "monthly" }, fakeMp());

    expect(r.status).toBe("created");
  });

  it("un plan de PF del mismo uid no lo traba", async () => {
    // No deberia pasar —`role` es inmutable— pero si pasara, un plan de
    // entrenador no dice nada sobre la suscripcion de alumno.
    const mundo = YA_PAGA("monthly");
    (mundo.mp_plans.viejo as Record<string, unknown>).producto = "trainer";
    const { app } = fakeApp(mundo);

    const r = await correr(app, { cycle: "monthly" }, fakeMp());

    expect(r.status).toBe("created");
  });

  it("un alumno que nunca pago no le pregunta nada a MP", async () => {
    // El caso NORMAL no tiene por que costar una llamada de red: sin planes en
    // `mp_plans` no hay a quien preguntarle.
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    await correr(app, { cycle: "monthly" }, mp);

    expect(mp.busquedas).toEqual([]);
  });
});

describe("mitigacion: un solo plan vivo — no se abre otro mientras MP cobra", () => {
  // MITIGACION TEMPORAL del cobro doble: la rama del alumno de `reconcile.ts`
  // no da de baja el plan reemplazado, asi que dos checkouts = dos cobros.
  // Estos tests se borran cuando esa baja exista.

  const YA_PAGA = (cycle: string, status = "active"): Store => ({
    users: {
      [UID]: {
        role: "athlete",
        displayName: "Ana",
        athleteSubscription: { status },
      },
    },
    mp_plans: { viejo: { producto: "athlete", uid: UID, cycle } },
  });

  const RECHAZADO = { code: "failed-precondition" };

  it("mensual activo → pedir anual se RECHAZA y no se abre checkout", async () => {
    const { app, escrituras } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);

    // Lo que importa: MP no recibio ningun pedido de plan y no se escribio nada.
    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
  });

  it("anual activo → pedir mensual se RECHAZA y no se abre checkout", async () => {
    const { app, escrituras } = fakeApp(YA_PAGA("annual"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject(RECHAZADO);

    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
  });

  it("el mismo ciclo sigue rechazado", async () => {
    const { app } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject(RECHAZADO);
    expect(mp.pedidos).toEqual([]);
  });

  it("el mensaje del cambio de ciclo no activa ningun copy equivocado de la landing", async () => {
    // `motivoDeLaPrecondicion` (treino-app) busca «entrenador» y «ciclo» en el
    // texto. Con cualquiera de las dos el alumno veria un motivo falso.
    const { app } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    const error = await correr(app, { cycle: "annual" }, mp).catch((e) => e);

    expect(error.code).toBe("failed-precondition");
    expect(error.message.toLowerCase()).not.toContain("entrenador");
    expect(error.message.toLowerCase()).not.toContain("ciclo");
  });

  it("⚠️ NEGATIVO: plan dado de baja con periodo por delante → SI se puede contratar", async () => {
    // El derecho sigue `active` hasta que vence (terminos §7), pero MP ya no
    // cobra. Si la guarda mirara el derecho en vez de a MP, esto quedaria
    // bloqueado y el que vuelve no podria pagarnos.
    const mundo = YA_PAGA("monthly", "active");
    (mundo.mp_plans.viejo as Record<string, unknown>).currentPeriodEnd =
      AHORA + 10 * 24 * 3600 * 1000;
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "cancelled" }] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
    expect(mp.busquedas).toEqual(["viejo"]);
    // La lista que deja pasar tiene que venir de una respuesta sana: en modo
    // laxo, un `results` roto de MP tambien se leeria como "no cobra nada".
    expect(mp.opcionesDeBusqueda).toEqual([{ estricto: true }]);
  });

  it("pausado (derecho `expired`) → se RECHAZA: el pagador lo puede reactivar", async () => {
    // `paused` figura `expired` en nuestro derecho, asi que mirar `users/{uid}`
    // lo dejaria pasar. Pero MP lo puede reanudar, y ahi cobran los dos.
    const { app } = fakeApp(YA_PAGA("monthly", "expired"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "paused" }] } });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
    expect(mp.pedidos).toEqual([]);
  });

  it("en `grace` (MP sigue `authorized` y reintenta) se RECHAZA", async () => {
    const { app } = fakeApp(YA_PAGA("monthly", "grace"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
  });

  it("un checkout abierto y nunca pagado (sin suscripcion en MP) no bloquea", async () => {
    // Abrio el mensual, lo abandono, y ahora quiere el anual.
    const mundo = YA_PAGA("monthly", "expired");
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
  });

  it("una suscripcion `pending` (todavia no autorizo) no bloquea", async () => {
    const { app } = fakeApp(YA_PAGA("monthly", "expired"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "pending" }] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
  });

  it("un estado de MP desconocido bloquea: ante la duda, no se arma un cobro doble", async () => {
    const { app } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "algo-nuevo" }] } });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
  });

  it("un plan terminal (baja confirmada) no gasta una consulta ni bloquea", async () => {
    const mundo = YA_PAGA("monthly", "expired");
    (mundo.mp_plans.viejo as Record<string, unknown>).terminal = true;
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
    expect(mp.busquedas).toEqual([]);
  });

  it("un terminal por ABANDONO se sigue mirando: el init_point no vence y se puede pagar tarde", async () => {
    const mundo = YA_PAGA("monthly", "expired");
    Object.assign(mundo.mp_plans.viejo as Record<string, unknown>, {
      terminal: true, terminalReason: MOTIVO_ABANDONO,
    });
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
  });

  it("el plan de OTRO alumno no bloquea", async () => {
    const mundo = YA_PAGA("monthly", "expired");
    (mundo.mp_plans.viejo as Record<string, unknown>).uid = "otro";
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
    expect(mp.busquedas).toEqual([]);
  });

  it("si no se puede consultar a MP NO se abre checkout: sale `unavailable`", async () => {
    // Sin saber si hay un cobro vivo no se puede descartar el doble cobro.
    const { app, escrituras } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({ fallaLaBusqueda: new Error("503") });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject({ code: "unavailable" });
    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
    expect(errorSpy).toHaveBeenCalled();
  });

  it("varios planes: uno cancelado y otro autorizado → se RECHAZA", async () => {
    // El alumno que se dio de baja del mensual, contrato el anual, y ahora
    // pide otro. El cancelado no tapa al vivo.
    // Derecho `expired` para que sea la consulta a MP la que rechaza, no la
    // guarda del mismo ciclo.
    const mundo = YA_PAGA("monthly", "expired");
    mundo.mp_plans.nuevo = { producto: "athlete", uid: UID, cycle: "annual" };
    const { app } = fakeApp(mundo);
    const mp = fakeMp({
      suscripciones: {
        viejo: [{ status: "cancelled" }],
        nuevo: [{ status: "authorized" }],
      },
    });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject(RECHAZADO);
    expect(mp.pedidos).toEqual([]);
  });

  it("un plan de PF (`producto: trainer`) del mismo uid autorizado NO cuenta", async () => {
    // No deberia existir —`role` es inmutable— pero si existiera, el cobro de
    // un entrenador no es el del alumno. Y ni siquiera se le pregunta a MP.
    const mundo = YA_PAGA("monthly", "expired");
    (mundo.mp_plans.viejo as Record<string, unknown>).producto = "trainer";
    const { app } = fakeApp(mundo);
    const mp = fakeMp({ suscripciones: { viejo: [{ status: "authorized" }] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(r.status).toBe("created");
    expect(mp.busquedas).toEqual([]);
  });

  it("una suscripcion de MP SIN status bloquea — igual que un estado desconocido", async () => {
    const { app } = fakeApp(YA_PAGA("monthly"));
    const mp = fakeMp({
      suscripciones: { viejo: [{} as unknown as { status: string }] },
    });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
    expect(mp.pedidos).toEqual([]);
  });

  it("la consulta es SECUENCIAL: con el primero vivo no se consulta el segundo", async () => {
    // MP contesta 429 y los planes abandonados se acumulan: cada llamada de
    // mas es una chance de trabar al alumno.
    // Derecho `expired` para que la guarda del mismo ciclo no atienda antes.
    const mundo = YA_PAGA("monthly", "expired");
    mundo.mp_plans.otro = { producto: "athlete", uid: UID, cycle: "annual" };
    const { app } = fakeApp(mundo);
    const mp = fakeMp({
      suscripciones: {
        viejo: [{ status: "authorized" }],
        otro: [{ status: "authorized" }],
      },
    });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject(RECHAZADO);
    expect(mp.busquedas).toEqual(["viejo"]);
  });

  it("si una consulta falla antes de hallar uno vivo → `unavailable` y no se abre checkout", async () => {
    const mundo = YA_PAGA("monthly", "expired");
    mundo.mp_plans.otro = { producto: "athlete", uid: UID, cycle: "annual" };
    const { app, escrituras } = fakeApp(mundo);
    const mp = fakeMp({
      suscripciones: { viejo: [{ status: "cancelled" }] },
      fallaEnPlan: { otro: new Error("429") },
    });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject({ code: "unavailable" });
    expect(mp.busquedas).toEqual(["viejo", "otro"]);
    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Volver con dias pagos: el primer cobro se difiere.
//
// Las reglas de la decision se prueban en `mp-diferir-primer-cobro.test.ts`. Aca
// se fija lo que el CALLABLE hace con ella: que el plan de MP lleve la prueba, que
// la guarda del mismo ciclo no le cierre la puerta al que se dio de baja, y que
// la fecha vuelva en la respuesta para que la landing avise antes de MP.
// ---------------------------------------------------------------------------

describe("volver con dias pagos: el primer cobro se difiere", () => {
  /** Lo que el alumno ya tenia pago: del 17/9 (AHORA) al 30/9, 13 dias. */
  const FIN = AHORA + 13 * DIA_MS;
  /** El cobro del 30/8 cubre un mes: hasta FIN. */
  const ULTIMO_COBRO = "2026-08-30T12:00:00.000Z";

  /**
   * Un alumno que pago y se dio de baja. El documento dice `active` (le quedan
   * dias, como a uno que paga) y su plan tiene fecha y NO es `terminal`: es como
   * los deja el reconciliador del alumno mientras el periodo corre.
   */
  const DADO_DE_BAJA = (): Store => ({
    users: {
      [UID]: {
        role: "athlete",
        displayName: "Ana",
        athleteSubscription: { status: "active" },
      },
    },
    mp_plans: {
      viejo: {
        producto: "athlete",
        uid: UID,
        cycle: "monthly",
        createdAt: ts(AHORA - 18 * DIA_MS),
        currentPeriodEnd: ts(FIN),
      },
    },
  });

  /** Su suscripcion en MP: dada de baja, con el cobro del 30/8. */
  const BAJA: MpPreapproval = {
    id: "s-vieja",
    status: "cancelled",
    auto_recurring: {
      frequency: 1,
      frequency_type: "months",
      transaction_amount: ATHLETE_PRICES_ARS.monthly,
    },
    summarized: {
      charged_quantity: 1,
      charged_amount: ATHLETE_PRICES_ARS.monthly,
      last_charged_date: ULTIMO_COBRO,
      last_charged_amount: ATHLETE_PRICES_ARS.monthly,
      pending_charge_quantity: 0,
    },
  };
  /** La misma suscripcion, pero VIVA: el alumno no se dio de baja. */
  const VIVA: MpPreapproval = { ...BAJA, status: "authorized" };

  it("dado de baja, vuelve al MISMO ciclo: el plan nuevo arranca con prueba hasta que vence lo que pago", async () => {
    const { app, store } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [BAJA] } });

    const r = await correr(app, { cycle: "monthly" }, mp);

    expect(r.status).toBe("created");
    // Del 17/9 al 30/9: 13 dias de calendario argentino.
    expect(mp.pedidos[0].freeTrialDays).toBe(13);
    expect(r.diferidoHastaIso).toBe(new Date(FIN).toISOString());
    expect(store.mp_plans["plan-nuevo"])
      .toMatchObject({ producto: "athlete", cycle: "monthly", diferidoHastaMs: FIN });
    expect(store.mp_checkouts[UID]).toMatchObject({ diferidoHastaMs: FIN });
  });

  it("con esa suscripcion VIVA el mismo ciclo sigue bloqueado (el control del test anterior)", async () => {
    // Es lo que prueba que la guarda se levanta por lo que dijo MP, y no por otra
    // cosa: el mismo documento y el mismo plan, con la suscripcion autorizada.
    const { app } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [VIVA] } });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject({ code: "failed-precondition" });
    expect(mp.pedidos).toEqual([]);
  });

  it("cambiar de ciclo tambien se difiere: el anual pagaria dos veces los mismos dias", async () => {
    const { app } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [BAJA] } });

    const r = await correr(app, { cycle: "annual" }, mp);

    expect(mp.pedidos[0]).toMatchObject({ frequencyMonths: 12, freeTrialDays: 13 });
    expect(r.diferidoHastaIso).toBe(new Date(FIN).toISOString());
  });

  it("con la suscripcion viva, cambiar de ciclo se BLOQUEA: ni prueba ni cobro en el acto", async () => {
    // Antes de la mitigacion (#1305) esto abria el checkout y cobraba en el acto
    // mientras el plan viejo seguia cobrando. Ahora la pasada por MP encuentra la
    // viva y no se abre nada: el diferimiento no puede esquivar el bloqueo.
    const { app, store, escrituras } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [VIVA] } });

    const error = await correr(app, { cycle: "annual" }, mp).catch((e) => e);

    expect(error.code).toBe("failed-precondition");
    expect(error.message).toContain("se sigue cobrando");
    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
    expect(store.mp_plans["plan-nuevo"]).toBeUndefined();
  });

  it("con el interruptor apagado todo es como antes: el mismo ciclo bloqueado, el otro en el acto", async () => {
    const mismo = fakeApp(DADO_DE_BAJA());
    await expect(correr(mismo.app, { cycle: "monthly" },
      fakeMp({ subs: { viejo: [BAJA] }, diferirHabilitado: false })))
      .rejects.toMatchObject({ code: "failed-precondition" });

    const otro = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [BAJA] }, diferirHabilitado: false });
    const r = await correr(otro.app, { cycle: "annual" }, mp);

    expect(mp.pedidos[0]).not.toHaveProperty("freeTrialDays");
    expect(r).not.toHaveProperty("diferidoHastaIso");
    // Apagado NO apaga el bloqueo (#1305): es una guarda del cobro doble y no
    // depende del diferimiento, asi que consulta a MP igual.
    expect(mp.busquedas).toEqual(["viejo"]);
  });

  it("con el interruptor apagado, una suscripcion viva igual se bloquea", async () => {
    const { app } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [VIVA] }, diferirHabilitado: false });

    await expect(correr(app, { cycle: "annual" }, mp))
      .rejects.toMatchObject({ code: "failed-precondition" });
    expect(mp.pedidos).toEqual([]);
  });

  it("si no puede consultar MP no abre nada: unavailable, para que reintente", async () => {
    // Seguir de largo sin saber si tiene dias pagos es cobrarle en el acto lo
    // que ya pago: el doble cobro que esto viene a cerrar.
    const { app, escrituras } = fakeApp(DADO_DE_BAJA());
    const falla = Object.assign(new Error("503"), { status: 503, retryable: true });
    const mp = fakeMp({ subs: { viejo: falla } });

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject({ code: "unavailable" });
    expect(mp.pedidos).toEqual([]);
    expect(escrituras).toEqual([]);
  });

  it("el doble click vuelve a verificar contra MP y reusa el MISMO checkout", async () => {
    // Sin atajo, a diferencia del PF: el segundo toque vuelve a preguntar (el
    // checkout recien abierto incluido) y, como nada cambio, llega a la misma
    // fecha, que es lo que `abrirCheckout` necesita para reusar.
    const { app } = fakeApp(DADO_DE_BAJA());
    const mp = fakeMp({ subs: { viejo: [BAJA] } });

    const a = await correr(app, { cycle: "monthly" }, mp);
    const b = await correr(app, { cycle: "monthly" }, mp);

    expect(b.status).toBe("reused");
    expect(b.planId).toBe(a.planId);
    expect(mp.pedidos).toHaveLength(1);
    // Cada toque consulta dos veces cada plan: el diferimiento y el bloqueo de
    // #1305 preguntan por separado lo mismo (se unifican en el commit siguiente).
    expect(mp.busquedas.slice(2).sort())
      .toEqual(["plan-nuevo", "plan-nuevo", "viejo", "viejo"]);
    // Y la respuesta reusada tambien trae la fecha: la landing avisa igual.
    expect(b.diferidoHastaIso).toBe(new Date(FIN).toISOString());
  });

  it("⚠️ si ya autorizo el checkout diferido, el segundo toque queda bloqueado: no le abre otro", async () => {
    // El hueco que encontro la revision: con el atajo del PF, el segundo toque no
    // le preguntaba nada a MP, se salteaba la guarda y devolvia el checkout ya
    // pagado. Ahora el plan nuevo se consulta, esta vivo, y la guarda vuelve.
    const { app } = fakeApp(DADO_DE_BAJA());
    const subs: Record<string, MpPreapproval[]> = { viejo: [BAJA] };
    const mp = fakeMp({ subs });

    await correr(app, { cycle: "monthly" }, mp);
    // Lo autorizo: la suscripcion de su plan nuevo esta viva, en prueba.
    subs["plan-nuevo"] = [{
      id: "s-nueva",
      status: "authorized",
      auto_recurring: {
        frequency: 1,
        frequency_type: "months",
        free_trial: { frequency: 13, frequency_type: "days" },
      },
      summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
    }];

    await expect(correr(app, { cycle: "monthly" }, mp))
      .rejects.toMatchObject({ code: "failed-precondition" });
    expect(mp.pedidos).toHaveLength(1);
  });

  it("un checkout normal NO trae diferidoHastaIso ni le cuesta una busqueda en MP", async () => {
    const { app } = fakeApp(ALUMNO_SUELTO());
    const mp = fakeMp();

    const r = await correr(app, { cycle: "monthly" }, mp);

    expect(r).not.toHaveProperty("diferidoHastaIso");
    expect(mp.pedidos[0]).not.toHaveProperty("freeTrialDays");
    expect(mp.busquedas).toEqual([]);
  });

  it("mp_plans se lee UNA vez aunque lo usen el diferimiento y la guarda del ciclo", async () => {
    // Con la suscripcion viva corren los dos: el diferimiento (que no difiere) y
    // la guarda (que bloquea). La query es la misma y se comparte.
    const { app, queries } = fakeApp(DADO_DE_BAJA());

    await expect(correr(app, { cycle: "monthly" }, fakeMp({ subs: { viejo: [VIVA] } })))
      .rejects.toMatchObject({ code: "failed-precondition" });

    expect(queries().filter((c) => c === "mp_plans")).toHaveLength(1);
  });
});
