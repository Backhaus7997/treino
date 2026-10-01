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
  HOLGURA_PRUEBA_MS,
  MAX_PLANES_A_REVISAR,
  MIN_DIFERIMIENTO_MS,
  PlanDeLaCuenta,
  PruebaDiferidaInput,
  VENTANA_AUTORIZACION_MS,
  aplicarPruebaDiferidaAlEstado,
  aplicarPruebaDiferidaAlPeriodo,
  decidirDiferimiento,
  diasDePrueba,
  evidenciaDePago,
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

  // OJO: ninguna de estas suscripciones trae `date_created`, y es a proposito. Con
  // el, un `last_charged_date` ausente o invalido lo rescata el respaldo desde el
  // alta (ver el bloque de abajo); sin el, el respaldo no tiene de donde salir y
  // lo unico que queda es la fecha del ultimo cobro.
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
    ["sin last_charged_date (y sin date_created para el respaldo)",
      pagada("2026-08-20T12:00:00.000Z", {
        summarized: { charged_quantity: 1 },
      })],
    ["last_charged_date null (y sin date_created para el respaldo)",
      pagada("2026-08-20T12:00:00.000Z", {
        summarized: { charged_quantity: 1, last_charged_date: null },
      })],
    ["last_charged_date que no es fecha (y sin date_created para el respaldo)",
      pagada("manana")],
    ["last_charged_date numerico (y sin date_created para el respaldo)",
      pagada("2026-08-20T12:00:00.000Z", {
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
// El respaldo desde el alta.
//
// `last_charged_date` es lo unico de la evidencia que no esta medido contra MP.
// Si la busqueda lo omitiera, sin respaldo `pagadoHastaDe` daria `null` siempre y
// el diferimiento no se dispararia NUNCA (el PF seguiria pagando dos veces). Con
// `charged_quantity >= 1` y un `date_created` valido se reconstruye:
// `date_created + cobros * periodo`. Con una prueba gratis NO, porque el primer
// cobro no cae en `date_created` y no sabemos cuantos dias despues.
// ---------------------------------------------------------------------------

/**
 * Una suscripcion con cobros pero SIN `last_charged_date`, y con `date_created`: la
 * forma que tendria la respuesta de la busqueda si MP omitiera ese campo.
 */
function sinFechaDeCobro(
  over: Partial<MpPreapproval> = {},
  resumen: Record<string, unknown> = {},
): MpPreapproval {
  return {
    id: "s1",
    status: "cancelled",
    date_created: "2026-08-20T12:00:00.000Z",
    auto_recurring: {
      frequency: 1,
      frequency_type: "months",
      transaction_amount: 22000,
    },
    summarized: { charged_quantity: 1, pending_charge_quantity: 0, ...resumen },
    ...over,
  };
}

/** La prueba gratis de 13 dias que mandamos en un plan diferido. */
const PRUEBA_DE_13_DIAS = { frequency: 13, frequency_type: "days" };

describe("pagadoHastaDe: el respaldo desde el alta", () => {
  it("un cobro mensual: el alta mas UN periodo", () => {
    expect(pagadoHastaDe(sinFechaDeCobro()))
      .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("cada cobro exitoso compra UN periodo: tres cobros mensuales son alta + 3 meses", () => {
    const tres = sinFechaDeCobro(
      { date_created: "2026-06-20T12:00:00.000Z" },
      { charged_quantity: 3 },
    );

    expect(pagadoHastaDe(tres)).toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("un anual con un cobro cubre 12 meses desde el alta", () => {
    const anual = sinFechaDeCobro({
      date_created: "2026-03-01T09:30:00.000Z",
      auto_recurring: { frequency: 12, frequency_type: "months" },
    });

    expect(pagadoHastaDe(anual)).toBe(Date.parse("2027-03-01T09:30:00.000Z"));
  });

  it("la cantidad de cobros multiplica el periodo: dos anuales son 24 meses", () => {
    // El tope de 24 es del PERIODO (`frequency`), no del total.
    const dosAnuales = sinFechaDeCobro(
      {
        date_created: "2026-03-01T09:30:00.000Z",
        auto_recurring: { frequency: 12, frequency_type: "months" },
      },
      { charged_quantity: 2 },
    );

    expect(pagadoHastaDe(dosAnuales)).toBe(Date.parse("2028-03-01T09:30:00.000Z"));
  });

  it("el desborde de mes lo normaliza el calendario, igual que en reconcile", () => {
    const ms = pagadoHastaDe(sinFechaDeCobro({
      date_created: "2026-01-31T00:00:00.000Z",
    }));

    expect(new Date(ms as number).toISOString())
      .toBe("2026-03-03T00:00:00.000Z");
  });

  it("respeta el huso horario con el que MP manda el alta", () => {
    expect(pagadoHastaDe(sinFechaDeCobro({
      date_created: "2026-08-20T10:00:00.000-04:00",
    }))).toBe(Date.parse("2026-09-20T10:00:00.000-04:00"));
  });

  it("dice que la fecha salio del alta", () => {
    expect(evidenciaDePago(sinFechaDeCobro())).toEqual({
      hastaMs: Date.parse("2026-09-20T12:00:00.000Z"),
      fuente: "alta",
    });
  });

  // `last_charged_date` presente pero que no se entiende cuenta como ausente.
  const ultimoCobroQueNoSirve: [string, Record<string, unknown>][] = [
    ["ausente", {}],
    ["null", { last_charged_date: null }],
    ["un string vacio", { last_charged_date: "" }],
    ["un string que no es fecha", { last_charged_date: "ayer" }],
    ["un numero", { last_charged_date: 1_787_000_000_000 }],
    ["un objeto", { last_charged_date: { date: "2026-08-20" } }],
  ];

  for (const [caso, resumen] of ultimoCobroQueNoSirve) {
    it(`se usa cuando last_charged_date es ${caso}`, () => {
      expect(pagadoHastaDe(sinFechaDeCobro({}, resumen)))
        .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
    });
  }

  it("un plan SIN prueba (`free_trial` null) usa el respaldo", () => {
    const sub = sinFechaDeCobro({
      auto_recurring: {
        frequency: 1,
        frequency_type: "months",
        free_trial: null,
      },
    });

    expect(pagadoHastaDe(sub)).toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("y tambien con `free_trial` ausente o `undefined`", () => {
    const sub = sinFechaDeCobro({
      auto_recurring: {
        frequency: 1,
        frequency_type: "months",
        free_trial: undefined,
      },
    });

    expect(pagadoHastaDe(sub)).toBe(Date.parse("2026-09-20T12:00:00.000Z"));
    expect(pagadoHastaDe(sinFechaDeCobro()))
      .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });
});

describe("pagadoHastaDe: el respaldo NO corre con una prueba gratis", () => {
  // Con prueba el primer cobro cae cuando la prueba termina, no en `date_created`,
  // y no sabemos cuantos dias despues. Se prefiere no reconstruir nada: el
  // diferimiento no se dispara y el checkout cobra en el acto, como antes.
  const conPrueba: [string, unknown][] = [
    ["la de un plan nuestro (13 dias)", PRUEBA_DE_13_DIAS],
    ["en meses", { frequency: 1, frequency_type: "months" }],
    ["un objeto vacio: forma que no conocemos, no se asume que no hay prueba", {}],
    ["un string", "13 days"],
    ["un string vacio", ""],
    ["un booleano", true],
  ];

  for (const [caso, free_trial] of conPrueba) {
    it(`da null con free_trial ${caso}`, () => {
      const sub = sinFechaDeCobro({
        auto_recurring: { frequency: 1, frequency_type: "months", free_trial },
      });

      expect(pagadoHastaDe(sub)).toBeNull();
      expect(evidenciaDePago(sub)).toBeNull();
    });
  }

  it("con prueba, ni varios cobros ni un anual lo rescatan", () => {
    const sub = sinFechaDeCobro(
      {
        date_created: "2026-03-01T09:30:00.000Z",
        auto_recurring: {
          frequency: 12,
          frequency_type: "months",
          free_trial: PRUEBA_DE_13_DIAS,
        },
      },
      { charged_quantity: 2 },
    );

    expect(pagadoHastaDe(sub)).toBeNull();
  });

  it("pero con una prueba y `last_charged_date` valida SI hay evidencia: es la fuente principal", () => {
    // Un plan diferido nuestro DESPUES de su primer cobro: ya no hace falta
    // adivinar nada, MP dice cuando fue el cobro. La prueba solo le cierra la
    // puerta al respaldo, no a la fuente medida.
    const sub = sinFechaDeCobro(
      {
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          free_trial: PRUEBA_DE_13_DIAS,
        },
      },
      { last_charged_date: "2026-09-20T12:00:00.000Z" },
    );

    expect(evidenciaDePago(sub)).toEqual({
      hastaMs: Date.parse("2026-10-20T12:00:00.000Z"),
      fuente: "ultimo-cobro",
    });
  });
});

describe("pagadoHastaDe: lo que el respaldo exige", () => {
  const sinAlta: [string, Partial<MpPreapproval>][] = [
    ["date_created ausente", { date_created: undefined }],
    ["date_created null", { date_created: null }],
    ["date_created vacio", { date_created: "" }],
    ["date_created que no es fecha", { date_created: "ayer" }],
    ["date_created numerico", { date_created: 1_787_000_000_000 }],
  ];

  for (const [caso, patch] of sinAlta) {
    it(`da null con ${caso}: sin alta no hay desde donde contar`, () => {
      expect(pagadoHastaDe(sinFechaDeCobro(patch))).toBeNull();
    });
  }

  const periodoQueNoEntendemos: [string, unknown][] = [
    ["sin auto_recurring", undefined],
    ["auto_recurring null", null],
    ["auto_recurring que no es un objeto", "mensual"],
    ["frequency cero", { frequency: 0, frequency_type: "months" }],
    ["frequency negativa", { frequency: -1, frequency_type: "months" }],
    ["frequency fraccionaria", { frequency: 1.5, frequency_type: "months" }],
    ["frequency absurda (24 meses es el tope)", { frequency: 25, frequency_type: "months" }],
    ["frequency como string", { frequency: "1", frequency_type: "months" }],
    ["frequency_type days", { frequency: 30, frequency_type: "days" }],
    ["sin frequency_type", { frequency: 1 }],
    ["sin frequency", { frequency_type: "months" }],
  ];

  for (const [caso, auto_recurring] of periodoQueNoEntendemos) {
    it(`da null con ${caso}: un periodo que no entendemos no se multiplica`, () => {
      expect(pagadoHastaDe(sinFechaDeCobro({ auto_recurring }))).toBeNull();
    });
  }

  const cobrosQueNoSirven: [string, unknown][] = [
    ["cero", 0],
    ["negativo", -1],
    ["NaN", Number.NaN],
    ["infinito", Number.POSITIVE_INFINITY],
    ["un string", "1"],
    ["null", null],
    ["fraccionario: se multiplica, y un 1.5 no es una cantidad de cobros", 1.5],
    ["menor que uno", 0.5],
  ];

  for (const [caso, charged_quantity] of cobrosQueNoSirven) {
    it(`da null con charged_quantity ${caso}, aunque haya alta`, () => {
      expect(pagadoHastaDe(sinFechaDeCobro({}, { charged_quantity }))).toBeNull();
    });
  }

  it("sin charged_quantity tampoco, aunque haya alta", () => {
    const sub = sinFechaDeCobro({ summarized: { pending_charge_quantity: 0 } });

    expect(pagadoHastaDe(sub)).toBeNull();
  });

  it("sin summarized tampoco: el alta sola no prueba ningun cobro", () => {
    expect(pagadoHastaDe(sinFechaDeCobro({ summarized: undefined }))).toBeNull();
    expect(pagadoHastaDe(sinFechaDeCobro({ summarized: null }))).toBeNull();
  });

  it("una cantidad absurda no se sale del rango de fechas: da null, nunca NaN", () => {
    // `cobros * periodo` desborda el rango de `Date`. Sin la guarda saldria un
    // NaN, y `Math.min` lo propagaria hasta una fecha de diferimiento invalida.
    for (const charged_quantity of [1e15, Number.MAX_SAFE_INTEGER, 1e300]) {
      const r = pagadoHastaDe(sinFechaDeCobro({}, { charged_quantity }));

      expect(r).toBeNull();
    }
  });
});

describe("pagadoHastaDe: la fecha del ultimo cobro sigue siendo la fuente principal", () => {
  it("con las dos presentes gana last_charged_date, aunque den fechas distintas", () => {
    // Alta 20/6 con 3 cobros: el respaldo daria el 20/9. El ultimo cobro fue el
    // 25/8, o sea que MP dice 25/9.
    const sub = sinFechaDeCobro(
      { date_created: "2026-06-20T12:00:00.000Z" },
      { charged_quantity: 3, last_charged_date: "2026-08-25T12:00:00.000Z" },
    );

    expect(evidenciaDePago(sub)).toEqual({
      hastaMs: Date.parse("2026-09-25T12:00:00.000Z"),
      fuente: "ultimo-cobro",
    });
  });

  it("gana aunque el respaldo diera una fecha MAS LEJANA: no se toma el maximo", () => {
    // Alta 20/5 con 5 cobros: el respaldo daria el 20/10. La fuente medida dice
    // 25/9 y esa es la que vale.
    const sub = sinFechaDeCobro(
      { date_created: "2026-05-20T12:00:00.000Z" },
      { charged_quantity: 5, last_charged_date: "2026-08-25T12:00:00.000Z" },
    );

    expect(pagadoHastaDe(sub)).toBe(Date.parse("2026-09-25T12:00:00.000Z"));
  });

  it("gana aunque no haya date_created: el respaldo no es requisito de la fuente principal", () => {
    const sub = pagada("2026-08-20T12:00:00.000Z");

    expect(sub.date_created).toBeUndefined();
    expect(evidenciaDePago(sub)).toEqual({
      hastaMs: Date.parse("2026-09-20T12:00:00.000Z"),
      fuente: "ultimo-cobro",
    });
  });

  it("si la fuente principal es valida pero el periodo no se entiende, NO cae al respaldo", () => {
    // El respaldo tampoco entiende el periodo: no hay con que multiplicar.
    const sub = sinFechaDeCobro(
      { auto_recurring: { frequency: 0, frequency_type: "months" } },
      { last_charged_date: "2026-08-25T12:00:00.000Z" },
    );

    expect(pagadoHastaDe(sub)).toBeNull();
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
        fuenteDelPago: "ultimo-cobro",
        diasDePrueba: 13,
        diferidoHastaIso: "2026-09-20T12:00:00.000Z",
      }),
    );
    // Con la fecha del ultimo cobro no hay nada que avisar.
    expect(logger.warn).not.toHaveBeenCalled();
  });

  // ── Si MP omite `last_charged_date`: el respaldo desde el alta ──

  /** La suscripcion de p0 como la devolveria la busqueda SIN `last_charged_date`. */
  const SIN_FECHA_DE_COBRO: MpPreapproval = {
    id: "s0",
    status: "cancelled",
    date_created: ULTIMO_COBRO,
    auto_recurring: { frequency: 1, frequency_type: "months" },
    summarized: { charged_quantity: 1, pending_charge_quantity: 0 },
  };

  it("si la busqueda de MP omite last_charged_date, el alta alcanza para diferir", async () => {
    // Es el caso por el que existe el respaldo: sin el, el diferimiento no se
    // dispararia nunca y el PF volveria a pagar dos veces.
    const { input } = armar({ subs: { p0: [SIN_FECHA_DE_COBRO] } });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("y avisa con un warn que el pago se reconstruyo, porque no es un camino normal", async () => {
    const { input } = armar({ subs: { p0: [SIN_FECHA_DE_COBRO] } });

    await decidirDiferimiento(input);

    expect(logger.warn).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: MP no mando last_charged_date, el pago se " +
        "reconstruye desde el alta",
      { uid: "t1", tier: "plan2", planConPago: "p0" },
    );
    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se difiere el primer cobro",
      expect.objectContaining({ fuenteDelPago: "alta" }),
    );
  });

  it("el respaldo tambien respeta la fecha MENOR: manda nuestro fin si es antes", async () => {
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 4 * DIA_MS),
      subs: { p0: [SIN_FECHA_DE_COBRO] },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: true, diferidoHastaMs: AHORA + 4 * DIA_MS });
  });

  it("con dos suscripciones en el plan, una con fecha de cobro y otra solo con alta, gana la mas lejana", async () => {
    const { input } = armar({
      userData: usuarioCancelado("plan2", AHORA + 40 * DIA_MS),
      subs: {
        p0: [
          pagada("2026-08-10T12:00:00.000Z", { id: "s-con-fecha" }),
          { ...SIN_FECHA_DE_COBRO, id: "s-solo-alta", date_created: "2026-08-25T12:00:00.000Z" },
        ],
      },
    });

    expect(await decidirDiferimiento(input)).toEqual({
      diferir: true,
      diferidoHastaMs: Date.parse("2026-09-25T12:00:00.000Z"),
    });
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

  it("sin last_charged_date y con prueba gratis el respaldo no corre: no se difiere", async () => {
    // Es un plan diferido nuestro cuya busqueda omite la fecha del ultimo cobro:
    // el primer cobro no cayo en `date_created`, asi que no se reconstruye nada y
    // el checkout cobra en el acto, como antes.
    const { input } = armar({
      subs: {
        p0: [{
          id: "s0",
          status: "cancelled",
          date_created: ULTIMO_COBRO,
          auto_recurring: {
            frequency: 1,
            frequency_type: "months",
            free_trial: { frequency: 13, frequency_type: "days" },
          },
          summarized: { charged_quantity: 1 },
        }],
      },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it("sin last_charged_date y sin date_created no hay de donde contar: no se difiere", async () => {
    const { input } = armar({
      subs: {
        p0: [{
          id: "s0",
          status: "cancelled",
          auto_recurring: { frequency: 1, frequency_type: "months" },
          summarized: { charged_quantity: 1 },
        }],
      },
    });

    expect(await decidirDiferimiento(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
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

// ---------------------------------------------------------------------------
// La otra mitad: como se lee, al reconciliar, un plan que nacio con prueba.
//
// Tres cosas de MP lo vuelven necesario (detalle en el encabezado de esa
// seccion del modulo): el link de un checkout no vence, `pending_charge_quantity`
// puede contar un cobro que todavia no corresponde, y una prueba cancelada
// deriva su fin de un periodo entero que nunca se pago.
// ---------------------------------------------------------------------------

const HORA_MS = 60 * 60 * 1000;

/** Una suscripcion en prueba: el plan se abrio hace 1 h y se autorizo hace 30 min. */
const EN_PRUEBA: PruebaDiferidaInput = {
  diferidoHastaMs: FIN,
  planCreadoMs: AHORA - HORA_MS,
  mpStatus: "authorized",
  statusHoy: "active",
  summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
  mpDateCreated: new Date(AHORA - 30 * 60 * 1000).toISOString(),
  nowMs: AHORA,
};

/** Una autorizacion `horas` despues de abrir el checkout. */
const autorizadaDespues = (horas: number, extraMs = 0): PruebaDiferidaInput => ({
  ...EN_PRUEBA,
  planCreadoMs: AHORA - 10 * DIA_MS,
  mpDateCreated: new Date(AHORA - 10 * DIA_MS + horas * HORA_MS + extraMs)
    .toISOString(),
});

describe("aplicarPruebaDiferidaAlEstado: autorizada a tiempo", () => {
  it("sin cobro pendiente queda active", () => {
    expect(aplicarPruebaDiferidaAlEstado(EN_PRUEBA)).toBe("active");
  });

  it("CON cobro pendiente tambien queda active: durante la prueba no se debe nada", () => {
    // Si MP cuenta el primer cobro programado como pendiente, el mapeo de
    // siempre diria `grace` y el PF recibiria un "no pudimos cobrar" sin que se
    // le haya intentado cobrar nada.
    const r = aplicarPruebaDiferidaAlEstado({
      ...EN_PRUEBA,
      statusHoy: "grace",
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    });

    expect(r).toBe("active");
  });

  it("la ventana de autorizacion es inclusiva: exactamente 24 h todavia vale", () => {
    expect(aplicarPruebaDiferidaAlEstado(autorizadaDespues(24))).toBe("active");
    expect(VENTANA_AUTORIZACION_MS).toBe(24 * HORA_MS);
  });

  it("y 24 h y un milisegundo ya no", () => {
    expect(aplicarPruebaDiferidaAlEstado(autorizadaDespues(24, 1))).toBe("pending");
  });

  it("autorizar ANTES de que exista el plan (reloj corrido) cuenta como a tiempo", () => {
    // Defensa contra el desfasaje entre el reloj de MP y el de Firestore: una
    // diferencia negativa nunca puede castigar a quien pago.
    const r = aplicarPruebaDiferidaAlEstado({
      ...EN_PRUEBA,
      mpDateCreated: new Date(AHORA - 3 * HORA_MS).toISOString(),
    });

    expect(r).toBe("active");
  });
});

describe("aplicarPruebaDiferidaAlEstado: el horizonte E + holgura", () => {
  const conPendiente = (nowMs: number): PruebaDiferidaInput => ({
    ...EN_PRUEBA,
    nowMs,
    statusHoy: "grace",
    summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
  });

  it("un milisegundo antes del horizonte sigue active", () => {
    expect(aplicarPruebaDiferidaAlEstado(
      conPendiente(FIN + HOLGURA_PRUEBA_MS - 1))).toBe("active");
  });

  it("en el horizonte exacto vuelve el mapeo de siempre: grace", () => {
    expect(aplicarPruebaDiferidaAlEstado(
      conPendiente(FIN + HOLGURA_PRUEBA_MS))).toBe("grace");
  });

  it("pasado el horizonte, un cobro pendiente es grace: el primer cobro ya tendria que haber salido", () => {
    expect(aplicarPruebaDiferidaAlEstado(
      conPendiente(FIN + 10 * DIA_MS))).toBe("grace");
  });

  it("pasado el horizonte sin cobro pendiente queda active, como cualquier plan", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...EN_PRUEBA,
      nowMs: FIN + 10 * DIA_MS,
      statusHoy: "active",
    });

    expect(r).toBe("active");
  });

  it("la holgura son 3 dias", () => {
    expect(HOLGURA_PRUEBA_MS).toBe(3 * DIA_MS);
  });
});

describe("aplicarPruebaDiferidaAlEstado: un link viejo pagado tarde", () => {
  it("autorizada varios dias despues de abrir el checkout: pending", () => {
    // El link de un checkout no vence. Pagado tarde, el primer cobro cae tarde
    // y el PF tendria plan pago sin haber pagado nada.
    expect(aplicarPruebaDiferidaAlEstado(autorizadaDespues(3 * 24)))
      .toBe("pending");
  });

  it("y es pending aunque no haya cobro pendiente", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      statusHoy: "active",
    });

    expect(r).toBe("pending");
  });

  it("y es pending aunque el mapeo dijera grace", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      statusHoy: "grace",
      summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
    });

    expect(r).toBe("pending");
  });

  it("vale tambien pasado el horizonte: el link viejo no se vuelve valido con el tiempo", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      nowMs: FIN + 30 * DIA_MS,
    });

    expect(r).toBe("pending");
  });

  const fechasQueFaltan: [string, Partial<PruebaDiferidaInput>][] = [
    ["el plan sin createdAt legible", { planCreadoMs: null }],
    ["el plan con createdAt NaN", { planCreadoMs: Number.NaN }],
    ["la suscripcion sin date_created", { mpDateCreated: undefined }],
    ["date_created null", { mpDateCreated: null }],
    ["date_created que no es fecha", { mpDateCreated: "ayer" }],
    ["date_created numerico", { mpDateCreated: AHORA }],
  ];

  for (const [caso, patch] of fechasQueFaltan) {
    it(`con ${caso} NO se asume que fue a tiempo: pending`, () => {
      // Ante la duda no se le da plan pago a una suscripcion que todavia no
      // cobro. Es el lado barato de equivocarse: el primer cobro real lo corrige.
      expect(aplicarPruebaDiferidaAlEstado({ ...EN_PRUEBA, ...patch }))
        .toBe("pending");
    });
  }
});

describe("aplicarPruebaDiferidaAlEstado: lo que NO toca", () => {
  it("desde el primer cobro real todo es como en cualquier plan", () => {
    // Un link viejo y un cobro pendiente: con cobros >= 1 ya no es una prueba.
    const r = aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      statusHoy: "grace",
      summarized: { charged_quantity: 1, pending_charge_quantity: 1 },
    });

    expect(r).toBe("grace");
  });

  it("con cobros >= 1 devuelve siempre el mapeo de siempre", () => {
    for (const statusHoy of ["active", "grace", "pending"] as const) {
      expect(aplicarPruebaDiferidaAlEstado({
        ...autorizadaDespues(5 * 24),
        statusHoy,
        summarized: { charged_quantity: 2 },
      })).toBe(statusHoy);
    }
  });

  const noDiferidos: [string, unknown][] = [
    ["sin diferidoHastaMs", undefined],
    ["diferidoHastaMs null", null],
    ["diferidoHastaMs NaN", Number.NaN],
    ["diferidoHastaMs infinito", Number.POSITIVE_INFINITY],
    ["diferidoHastaMs como string", String(FIN)],
    ["diferidoHastaMs como Timestamp", { toMillis: () => FIN }],
  ];

  for (const [caso, diferidoHastaMs] of noDiferidos) {
    it(`un plan ${caso} se lee como cualquier otro, aunque la fecha sea tardia`, () => {
      for (const statusHoy of ["active", "grace"] as const) {
        expect(aplicarPruebaDiferidaAlEstado({
          ...autorizadaDespues(5 * 24),
          diferidoHastaMs,
          statusHoy,
        })).toBe(statusHoy);
      }
    });
  }

  const noAutorizadas = ["pending", "paused", "cancelled", "loquesea", undefined, null];

  for (const mpStatus of noAutorizadas) {
    it(`MP ${String(mpStatus)}: el estado lo decide el mapeo de siempre`, () => {
      for (const statusHoy of ["pending", "paused", "cancelled"] as const) {
        expect(aplicarPruebaDiferidaAlEstado({
          ...autorizadaDespues(5 * 24),
          mpStatus,
          statusHoy,
        })).toBe(statusHoy);
      }
    });
  }

  it("charged_quantity ausente, basura o summarized roto se lee como `no cobro`", () => {
    // Una suscripcion recien autorizada no trae cobros: es el caso normal.
    for (const summarized of [
      undefined,
      null,
      "cobrado",
      {},
      { charged_quantity: null },
      { charged_quantity: "1" },
      { charged_quantity: Number.NaN },
      { charged_quantity: 0 },
    ]) {
      expect(aplicarPruebaDiferidaAlEstado({
        ...autorizadaDespues(5 * 24),
        summarized,
      })).toBe("pending");
    }
  });
});

