/**
 * mp-diferir-primer-cobro.test.ts: que volver a suscribirse con dias pagos no
 * cobre dos veces el mismo periodo.
 * LOCAL, sin emulador y SIN RED: las dos lecturas (planes y MP) entran por
 * parametro, asi que no hace falta ningun mock de Firestore.
 *
 * Lo que estos tests cuidan es el lado caro de equivocarse. Diferir de mas le
 * regala dias al PF; diferir de menos lo cobra dos veces. Por eso casi todo lo
 * dudoso tiene que terminar en "no se difiere" (cobrar en el acto, como antes),
 * y lo unico que tira es no poder LEER.
 */

jest.mock("firebase-functions", () => ({
  logger: { warn: jest.fn(), info: jest.fn(), error: jest.fn() },
}));

import { logger } from "firebase-functions";

import { MpPreapproval } from "../subscriptions/mp/client";
import {
  DIA_MS,
  DecidirDiferimientoInput,
  MAX_PLANES_A_REVISAR,
  MIN_DIFERIMIENTO_MS,
  PlanDeLaCuenta,
  decidirDiferimiento,
  diasDePrueba,
  pagadoHastaDe,
  planesARevisar,
} from "../subscriptions/mp/diferir-primer-cobro";
import { SubscriptionTier } from "../subscriptions/tier-config";

/** Timestamp de mentira con la unica operacion que el codigo usa. */
const ts = (ms: number) => ({ toMillis: () => ms });

/** Un "ahora" fijo: el reloj entra por parametro en todo lo que se prueba. */
const AHORA = Date.parse("2026-09-07T12:00:00.000Z");

beforeEach(() => jest.clearAllMocks());

// ---------------------------------------------------------------------------
// pagadoHastaDe: la evidencia de pago, leida de lo que MP dice que cobro.
// ---------------------------------------------------------------------------

/** Una suscripcion con un cobro, tal como la devuelve la busqueda de MP. */
function pagada(
  ultimoCobro: string,
  over: Partial<MpPreapproval> = {},
): MpPreapproval {
  return {
    id: "s1",
    status: "cancelled",
    auto_recurring: {
      frequency: 1,
      frequency_type: "months",
      transaction_amount: 22000,
    },
    summarized: {
      charged_quantity: 1,
      last_charged_date: ultimoCobro,
      pending_charge_quantity: 0,
    },
    ...over,
  };
}

