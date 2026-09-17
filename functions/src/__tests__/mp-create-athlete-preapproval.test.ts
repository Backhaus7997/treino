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
import { ATHLETE_PRICES_ARS } from "../subscriptions/athlete-plan-config";
import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

const AHORA = Date.parse("2026-09-17T12:00:00.000Z");
const UID = "u1";

type Store = Record<string, Record<string, unknown>>;

/**
 * Firestore de mentira: documentos por coleccion + una query de `trainer_links`
 * que filtra por los dos `where` que usa el callable.
 */
function fakeApp(seed: Store = {}) {
  const store: Store = JSON.parse(JSON.stringify(seed));
  const escrituras: { col: string; id: string; data: unknown }[] = [];

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
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) =>
          filtros.every(([c, v]) => (d as Record<string, unknown>)[c] === v))
        .map(([id, d]) => ({ id, data: () => d }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const app = { firestore: () => ({ collection: coleccion }) } as unknown as App;
  return { app, store, escrituras };
}

/** Un alumno SUELTO: existe, es `athlete`, y no tiene vinculo activo. */
const ALUMNO_SUELTO = (): Store => ({
  users: { [UID]: { role: "athlete", displayName: "Ana" } },
});

function fakeMp(over: Partial<{ falla: Error }> = {}) {
  const pedidos: Record<string, unknown>[] = [];
  return {
    pedidos,
    deps: {
      nowMs: AHORA,
      mpClient: {
        getPreapproval: async () => ({}),
        searchPreapprovalsByPlan: async () => [],
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