describe("aplicarPruebaDiferidaAlPeriodo", () => {
  /** Una prueba cancelada antes de su primer cobro. */
  const cancelada = (periodEndMs: number | null, patch = {}) => ({
    ...EN_PRUEBA,
    mpStatus: "cancelled",
    statusHoy: "cancelled" as const,
    periodEndMs,
    ...patch,
  });

  it("cancelada: un fin pasado de E se acota a E", () => {
    // La cascada de `resolverFinDePeriodo` deriva "alta + un mes" de una
    // suscripcion que nunca cobro: ese mes no se pago.
    const unMesDespues = AHORA + 30 * DIA_MS;

    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(unMesDespues))).toBe(FIN);
  });

  it("cancelada: un fin ANTERIOR a E se respeta (min, no pisar)", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - 5 * DIA_MS)))
      .toBe(FIN - 5 * DIA_MS);
  });

  it("cancelada: un fin igual a E queda en E", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN))).toBe(FIN);
  });

  it("cancelada SIN fin por ningun camino: E, no `null`", () => {
    // Un `null` le sacaria el plan en el acto a alguien que si pago hasta E.
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(null))).toBe(FIN);
  });

  it("pausada se acota igual", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(AHORA + 90 * DIA_MS, {
      mpStatus: "paused",
      statusHoy: "paused" as const,
    }))).toBe(FIN);
  });

  it("autorizada o pendiente: el fin no se toca, ni siquiera si pasa de E", () => {
    for (const mpStatus of ["authorized", "pending"]) {
      expect(aplicarPruebaDiferidaAlPeriodo({
        ...EN_PRUEBA,
        mpStatus,
        periodEndMs: FIN + 40 * DIA_MS,
      })).toBe(FIN + 40 * DIA_MS);
    }
    expect(aplicarPruebaDiferidaAlPeriodo({ ...EN_PRUEBA, periodEndMs: null }))
      .toBeNull();
  });

  it("con cobros >= 1 no se acota nada: el PF ya esta pagando este plan", () => {
    const r = aplicarPruebaDiferidaAlPeriodo(cancelada(AHORA + 30 * DIA_MS, {
      summarized: { charged_quantity: 1, last_charged_date: "2026-09-20T12:00:00.000Z" },
    }));

    expect(r).toBe(AHORA + 30 * DIA_MS);
  });

  it("con cobros >= 1 y sin fin sigue siendo null, como en cualquier plan", () => {
    const r = aplicarPruebaDiferidaAlPeriodo(cancelada(null, {
      summarized: { charged_quantity: 3 },
    }));

    expect(r).toBeNull();
  });

  const noDiferidos: [string, unknown][] = [
    ["sin diferidoHastaMs", undefined],
    ["diferidoHastaMs null", null],
    ["diferidoHastaMs NaN", Number.NaN],
    ["diferidoHastaMs como string", String(FIN)],
  ];

  for (const [caso, diferidoHastaMs] of noDiferidos) {
    it(`un plan ${caso} conserva su fin tal cual`, () => {
      expect(aplicarPruebaDiferidaAlPeriodo(
        cancelada(AHORA + 30 * DIA_MS, { diferidoHastaMs }),
      )).toBe(AHORA + 30 * DIA_MS);
      expect(aplicarPruebaDiferidaAlPeriodo(
        cancelada(null, { diferidoHastaMs }),
      )).toBeNull();
    });
  }
});