describe("pagadoHastaDe", () => {
  it("el ultimo cobro mas UN periodo mensual", () => {
    expect(pagadoHastaDe(pagada("2026-08-20T12:00:00.000Z")))
      .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("un anual cubre 12 meses desde el cobro", () => {
    const anual = pagada("2026-03-01T09:30:00.000Z", {
      auto_recurring: { frequency: 12, frequency_type: "months" },
    });

    expect(pagadoHastaDe(anual)).toBe(Date.parse("2027-03-01T09:30:00.000Z"));
  });

  it("cuenta desde el ULTIMO cobro y no desde el primero", () => {
    const tresCobros = pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: 3,
        last_charged_date: "2026-08-20T12:00:00.000Z",
      },
    });

    expect(pagadoHastaDe(tresCobros))
      .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("respeta el huso horario con el que MP manda la fecha", () => {
    expect(pagadoHastaDe(pagada("2026-08-20T10:00:00.000-04:00")))
      .toBe(Date.parse("2026-09-20T10:00:00.000-04:00"));
  });

  it("el desborde de mes lo normaliza el calendario, igual que en reconcile", () => {
    // 31 de enero + 1 mes no existe: `setUTCMonth` lo lleva al 3 de marzo, que
    // es la misma cuenta de `finDePeriodoDesdeAltaMs`.
    const ms = pagadoHastaDe(pagada("2026-01-31T00:00:00.000Z"));

    expect(new Date(ms as number).toISOString())
      .toBe("2026-03-03T00:00:00.000Z");
  });

  const sinEvidencia: [string, MpPreapproval][] = [
    ["sin cobros (charged_quantity 0)", pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: 0,
        last_charged_date: "2026-08-20T12:00:00.000Z",
      },
    })],
    ["sin summarized", pagada("2026-08-20T12:00:00.000Z", { summarized: undefined })],
    ["summarized null", pagada("2026-08-20T12:00:00.000Z", { summarized: null })],
    ["summarized que no es un objeto", pagada("2026-08-20T12:00:00.000Z", {
      summarized: "cobrado",
    })],
    ["sin charged_quantity", pagada("2026-08-20T12:00:00.000Z", {
      summarized: { last_charged_date: "2026-08-20T12:00:00.000Z" },
    })],
    ["charged_quantity como string", pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: "1",
        last_charged_date: "2026-08-20T12:00:00.000Z",
      },
    })],
    ["charged_quantity NaN", pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: Number.NaN,
        last_charged_date: "2026-08-20T12:00:00.000Z",
      },
    })],
    ["charged_quantity negativo", pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: -1,
        last_charged_date: "2026-08-20T12:00:00.000Z",
      },
    })],
    ["sin last_charged_date", pagada("2026-08-20T12:00:00.000Z", {
      summarized: { charged_quantity: 1 },
    })],
    ["last_charged_date null", pagada("2026-08-20T12:00:00.000Z", {
      summarized: { charged_quantity: 1, last_charged_date: null },
    })],
    ["last_charged_date que no es fecha", pagada("manana")],
    ["last_charged_date numerico", pagada("2026-08-20T12:00:00.000Z", {
      summarized: { charged_quantity: 1, last_charged_date: 1_787_000_000_000 },
    })],
    ["sin auto_recurring", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: undefined,
    })],
    ["auto_recurring null", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: null,
    })],
    ["auto_recurring que no es un objeto", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: "mensual",
    })],
    ["frequency cero", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: 0, frequency_type: "months" },
    })],
    ["frequency fraccionaria", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: 1.5, frequency_type: "months" },
    })],
    ["frequency absurda (24 meses es el tope)", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: 25, frequency_type: "months" },
    })],
    ["frequency como string", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: "1", frequency_type: "months" },
    })],
    ["frequency_type days: no lo entendemos y no lo adivinamos",
      pagada("2026-08-20T12:00:00.000Z", {
        auto_recurring: { frequency: 30, frequency_type: "days" },
      })],
    ["sin frequency_type", pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: 1 },
    })],
  ];

  for (const [caso, sub] of sinEvidencia) {
    it(`da null: ${caso}`, () => {
      expect(pagadoHastaDe(sub)).toBeNull();
    });
  }

  it("el tope de 24 meses es inclusivo", () => {
    const dosAnios = pagada("2026-08-20T12:00:00.000Z", {
      auto_recurring: { frequency: 24, frequency_type: "months" },
    });

    expect(pagadoHastaDe(dosAnios)).toBe(Date.parse("2028-08-20T12:00:00.000Z"));
  });
});

// ---------------------------------------------------------------------------
// diasDePrueba: el primer cobro cae en la fecha o apenas despues, NUNCA antes.
// ---------------------------------------------------------------------------

describe("diasDePrueba", () => {
  it("un multiplo exacto de dias da esos dias", () => {
    expect(diasDePrueba(AHORA + 10 * DIA_MS, AHORA)).toBe(10);
  });

  it("un milisegundo de mas sube UN dia: ceil, nunca round", () => {
    // Con `floor` o `round` el cobro caeria antes de que venza lo que el PF ya
    // pago, que es el bug entero.
    expect(diasDePrueba(AHORA + 10 * DIA_MS + 1, AHORA)).toBe(11);
  });

  it("un milisegundo de menos sigue dando los 10", () => {
    expect(diasDePrueba(AHORA + 10 * DIA_MS - 1, AHORA)).toBe(10);
  });

  it("medio dia son 1 dia", () => {
    expect(diasDePrueba(AHORA + DIA_MS / 2, AHORA)).toBe(1);
  });

  it("el minimo diferible (1 dia exacto) son 1 dia", () => {
    expect(diasDePrueba(AHORA + MIN_DIFERIMIENTO_MS, AHORA)).toBe(1);
  });

  it("un anual entero son 365 dias", () => {
    expect(diasDePrueba(AHORA + 365 * DIA_MS, AHORA)).toBe(365);
  });

  it("el primer cobro nunca cae antes de la fecha, para cualquier hora", () => {
    // Barrido: el cobro cae a `ahora + dias`. Tiene que ser >= la fecha.
    for (let horas = 1; horas <= 24 * 40; horas += 7) {
      const fin = AHORA + horas * 60 * 60 * 1000 + 123;
      const cobro = AHORA + diasDePrueba(fin, AHORA) * DIA_MS;
      expect(cobro).toBeGreaterThanOrEqual(fin);
      // Y no se pasa por mas de un dia.
      expect(cobro - fin).toBeLessThan(DIA_MS);
    }
  });
});

// ---------------------------------------------------------------------------
// planesARevisar: que planes se le consultan a MP, y en que orden.
// ---------------------------------------------------------------------------

function plan(
  id: string,
  edadDias: number,
  data: Record<string, unknown> = {},
): PlanDeLaCuenta {
  return {
    id,
    data: {
      uid: "t1",
      tier: "plan2",
      cycle: "monthly",
      createdAt: ts(AHORA - edadDias * DIA_MS),
      ...data,
    },
  };
}

describe("planesARevisar", () => {
  it("del mas nuevo al mas viejo, sin importar el orden en que llegan", () => {
    const planes = [plan("viejo", 40), plan("nuevo", 2), plan("medio", 15)];

    expect(planesARevisar(planes, "plan2")).toEqual(["nuevo", "medio", "viejo"]);
  });

  it("deja afuera los planes de ALUMNO", () => {
    const planes = [
      plan("a1", 1, { producto: "athlete", tier: undefined }),
      plan("p1", 5),
    ];

    expect(planesARevisar(planes, "plan2")).toEqual(["p1"]);
  });

  it("un alumno que ademas tiene tier escrito sigue afuera", () => {
    // Defensa: el filtro de producto no depende de que falte el tier.
    const planes = [plan("a1", 1, { producto: "athlete" })];

    expect(planesARevisar(planes, "plan2")).toEqual([]);
  });

  it("deja afuera los planes de OTRO tier", () => {
    const planes = [plan("p3", 1, { tier: "plan3" }), plan("p2", 9)];

    expect(planesARevisar(planes, "plan2")).toEqual(["p2"]);
  });

  it("un plan de PF anterior a `producto` (sin el campo) SI entra", () => {
    // Son todos los planes de PF que hay en produccion hoy, y los que mas
    // pueden haber pagado.
    const planes = [plan("legado", 30, { producto: undefined })];

    expect(planesARevisar(planes, "plan2")).toEqual(["legado"]);
  });

  it("incluye cualquier ciclo del tier: el diferimiento es por plan, no por ciclo", () => {
    const planes = [
      plan("mensual", 3),
      plan("anual", 10, { cycle: "annual" }),
    ];

    expect(planesARevisar(planes, "plan2")).toEqual(["mensual", "anual"]);
  });

  it(`no pasa de ${MAX_PLANES_A_REVISAR} planes: los mas nuevos`, () => {
    const planes = [
      plan("p5", 50), plan("p3", 30), plan("p1", 10), plan("p4", 40), plan("p2", 20),
    ];

    expect(planesARevisar(planes, "plan2")).toEqual(["p1", "p2", "p3"]);
  });

  it("el tope se cuenta DESPUES de filtrar: otros tiers no gastan lugar", () => {
    const planes = [
      plan("x1", 1, { tier: "plan3" }),
      plan("x2", 2, { tier: "plan3" }),
      plan("x3", 3, { tier: "plan1" }),
      plan("a1", 4, { producto: "athlete" }),
      plan("p1", 20),
    ];

    expect(planesARevisar(planes, "plan2")).toEqual(["p1"]);
  });

  it("un plan sin fecha legible va al final, pero no se descarta", () => {
    // Sigue pudiendo ser el que pago. Solo pierde frente a los que tienen fecha.
    const planes = [
      plan("sin-fecha", 0, { createdAt: undefined }),
      plan("sentinel", 0, { createdAt: "__ts__" }),
      plan("con-fecha", 90),
    ];

    expect(planesARevisar(planes, "plan2")[0]).toBe("con-fecha");
    expect(planesARevisar(planes, "plan2")).toHaveLength(3);
  });

  it("sin planes da una lista vacia", () => {
    expect(planesARevisar([], "plan2")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// decidirDiferimiento: la decision completa, con las dos lecturas inyectadas.
// ---------------------------------------------------------------------------

/** Un fin de periodo en el futuro: 13 dias adelante, a la misma hora. */
const FIN = Date.parse("2026-09-20T12:00:00.000Z");
/** El ultimo cobro que respalda ese fin con un periodo mensual. */
const ULTIMO_COBRO = "2026-08-20T12:00:00.000Z";

/** `users/{uid}` de un PF dado de baja, en el tier y con la fecha que se pida. */
function usuarioCancelado(
  tier: SubscriptionTier = "plan2",
  finMs: number = FIN,
): Record<string, unknown> {
  return {
    role: "trainer",
    subscription: { tier, status: "cancelled", currentPeriodEnd: ts(finMs) },
  };
}

function armar(
  opts: {
    userData?: Record<string, unknown>;
    tier?: SubscriptionTier;
    planes?: PlanDeLaCuenta[] | Error;
    subs?: Record<string, MpPreapproval[] | Error>;
    nowMs?: number;
  } = {},
) {
  const lecturas = { planes: 0, suscripciones: [] as string[] };
  const input: DecidirDiferimientoInput = {
    uid: "t1",
    tier: opts.tier ?? "plan2",
    userData: "userData" in opts ? opts.userData : usuarioCancelado(),
    nowMs: opts.nowMs ?? AHORA,
    leerPlanes: async () => {
      lecturas.planes += 1;
      if (opts.planes instanceof Error) throw opts.planes;
      return opts.planes ?? [plan("p0", 20)];
    },
    leerSuscripciones: async (planId) => {
      lecturas.suscripciones.push(planId);
      const r = opts.subs?.[planId];
      if (r instanceof Error) throw r;
      return r ?? (planId === "p0" ? [pagada(ULTIMO_COBRO)] : []);
    },
  };
  return { input, lecturas };
}

describe("decidirDiferimiento: cuando SI se difiere", () => {
  it("cancelado, mismo tier, con dias por delante y un cobro real en MP", async () => {
    const { input } = armar();

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("vale para cualquier ciclo del tier: mensual a anual dentro del mismo plan", async () => {
    // Cambiar de ciclo sin cambiar de tier tambien paga dos veces los dias.
    const { input } = armar({
      planes: [plan("p0", 20, { cycle: "monthly" })],
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("gana la fecha MENOR: si MP respalda menos que nuestro fin, manda MP", async () => {
    // Nuestra fecha puede estar corrida hacia adelante. Un cobro hace 25 dias
    // cubre hasta dentro de 5, no hasta dentro de 13.
    const { input } = armar({
      subs: { p0: [pagada("2026-08-12T12:00:00.000Z")] },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({
      diferir: true,
      diferidoHastaMs: Date.parse("2026-09-12T12:00:00.000Z"),
    });
  });

  it("gana la fecha MENOR: si nuestro fin es antes que lo que cubre el cobro, manda el nuestro", async () => {
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 4 * DIA_MS),
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: AHORA + 4 * DIA_MS });
  });

  it("con dos suscripciones en el plan, toma el pago MAS lejano", async () => {
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 40 * DIA_MS),
      subs: {
        p0: [
          pagada("2026-08-10T12:00:00.000Z", { id: "s-vieja" }),
          pagada("2026-08-25T12:00:00.000Z", { id: "s-nueva" }),
        ],
      },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({
      diferir: true,
      diferidoHastaMs: Date.parse("2026-09-25T12:00:00.000Z"),
    });
  });

  it("un anual respalda su ano entero", async () => {
    const fin = Date.parse("2027-02-01T12:00:00.000Z");
    const { input } = armar({
      userData: usuarioCancelado("plan2", fin),
      subs: {
        p0: [pagada("2026-02-01T12:00:00.000Z", {
          auto_recurring: { frequency: 12, frequency_type: "months" },
        })],
      },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: fin });
  });

  it("el borde: exactamente un dia por delante SI se difiere", async () => {
    const fin = AHORA + MIN_DIFERIMIENTO_MS;
    const { input } = armar({
      userData: usuarioCancelado("plan2", fin),
      subs: { p0: [pagada("2026-08-08T12:00:00.000Z")] },
    });

    // El cobro del 8/8 cubre hasta el 8/9 a las 12:00, o sea justo un dia despues
    // de `ahora`: el limite exacto de lo que todavia se difiere.
    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: fin });
  });

  it("loguea la decision con el uid y la fecha, sin datos personales", async () => {
    const { input } = armar();

    await decidirDiferimiento(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se difiere el primer cobro",
      expect.objectContaining({
        uid: "t1",
        tier: "plan2",
        planConPago: "p0",
        diasDePrueba: 13,
        diferidoHastaIso: "2026-09-20T12:00:00.000Z",
      }),
    );
  });
});

describe("decidirDiferimiento: el estado de la suscripcion manda primero", () => {
  /** Cada uno corta ANTES de leer nada: ni Firestore ni MP. */
  const cortes: [string, Record<string, unknown> | undefined, string][] = [
    ["un PF sin suscripcion", { role: "trainer" }, "sin-suscripcion"],
    ["un usuario sin documento", undefined, "sin-suscripcion"],
    ["una suscripcion activa", {
      subscription: { tier: "plan2", status: "active", currentPeriodEnd: ts(FIN) },
    }, "no-esta-cancelada"],
    ["una suscripcion en gracia", {
      subscription: { tier: "plan2", status: "grace", currentPeriodEnd: ts(FIN) },
    }, "no-esta-cancelada"],
    ["una suscripcion pendiente", {
      subscription: { tier: "plan2", status: "pending", currentPeriodEnd: ts(FIN) },
    }, "no-esta-cancelada"],
    ["una suscripcion pausada", {
      subscription: { tier: "plan2", status: "paused", currentPeriodEnd: ts(FIN) },
    }, "no-esta-cancelada"],
    ["otro tier (cancelado en plan3, pide plan2)", usuarioCancelado("plan3"), "otro-tier"],
    ["otro tier (cancelado en plan1, pide plan2)", usuarioCancelado("plan1"), "otro-tier"],
    ["un periodo que ya vencio", usuarioCancelado("plan2", AHORA - DIA_MS), "queda-menos-de-un-dia"],
    ["un periodo que vence justo ahora", usuarioCancelado("plan2", AHORA), "queda-menos-de-un-dia"],
    ["menos de un dia por delante", usuarioCancelado("plan2", AHORA + DIA_MS - 1), "queda-menos-de-un-dia"],
    ["cancelado sin fecha de fin", {
      subscription: { tier: "plan2", status: "cancelled" },
    }, "sin-fecha-de-fin"],
    ["un estado ilegible (fecha como number)", {
      subscription: { tier: "plan2", status: "cancelled", currentPeriodEnd: FIN },
    }, "estado-degradado"],
    ["un estado ilegible (status desconocido)", {
      subscription: { tier: "plan2", status: "canceled", currentPeriodEnd: ts(FIN) },
    }, "estado-degradado"],
    ["un estado ilegible (tier desconocido)", {
      subscription: { tier: "plan9", status: "cancelled", currentPeriodEnd: ts(FIN) },
    }, "estado-degradado"],
  ];

  for (const [caso, userData, motivo] of cortes) {
    it(`${caso}: no se difiere (${motivo}) y NO se lee nada`, async () => {
      const { input, lecturas } = armar({ userData });

      const r = await decidirDiferimiento(input);

      expect(r).toEqual({ diferir: false, motivo });
      expect(lecturas.planes).toBe(0);
      expect(lecturas.suscripciones).toEqual([]);
    });
  }

  it("loguea el motivo por el que se cobra en el acto", async () => {
    const { input } = armar({ userData: usuarioCancelado("plan3") });

    await decidirDiferimiento(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se cobra en el acto",
      expect.objectContaining({ uid: "t1", tier: "plan2", motivo: "otro-tier" }),
    );
  });
});

describe("decidirDiferimiento: sin un cobro real en MP no se difiere", () => {
  it("la suscripcion del plan nunca cobro (charged_quantity 0)", async () => {
    // El caso de la fecha futura sin pago: nuestro `currentPeriodEnd` dice que
    // le quedan dias, pero MP nunca cobro nada.
    const { input } = armar({
      subs: {
        p0: [pagada(ULTIMO_COBRO, {
          summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
        })],
      },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("el plan no tiene ninguna suscripcion en MP", async () => {
    const { input } = armar({ subs: { p0: [] } });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("la cuenta no tiene ningun plan (un PF sembrado a mano con el Admin SDK)", async () => {
    const { input, lecturas } = armar({ planes: [] });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("la unica evidencia esta en un plan de ALUMNO: no cuenta", async () => {
    const { input, lecturas } = armar({
      planes: [plan("alumno", 5, { producto: "athlete", tier: undefined })],
      subs: { alumno: [pagada(ULTIMO_COBRO)] },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    // Ni siquiera se le pregunta a MP por el.
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("la unica evidencia esta en un plan de OTRO tier: no cuenta", async () => {
    const { input, lecturas } = armar({
      planes: [plan("de-plan3", 5, { tier: "plan3" })],
      subs: { "de-plan3": [pagada(ULTIMO_COBRO)] },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("un cobro cuyos datos no se entienden no es evidencia", async () => {
    const { input } = armar({
      subs: {
        p0: [pagada(ULTIMO_COBRO, {
          auto_recurring: { frequency: 30, frequency_type: "days" },
        })],
      },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("el pago existe pero vence en menos de un dia aunque nuestro fin sea lejano", async () => {
    // El cobro solo cubre hasta dentro de 12 horas. Nuestro `currentPeriodEnd`
    // esta corrido hacia adelante: no se le regalan dias al PF.
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 30 * DIA_MS),
      subs: { p0: [pagada("2026-08-08T00:00:00.000Z")] },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "pago-vence-pronto" });
  });

  it("el pago ya vencio y nuestro fin sigue en el futuro", async () => {
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 30 * DIA_MS),
      subs: { p0: [pagada("2026-05-01T12:00:00.000Z")] },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "pago-vence-pronto" });
  });
});

describe("decidirDiferimiento: que planes se revisan, y hasta donde", () => {
  it("toma el plan MAS NUEVO que muestra un cobro y no sigue", async () => {
    const { input, lecturas } = armar({
      planes: [plan("viejo", 60), plan("nuevo", 10), plan("medio", 30)],
      subs: {
        nuevo: [pagada("2026-08-20T12:00:00.000Z")],
        medio: [pagada("2026-08-01T12:00:00.000Z")],
        viejo: [pagada("2026-07-01T12:00:00.000Z")],
      },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["nuevo"]);
  });

  it("salta los planes nuevos SIN cobro (checkouts abandonados) hasta dar con el que pago", async () => {
    const { input, lecturas } = armar({
      planes: [plan("abandonado-2", 1), plan("abandonado-1", 5), plan("pago", 25)],
      subs: {
        "abandonado-2": [],
        "abandonado-1": [pagada(ULTIMO_COBRO, {
          summarized: { charged_quantity: 0 },
        })],
        pago: [pagada(ULTIMO_COBRO)],
      },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["abandonado-2", "abandonado-1", "pago"]);
  });

  it(`revisa a lo sumo ${MAX_PLANES_A_REVISAR} planes: el cuarto con pago no se ve`, async () => {
    const { input, lecturas } = armar({
      planes: [
        plan("p1", 1), plan("p2", 2), plan("p3", 3), plan("p4", 4), plan("p5", 5),
      ],
      subs: { p4: [pagada(ULTIMO_COBRO)], p5: [pagada(ULTIMO_COBRO)] },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(lecturas.suscripciones).toEqual(["p1", "p2", "p3"]);
  });

  it("lee los planes UNA sola vez", async () => {
    const { input, lecturas } = armar();

    await decidirDiferimiento(input);

    expect(lecturas.planes).toBe(1);
  });
});

describe("decidirDiferimiento: si no puede LEER, tira (nunca cae a cobrar en el acto)", () => {
  it("falla la lectura de los planes", async () => {
    // Seguir de largo seria abrir un checkout que cobra ya: el doble cobro.
    const { input } = armar({ planes: new Error("firestore caido") });

    await expect(decidirDiferimiento(input)).rejects.toThrow("firestore caido");
  });

  it("falla MP al buscar las suscripciones", async () => {
    const { input } = armar({ subs: { p0: new Error("MP 503") } });

    await expect(decidirDiferimiento(input)).rejects.toThrow("MP 503");
  });

  it("falla MP en el segundo plan, despues de un primero sin cobro", async () => {
    // Un fallo a mitad de camino no puede leerse como "no hubo evidencia".
    const { input } = armar({
      planes: [plan("p1", 1), plan("p2", 5)],
      subs: { p1: [], p2: new Error("MP 429") },
    });

    await expect(decidirDiferimiento(input)).rejects.toThrow("MP 429");
  });

  it("un estado que corta antes de leer NO tira aunque las lecturas esten rotas", async () => {
    // Las lecturas rotas solo importan cuando de verdad hacen falta.
    const { input } = armar({
      userData: usuarioCancelado("plan3"),
      planes: new Error("firestore caido"),
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "otro-tier" });
  });
});
