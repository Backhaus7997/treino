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

import { artDateKey } from "../mail/format";
import { MAX_FREE_TRIAL_DAYS, MpPreapproval } from "../subscriptions/mp/client";
import {
  ADELANTO_MAXIMO_DEL_COBRO_MS,
  DIA_MS,
  DIFERIR_PRIMER_COBRO_ENABLED,
  DecidirDiferimientoInput,
  HOLGURA_PRUEBA_MS,
  MAX_PLANES_A_REVISAR,
  MIN_DIFERIMIENTO_MS,
  PlanDeLaCuenta,
  PruebaDiferidaInput,
  VENTANA_AUTORIZACION_MS,
  aplicarPruebaDiferidaAlEstado,
  aplicarPruebaDiferidaAlPeriodo,
  cobroAntesDeLaPrueba,
  cobrosExitosos,
  decidirDiferimiento,
  diasDePrueba,
  evidenciaDePago,
  pagadoHastaDe,
  planesARevisar,
  situacionDeLaPrueba,
} from "../subscriptions/mp/diferir-primer-cobro";
import {
  MOTIVO_ABANDONO,
  MOTIVO_REEMPLAZO,
} from "../subscriptions/mp/motivos-terminal";
import { SubscriptionTier } from "../subscriptions/tier-config";

/** Timestamp de mentira con la unica operacion que el codigo usa. */
const ts = (ms: number) => ({ toMillis: () => ms });

/** Un "ahora" fijo: el reloj entra por parametro en todo lo que se prueba. */
const AHORA = Date.parse("2026-09-07T12:00:00.000Z");

beforeEach(() => jest.clearAllMocks());

// ---------------------------------------------------------------------------
// pagadoHastaDe: la evidencia de pago, leida de lo que MP dice que cobro.
// ---------------------------------------------------------------------------

/**
 * Una suscripcion con un cobro, tal como la devuelve la busqueda de MP.
 *
 * Trae montos POSITIVOS (`charged_amount` y `last_charged_amount`) a proposito: asi
 * la rama positiva de la regla de los montos corre en TODOS los tests del flujo
 * principal, y no solo en los que la prueban de frente. Un test que quiera la
 * suscripcion sin montos (MP que no los manda) pisa `summarized` entero.
 */
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
      charged_amount: 22000,
      last_charged_date: ultimoCobro,
      last_charged_amount: 22000,
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
  // Con prueba se espera que el primer cobro caiga cuando la prueba termina, no en
  // `date_created`, y no sabemos cuantos dias despues. Se prefiere no reconstruir
  // nada: el diferimiento no se dispara y el checkout cobra en el acto, como antes.
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
// Una autorizacion de $0 no es un pago.
//
// MP podria reportar la autorizacion de una prueba como `charged_quantity >= 1`
// con `charged_amount: 0` (no esta medido). Contarla como un pago convertiria el
// alta de una prueba en evidencia de que el PF pago un periodo entero.
// ---------------------------------------------------------------------------

/** Montos que NO son un pago: presentes, finitos, y en $0 o menos. */
const MONTOS_SIN_PAGO: [string, Record<string, unknown>][] = [
  ["charged_amount 0", { charged_amount: 0 }],
  ["charged_amount negativo", { charged_amount: -1 }],
  ["charged_amount '0.0' (string)", { charged_amount: "0.0" }],
  ["last_charged_amount 0", { last_charged_amount: 0 }],
  ["last_charged_amount '0' (el SDK lo tipa como string)", { last_charged_amount: "0" }],
  ["last_charged_amount '-5'", { last_charged_amount: "-5" }],
  ["los dos en 0", { charged_amount: 0, last_charged_amount: 0 }],
  ["uno positivo y el otro en 0", { charged_amount: 22000, last_charged_amount: 0 }],
];

/**
 * Montos que SI cuentan, o que no vinieron: la regla de la cantidad manda, como
 * siempre. Un monto que falta no puede dejar sin evidencia a todo plan.
 */
const MONTOS_QUE_CUENTAN: [string, Record<string, unknown>][] = [
  ["charged_amount positivo", { charged_amount: 22000 }],
  ["last_charged_amount positivo como string", { last_charged_amount: "22000.0" }],
  ["los dos positivos", { charged_amount: 44000, last_charged_amount: "22000" }],
  ["montos null", { charged_amount: null, last_charged_amount: null }],
  ["montos ausentes", {}],
  ["monto NaN (no es un numero finito)", { charged_amount: Number.NaN }],
  ["monto infinito (no es finito)", { charged_amount: Number.POSITIVE_INFINITY }],
  ["monto string vacio: no es un $0", { last_charged_amount: "" }],
  ["monto string en blanco", { last_charged_amount: "   " }],
  ["monto string que no es un numero", { last_charged_amount: "n/a" }],
  ["monto que es un objeto", { charged_amount: { amount: 0 } }],
];

describe("cobrosExitosos: un monto en $0 no es un pago", () => {
  it("devuelve la cantidad de cobros cuando no hay montos", () => {
    expect(cobrosExitosos({ charged_quantity: 3 })).toBe(3);
  });

  for (const [caso, montos] of MONTOS_SIN_PAGO) {
    it(`da 0 con ${caso}, aunque charged_quantity sea 1`, () => {
      expect(cobrosExitosos({ charged_quantity: 1, ...montos })).toBe(0);
    });
  }

  for (const [caso, montos] of MONTOS_QUE_CUENTAN) {
    it(`cuenta el cobro con ${caso}`, () => {
      expect(cobrosExitosos({ charged_quantity: 2, ...montos })).toBe(2);
    });
  }

  const sinCantidad: [string, unknown][] = [
    ["summarized undefined", undefined],
    ["summarized null", null],
    ["summarized que no es un objeto", "cobrado"],
    ["charged_quantity ausente", { charged_amount: 22000 }],
    ["charged_quantity 0", { charged_quantity: 0, charged_amount: 22000 }],
    ["charged_quantity NaN", { charged_quantity: Number.NaN }],
    ["charged_quantity como string", { charged_quantity: "1" }],
  ];

  for (const [caso, summarized] of sinCantidad) {
    it(`da 0 con ${caso}: un monto positivo no reemplaza a la cantidad`, () => {
      expect(cobrosExitosos(summarized)).toBe(0);
    });
  }
});

describe("pagadoHastaDe: una autorizacion de $0 no es evidencia de pago", () => {
  const conMontos = (montos: Record<string, unknown>) =>
    pagada("2026-08-20T12:00:00.000Z", {
      summarized: {
        charged_quantity: 1,
        last_charged_date: "2026-08-20T12:00:00.000Z",
        ...montos,
      },
    });

  for (const [caso, montos] of MONTOS_SIN_PAGO) {
    it(`da null con ${caso}, aunque haya last_charged_date`, () => {
      expect(pagadoHastaDe(conMontos(montos))).toBeNull();
      expect(evidenciaDePago(conMontos(montos))).toBeNull();
    });
  }

  for (const [caso, montos] of MONTOS_QUE_CUENTAN) {
    it(`sigue dando la fecha con ${caso}`, () => {
      expect(pagadoHastaDe(conMontos(montos)))
        .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
    });
  }

  it("el respaldo desde el alta tambien lo exige: charged_amount 0 sin last_charged_date da null", () => {
    expect(pagadoHastaDe(sinFechaDeCobro({}, { charged_amount: 0 }))).toBeNull();
    expect(pagadoHastaDe(sinFechaDeCobro({}, { last_charged_amount: "0" }))).toBeNull();
  });

  it("y con un monto positivo el respaldo sigue andando", () => {
    expect(pagadoHastaDe(sinFechaDeCobro({}, { charged_amount: 22000 })))
      .toBe(Date.parse("2026-09-20T12:00:00.000Z"));
  });

  it("una prueba nuestra que solo autorizo (cantidad 1, monto 0) no deja evidencia", () => {
    // La forma que tendria la suscripcion de un plan diferido recien autorizado si
    // MP contara la autorizacion como un cobro de $0.
    const autorizacion = sinFechaDeCobro(
      {
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          free_trial: PRUEBA_DE_13_DIAS,
        },
      },
      { charged_quantity: 1, charged_amount: 0, last_charged_amount: 0 },
    );

    expect(pagadoHastaDe(autorizacion)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// diasDePrueba: la cuenta de los dias, en CALENDARIO ARGENTINO.
//
// Antes era `ceil(tiempo exacto / 24 h)`, que le sumaba un dia a cualquiera con
// horas sobrantes. El caso real: un plan pago hasta el 1/11/2026 a las 11:47 ART y
// el checkout abierto el 2/10 a las 09:30 ART. Faltaban 30 dias y 2 horas, el
// `ceil` daba 31, MP mostraba "31 dias gratis" y el primer cobro caia el 2/11. Del
// 2/10 al 1/11 son 30.
//
// Ahora es la fecha argentina de E menos la de hoy. Los instantes van en UTC con su
// hora argentina al lado (ART = UTC-3, sin horario de verano) para poder recalcular
// cada numero a mano: los esperados salen de CONTAR dias de calendario, no de
// ajustar la formula hasta que de verde. Lo que se espera de MP (N corridas de 24 h
// desde la autorizacion) NO esta medido: estos tests fijan la cuenta, no a MP.
// ---------------------------------------------------------------------------

describe("diasDePrueba: dias de calendario argentino", () => {
  /** Vence el 1/11/2026 a las 14:47 UTC = 11:47 ART: el caso real. */
  const E_REAL = Date.parse("2026-11-01T14:47:00.000Z");
  const desde = (ahoraIso: string, e: number = E_REAL) =>
    diasDePrueba(e, Date.parse(ahoraIso));

  // ── Los numeros del caso real ──

  it("el caso real: del 2/10 (09:31 ART) al 1/11 (11:47 ART) son 30 dias, no 31", () => {
    // Calendario: octubre tiene 31 dias, asi que 2/10 + 29 = 31/10 y + 1 = 1/11: 30.
    // El tiempo exacto es 30 dias y 2 h 16 min, que con `ceil` daba 31.
    expect(desde("2026-10-02T12:31:00.000Z")).toBe(30);
  });

  it("desde el 8/10 a las 09:00 ART son 24", () => {
    // 8/10 + 23 = 31/10 y + 1 = 1/11: 24. Con `ceil` hubieran sido 25.
    expect(desde("2026-10-08T12:00:00.000Z")).toBe(24);
  });

  it("desde el 1/10 a las 15:50 ART son 31", () => {
    // 1/10 + 30 = 31/10 y + 1 = 1/11: 31. Aca E cae mas temprano en el dia que hoy
    // (11:47 contra 15:50), asi que no sobran horas: pasan 30 dias y 19 h 57 min, y el
    // calendario y el `ceil` coinciden.
    expect(desde("2026-10-01T18:50:00.000Z")).toBe(31);
  });

  // ── La medianoche es la ARGENTINA, no la de UTC ──

  it("a las 23:59 ART del 1/10 todavia es 1/10: 31", () => {
    // 2026-10-02T02:59Z = 1/10 a las 23:59 ART.
    expect(desde("2026-10-02T02:59:00.000Z")).toBe(31);
  });

  it("un minuto despues, a las 00:00 ART del 2/10, ya es 2/10: 30", () => {
    // 2026-10-02T03:00Z = 2/10 a las 00:00 ART. El dia argentino cambia a las 03:00
    // UTC, y la function corre en UTC.
    expect(desde("2026-10-02T03:00:00.000Z")).toBe(30);
  });

  it("la medianoche UTC NO es el borde: a las 21:00 ART del 1/10 sigue siendo 1/10", () => {
    // 2026-10-02T00:00Z ya es 2/10 en UTC, pero en Argentina son las 21:00 del 1/10.
    // Una cuenta con fechas UTC daria 30 aca.
    expect(desde("2026-10-02T00:00:00.000Z")).toBe(31);
  });

  // ── Hora sobrante: de E al final del dia o al principio ──

  it("E al final del dia argentino y hoy al principio: cuentan los dias, no las horas", () => {
    // Hoy 2/10 a las 00:01 ART (03:01Z); vence el 1/11 a las 23:59 ART (02:59Z del
    // 2/11). Pasan 30 dias y 23 h 58 min, pero del 2/10 al 1/11 son 30 dias de
    // calendario. Con `ceil` hubieran sido 31.
    const e = Date.parse("2026-11-02T02:59:00.000Z");

    expect(desde("2026-10-02T03:01:00.000Z", e)).toBe(30);
  });

  it("E al principio del dia argentino y hoy al final: 31 dias de calendario", () => {
    // Hoy 1/10 a las 23:59 ART (02:59Z del 2/10); vence el 1/11 a las 00:01 ART
    // (03:01Z). Pasan 30 dias y 2 min; del 1/10 al 1/11 son 31 dias de calendario.
    const e = Date.parse("2026-11-01T03:01:00.000Z");

    expect(desde("2026-10-02T02:59:00.000Z", e)).toBe(31);
  });

  it("un multiplo exacto de dias da esos dias, y un milisegundo menos tambien", () => {
    // AHORA es el lunes 7/9 a las 09:00 ART: 10 dias despues es el 17/9 a las 09:00.
    expect(diasDePrueba(AHORA + 10 * DIA_MS, AHORA)).toBe(10);
    expect(diasDePrueba(AHORA + 10 * DIA_MS - 1, AHORA)).toBe(10);
  });

  it("un milisegundo de mas NO suma un dia: sigue siendo el mismo dia de calendario", () => {
    // El `ceil` pasaba de 10 a 11 con un solo milisegundo.
    expect(diasDePrueba(AHORA + 10 * DIA_MS + 1, AHORA)).toBe(10);
  });

  // ── El minimo: 24 h por delante garantizan al menos 1 dia ──

  it("con exactamente MIN_DIFERIMIENTO_MS por delante da 1, a cualquier hora del dia", () => {
    // Sumar 24 h corre la fecha argentina exactamente un dia. Barrido cada 15 minutos
    // durante dos dias.
    for (let min = 0; min < 2 * 24 * 60; min += 15) {
      const ahora = Date.parse("2026-10-02T00:00:00.000Z") + min * 60_000;

      expect(diasDePrueba(ahora + MIN_DIFERIMIENTO_MS, ahora)).toBe(1);
    }
  });

  it("con MAS de MIN_DIFERIMIENTO_MS da al menos 1, nunca 0", () => {
    // Cada 15 minutos, con distintas horas sobrantes (de 1 ms a casi un dia).
    for (const sobra of [1, 60_000, 6 * 60 * 60 * 1000, DIA_MS - 1]) {
      for (let min = 0; min < 2 * 24 * 60; min += 15) {
        const ahora = Date.parse("2026-10-02T00:00:00.000Z") + min * 60_000;

        expect(diasDePrueba(ahora + MIN_DIFERIMIENTO_MS + sobra, ahora))
          .toBeGreaterThanOrEqual(1);
      }
    }
  });

  it("por debajo del minimo SI puede dar 0: por eso no se difiere", () => {
    // Hoy 2/10 a las 09:00 ART; vence ese mismo dia a las 22:00 ART (01:00Z del 3/10):
    // 13 horas, 0 dias de calendario. El cliente de MP no manda una prueba de 0.
    expect(desde("2026-10-02T12:00:00.000Z", Date.parse("2026-10-03T01:00:00.000Z")))
      .toBe(0);
  });

  // ── Un anual ──

  it("un anual recien cobrado: del 2/10/2026 al 1/10/2027 son 364 dias", () => {
    // Cobro el 1/10/2026 a las 11:47 ART + 12 meses = 1/10/2027 a las 11:47 ART
    // (14:47Z). Del 2/10/2026 al 2/10/2027 son 365 dias (no hay 29/2 en el medio),
    // menos uno: 364. Con `ceil` hubieran sido 365.
    const dias = desde("2026-10-02T12:31:00.000Z", Date.parse("2027-10-01T14:47:00.000Z"));

    expect(dias).toBe(364);
    // Y entra en el maximo que acepta el cliente de MP.
    expect(dias).toBeLessThanOrEqual(MAX_FREE_TRIAL_DAYS);
  });

  it("un anual que cruza un 29 de febrero: 365", () => {
    // Del 2/10/2027 al 2/10/2028 son 366 dias (incluye el 29/2/2028), menos uno.
    const dias = desde("2027-10-02T12:31:00.000Z", Date.parse("2028-10-01T14:47:00.000Z"));

    expect(dias).toBe(365);
    expect(dias).toBeLessThanOrEqual(MAX_FREE_TRIAL_DAYS);
  });

  // ── La propiedad que importa, barrida ──

  it("barrido: para cualquier hora del dia, ahora + N * 24 h cae el MISMO dia argentino que E", () => {
    // Si MP cuenta N corridas de 24 h desde la autorizacion (NO medido), el primer
    // cobro cae en `ahora + N * 24 h`. Se compara con `artDateKey`, la definicion de
    // "dia argentino" del repo, y no con la implementacion que se prueba.
    for (let min = 0; min < 3 * 24 * 60; min += 7) {
      const ahora = Date.parse("2026-10-01T00:00:00.000Z") + min * 60_000;
      const n = diasDePrueba(E_REAL, ahora);
      const cobro = ahora + n * DIA_MS;

      expect(artDateKey(cobro)).toBe(artDateKey(E_REAL));
      // Y a menos de un dia de la hora exacta de E, hacia cualquiera de los dos lados.
      expect(Math.abs(cobro - E_REAL)).toBeLessThan(DIA_MS);
    }
  });

  it("barrido: lo mismo variando la hora de E y el mes", () => {
    // Mas de mil pares (hoy, E): E en tres fechas distintas (una es un 29/2) y a todas
    // las horas del dia, hoy tambien a todas las horas. Siempre hay al menos 24 h.
    for (const diaDeE of ["2026-11-01", "2027-03-15", "2028-02-29"]) {
      for (let minE = 0; minE < 24 * 60; minE += 97) {
        const e = Date.parse(`${diaDeE}T00:00:00.000Z`) + minE * 60_000;
        for (let minAhora = 0; minAhora < 24 * 60; minAhora += 53) {
          const ahora = Date.parse("2026-10-02T00:00:00.000Z") + minAhora * 60_000;
          const n = diasDePrueba(e, ahora);

          expect(n).toBeGreaterThanOrEqual(1);
          expect(artDateKey(ahora + n * DIA_MS)).toBe(artDateKey(e));
          expect(Math.abs(ahora + n * DIA_MS - e)).toBeLessThan(DIA_MS);
        }
      }
    }
  });

  it("un valor que no es una fecha da NaN y NO tira: el cliente de MP lo rechaza como siempre", () => {
    // Sin esto, un `RangeError` crudo de `Intl` saldria en medio del checkout.
    for (const malo of [Number.NaN, Number.POSITIVE_INFINITY, 9e15]) {
      expect(Number.isNaN(diasDePrueba(malo, AHORA))).toBe(true);
      expect(Number.isNaN(diasDePrueba(AHORA, malo))).toBe(true);
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
      // Por defecto un plan CERRADO por una baja: la unica clase que puede ser la
      // evidencia de un pago (`reconcile.ts` lo marca `terminal`, sin motivo,
      // cuando MP dice `cancelled`). Un checkout sin pagar se arma con `abierto`.
      terminal: true,
      ...data,
    },
  };
}

/**
 * Un checkout que el PF abrio y NO pago (o que todavia no se dio de baja): no es
 * `terminal`. Cada toque del boton fuera de la ventana de reuso deja uno.
 */
const abierto = (
  id: string,
  edadDias: number,
  data: Record<string, unknown> = {},
): PlanDeLaCuenta => plan(id, edadDias, { terminal: undefined, ...data });

describe("planesARevisar", () => {
  const ids = (planes: PlanDeLaCuenta[], tier: SubscriptionTier = "plan2") =>
    planesARevisar(planes, tier, AHORA).ids;

  it("del mas nuevo al mas viejo, sin importar el orden en que llegan", () => {
    const planes = [plan("viejo", 40), plan("nuevo", 2), plan("medio", 15)];

    expect(ids(planes)).toEqual(["nuevo", "medio", "viejo"]);
  });

  it("deja afuera los planes de ALUMNO", () => {
    const planes = [
      plan("a1", 1, { producto: "athlete", tier: undefined }),
      plan("p1", 5),
    ];

    expect(ids(planes)).toEqual(["p1"]);
  });

  it("un alumno que ademas tiene tier escrito sigue afuera", () => {
    // Defensa: el filtro de producto no depende de que falte el tier.
    const planes = [plan("a1", 1, { producto: "athlete" })];

    expect(ids(planes)).toEqual([]);
  });

  it("deja afuera los planes de OTRO tier", () => {
    const planes = [plan("p3", 1, { tier: "plan3" }), plan("p2", 9)];

    expect(ids(planes)).toEqual(["p2"]);
  });

  it("un plan de PF anterior a `producto` (sin el campo) SI entra", () => {
    // Son todos los planes de PF que hay en produccion hoy, y los que mas
    // pueden haber pagado.
    const planes = [plan("legado", 30, { producto: undefined })];

    expect(ids(planes)).toEqual(["legado"]);
  });

  it("incluye cualquier ciclo del tier: el diferimiento es por plan, no por ciclo", () => {
    const planes = [
      plan("mensual", 3),
      plan("anual", 10, { cycle: "annual" }),
    ];

    expect(ids(planes)).toEqual(["mensual", "anual"]);
  });

  it(`no pasa de ${MAX_PLANES_A_REVISAR} planes: los mas nuevos`, () => {
    const planes = [
      plan("p5", 50), plan("p3", 30), plan("p1", 10), plan("p4", 40), plan("p2", 20),
    ];

    expect(ids(planes)).toEqual(["p1", "p2", "p3"]);
  });

  it("el tope se cuenta DESPUES de filtrar: otros tiers no gastan lugar", () => {
    const planes = [
      plan("x1", 1, { tier: "plan3" }),
      plan("x2", 2, { tier: "plan3" }),
      plan("x3", 3, { tier: "plan1" }),
      plan("a1", 4, { producto: "athlete" }),
      plan("p1", 20),
    ];

    expect(ids(planes)).toEqual(["p1"]);
  });

  it("un plan sin fecha legible va al final, pero no se descarta", () => {
    // Sigue pudiendo ser el que pago. Solo pierde frente a los que tienen fecha.
    const planes = [
      plan("sin-fecha", 0, { createdAt: undefined }),
      plan("sentinel", 0, { createdAt: "__ts__" }),
      plan("con-fecha", 90),
    ];

    expect(ids(planes)[0]).toBe("con-fecha");
    expect(ids(planes)).toHaveLength(3);
  });

  it("sin planes da una lista vacia", () => {
    expect(planesARevisar([], "plan2", AHORA)).toEqual({ candidatos: 0, ids: [] });
  });
});

describe("planesARevisar: el plan que pago no se cae del tope", () => {
  const ids = (planes: PlanDeLaCuenta[]) => planesARevisar(planes, "plan2", AHORA).ids;

  // ── Los toques sin pagar ──

  it("deja afuera los checkouts que el PF abrio y no pago: no son terminal", () => {
    expect(ids([abierto("sin-pagar", 1), plan("pago", 20)])).toEqual(["pago"]);
  });

  it("tres toques sin pagar NO empujan afuera al plan que pago", () => {
    // El bug: cada toque fuera de la ventana de reuso abre un plan. Cortando por
    // recencia ANTES de filtrar, el plan que pago era el cuarto mas nuevo, no se
    // revisaba, y al PF se le cobraba en el acto lo que ya tenia pago.
    const planes = [
      abierto("toque-4", 1),
      abierto("toque-3", 2),
      abierto("toque-2", 3),
      abierto("toque-1", 4),
      plan("pago", 20),
    ];

    const r = planesARevisar(planes, "plan2", AHORA);

    expect(r.ids).toEqual(["pago"]);
    expect(r.candidatos).toBe(1);
  });

  it("cada cambio de ciclo abre un plan: tampoco lo empuja", () => {
    const planes = [
      abierto("anual-2", 1, { cycle: "annual" }),
      abierto("mensual-2", 2),
      abierto("anual-1", 3, { cycle: "annual" }),
      abierto("mensual-1", 4),
      plan("pago", 25),
    ];

    expect(ids(planes)).toEqual(["pago"]);
  });

  it("`terminal` tiene que ser exactamente `true`: nada que se le parezca", () => {
    for (const terminal of ["true", 1, "yes", false, null, undefined, {}]) {
      expect(ids([plan("raro", 1, { terminal }), plan("pago", 20)]))
        .toEqual(["pago"]);
    }
  });

  // ── Los terminal: solo el ABANDONO queda afuera ──

  it("deja afuera un checkout ABANDONADO que el barrido marco terminal", () => {
    // El barrido nocturno marca `terminal` a un checkout sin suscripcion a los 30
    // dias, con MOTIVO_ABANDONO. Sin descartarlo, un PF con un anual y varios
    // toques de hace mas de un mes volveria a empujar fuera al plan que pago.
    const planes = [
      plan("abandonado-3", 40, { terminalReason: MOTIVO_ABANDONO }),
      plan("abandonado-2", 50, { terminalReason: MOTIVO_ABANDONO }),
      plan("abandonado-1", 60, { terminalReason: MOTIVO_ABANDONO }),
      plan("pago", 200),
    ];

    expect(ids(planes)).toEqual(["pago"]);
  });

  it("un plan pagado que despues se REEMPLAZO sigue contando", () => {
    // `darDeBajaUnPlan` lo marca `terminal` con MOTIVO_REEMPLAZO, y SOLO despues de
    // encontrarle una suscripcion a la que dar de baja: tuvo una de verdad, y es la
    // evidencia de ese pago.
    const planes = [plan("reemplazado", 5, { terminalReason: MOTIVO_REEMPLAZO })];

    const r = planesARevisar(planes, "plan2", AHORA);

    expect(r.ids).toEqual(["reemplazado"]);
    expect(r.candidatos).toBe(1);
  });

  it("los reemplazados y las bajas cuentan juntos, del mas nuevo al mas viejo", () => {
    const planes = [
      plan("baja", 30),
      plan("reemplazado", 10, { terminalReason: MOTIVO_REEMPLAZO }),
      plan("abandonado", 5, { terminalReason: MOTIVO_ABANDONO }),
    ];

    expect(ids(planes)).toEqual(["reemplazado", "baja"]);
  });

  it("un motivo que no conocemos tampoco lo deja afuera: solo se descarta el abandono", () => {
    // Si manana el reconciliador estrena un motivo, por defecto no se pierde
    // evidencia de pago.
    expect(ids([plan("x", 1, { terminalReason: "otro motivo" }), plan("pago", 20)]))
      .toEqual(["x", "pago"]);
  });

  it("un `terminalReason` que no es un string no cuenta como motivo", () => {
    for (const terminalReason of [undefined, null, 0, false]) {
      expect(ids([plan("baja", 1, { terminalReason })])).toEqual(["baja"]);
    }
  });

  // ── Volver a suscribirse y cancelar, varias veces ──

  it("tres vueltas de suscribirse con prueba y cancelar NO empujan afuera al plan que pago", () => {
    // Cada vuelta deja un plan terminal que nunca cobro, y todos comparten E (el
    // fin del periodo pago, todavia lejos). Ninguno puede ser evidencia.
    const E = AHORA + 13 * DIA_MS;
    const planes = [
      plan("vuelta-3", 1, { diferidoHastaMs: E }),
      plan("vuelta-2", 2, { diferidoHastaMs: E }),
      plan("vuelta-1", 3, { diferidoHastaMs: E }),
      plan("pago", 20),
    ];

    const r = planesARevisar(planes, "plan2", AHORA);

    expect(r.ids).toEqual(["pago"]);
    expect(r.candidatos).toBe(1);
  });

  it("un plan con prueba cuyo E ya paso SI entra: pudo haber cobrado", () => {
    // La segunda generacion: el diferido cobro en E, y despues se cancelo.
    const planes = [
      plan("diferido-cobrado", 10, { diferidoHastaMs: AHORA - 3 * DIA_MS }),
      plan("pago", 40),
    ];

    expect(ids(planes)).toEqual(["diferido-cobrado", "pago"]);
  });

  it("el borde: con E a exactamente un dia SI entra, con un milisegundo mas no", () => {
    // Un dia es el adelanto maximo que suponemos: con dias de calendario argentino el
    // primer cobro cae el mismo dia que E pero a la hora en que se autorizo, o sea
    // hasta casi un dia ANTES de la hora exacta de E (hoy a las 00:01 ART y E a las
    // 23:59 de ese dia: 23 h 58 min antes). Hasta ahi el plan entra, por las dudas.
    expect(ids([plan("justo", 1, { diferidoHastaMs: AHORA + ADELANTO_MAXIMO_DEL_COBRO_MS })]))
      .toEqual(["justo"]);
    expect(ids([plan("lejos", 1, {
      diferidoHastaMs: AHORA + ADELANTO_MAXIMO_DEL_COBRO_MS + 1,
    })])).toEqual([]);
  });

  it("un `diferidoHastaMs` que no es un numero se ignora: el plan entra como cualquier otro", () => {
    for (const diferidoHastaMs of ["manana", Number.NaN, null, {}]) {
      expect(ids([plan("raro", 1, { diferidoHastaMs })])).toEqual(["raro"]);
    }
  });

  // ── La cuenta de candidatos, que va al log ──

  it("cuenta los candidatos ANTES del tope", () => {
    const planes = [
      plan("c5", 50), plan("c4", 40), plan("c3", 30), plan("c2", 20), plan("c1", 10),
      abierto("sin-pagar", 1),
      plan("otro-tier", 2, { tier: "plan3" }),
      plan("alumno", 3, { producto: "athlete" }),
    ];

    const r = planesARevisar(planes, "plan2", AHORA);

    expect(r.candidatos).toBe(5);
    expect(r.ids).toEqual(["c1", "c2", "c3"]);
  });
});

// ---------------------------------------------------------------------------
// decidirDiferimiento: la decision completa, con las dos lecturas inyectadas.
// ---------------------------------------------------------------------------

/**
 * Un fin de periodo en el futuro: el 20/9/2026 a las 09:00 ART. `AHORA` es el 7/9 a
 * las 09:00 ART, asi que son 13 dias de calendario (7/9 + 13 = 20/9) y tambien 13
 * dias de 24 h exactos: la misma hora del dia, por eso la cuenta por calendario y la
 * del tiempo exacto coinciden en estas fixtures.
 */
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
    // Explicito: los tests de la decision no dependen del valor de la constante, asi
    // que flipearla (el rollback) no los pone rojos. El camino sin parametro tiene
    // su propio test, que tampoco asume el valor.
    habilitado: true,
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
        // Del 7/9 (AHORA, 09:00 ART) al 20/9 (FIN, 09:00 ART): 7 + 13 = 20.
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
    ["una fecha de fin que no es un numero (NaN)", {
      subscription: { tier: "plan2", status: "cancelled", currentPeriodEnd: ts(Number.NaN) },
    }, "sin-fecha-de-fin"],
    ["una fecha de fin infinita", {
      subscription: {
        tier: "plan2",
        status: "cancelled",
        currentPeriodEnd: ts(Number.POSITIVE_INFINITY),
      },
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

  it("salta los planes cerrados que nunca cobraron hasta dar con el que pago", async () => {
    // Son planes terminales (MP los dio de baja) cuya suscripcion nunca llego a
    // cobrar: hay que preguntarle a MP para saberlo, y se sigue con el siguiente.
    const { input, lecturas } = armar({
      planes: [plan("sin-cobro-2", 1), plan("sin-cobro-1", 5), plan("pago", 25)],
      subs: {
        "sin-cobro-2": [],
        "sin-cobro-1": [pagada(ULTIMO_COBRO, {
          summarized: { charged_quantity: 0 },
        })],
        pago: [pagada(ULTIMO_COBRO)],
      },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["sin-cobro-2", "sin-cobro-1", "pago"]);
  });

  it("tres toques sin pagar NO le sacan el diferimiento al PF que pago", async () => {
    // Cada toque fuera de la ventana de reuso abre un plan en MP. Cortando por
    // recencia antes de filtrar, el plan que pago era el cuarto mas nuevo, no se
    // revisaba, y el PF terminaba pagando en el acto lo que ya tenia pago.
    const { input, lecturas } = armar({
      planes: [
        abierto("toque-3", 1),
        abierto("toque-2", 2),
        abierto("toque-1", 3),
        abierto("cambio-de-ciclo", 4, { cycle: "annual" }),
        plan("p0", 20),
      ],
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    // A MP solo se le pregunta por el plan que puede haber cobrado.
    expect(lecturas.suscripciones).toEqual(["p0"]);
  });

  it("tres vueltas de suscribirse con prueba y cancelar tampoco: el plan que pago se sigue viendo", async () => {
    const E = FIN;
    const { input, lecturas } = armar({
      planes: [
        plan("vuelta-3", 1, { diferidoHastaMs: E }),
        plan("vuelta-2", 2, { diferidoHastaMs: E }),
        plan("vuelta-1", 3, { diferidoHastaMs: E }),
        plan("p0", 20),
      ],
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["p0"]);
  });

  it("un checkout abandonado que el barrido ya marco terminal tampoco empuja al que pago", async () => {
    // Un anual (periodo largo) con varios toques de hace mas de un mes.
    const { input, lecturas } = armar({
      planes: [
        plan("abandonado-3", 40, { terminalReason: MOTIVO_ABANDONO }),
        plan("abandonado-2", 50, { terminalReason: MOTIVO_ABANDONO }),
        plan("abandonado-1", 60, { terminalReason: MOTIVO_ABANDONO }),
        plan("p0", 200),
      ],
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["p0"]);
  });

  it("un plan pagado que despues se reemplazo SIGUE dando evidencia", async () => {
    // El caso real: el plan que pago quedo marcado MOTIVO_REEMPLAZO cuando otro
    // plan lo reemplazo. Sin contarlo, a ese PF se le cobraba en el acto lo que ya
    // tenia pago.
    const { input, lecturas } = armar({
      planes: [plan("reemplazado", 10, { terminalReason: MOTIVO_REEMPLAZO })],
      subs: { reemplazado: [pagada(ULTIMO_COBRO)] },
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["reemplazado"]);
  });

  it("sin ningun plan cerrado no se le pregunta nada a MP", async () => {
    const { input, lecturas } = armar({
      planes: [abierto("toque-2", 1), abierto("toque-1", 2)],
    });

    const r = await decidirDiferimiento(input);

    expect(r).toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("loguea cuantos planes habia, cuantos eran candidatos y cuantos se revisaron", async () => {
    // Para poder explicar despues un "sin-pago-comprobado": si `candidatos` es 0,
    // no habia ningun plan cerrado que mirar.
    const { input } = armar({
      planes: [
        abierto("toque-2", 1),
        abierto("toque-1", 2),
        plan("otro-tier", 3, { tier: "plan3" }),
        // Cuatro candidatos: el tope deja afuera al mas viejo, y p0 es el tercero.
        plan("c2", 4), plan("c1", 5), plan("p0", 6), plan("c0", 7),
      ],
    });

    await decidirDiferimiento(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se difiere el primer cobro",
      expect.objectContaining({
        planesEnLaCuenta: 7,
        candidatos: 4,
        planesRevisados: MAX_PLANES_A_REVISAR,
      }),
    );
  });

  it("el conteo tambien va al log cuando no se difiere", async () => {
    const { input } = armar({ planes: [abierto("toque", 1), plan("c1", 2)], subs: { c1: [] } });

    await decidirDiferimiento(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se cobra en el acto",
      expect.objectContaining({
        motivo: "sin-pago-comprobado",
        planesEnLaCuenta: 2,
        candidatos: 1,
        planesRevisados: 1,
      }),
    );
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
// El atajo del doble click. Sin el, cada toque de un PF dado de baja pagaba hasta
// tres busquedas en MP aunque el checkout diferido ya estuviera abierto y fuera a
// reusarse. La verificacion contra MP se hizo cuando se abrio.
// ---------------------------------------------------------------------------

describe("decidirDiferimiento: el atajo del doble click", () => {
  /** Un lector del checkout abierto que anota cuantas veces lo llamaron. */
  function checkoutAbierto(valor: number | null | Error) {
    const llamadas = { n: 0 };
    const lector = async (): Promise<number | null> => {
      llamadas.n += 1;
      if (valor instanceof Error) throw valor;
      return valor;
    };
    return { llamadas, lector };
  }

  it("con un checkout diferido abierto devuelve esa fecha y NO busca nada", async () => {
    const abierto = checkoutAbierto(FIN);
    const { input, lecturas } = armar();

    const r = await decidirDiferimiento({
      ...input,
      diferidoDelCheckoutAbierto: abierto.lector,
    });

    expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(abierto.llamadas.n).toBe(1);
    // Ni los planes de Firestore ni una sola busqueda en MP.
    expect(lecturas.planes).toBe(0);
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("devuelve EXACTAMENTE la fecha guardada, no la que saldria de buscar", async () => {
    // `abrirCheckout` la compara para reusar: devolver otra crearia un plan nuevo
    // sin haber verificado el pago. La guardada es 2 dias anterior a lo que
    // daria la busqueda (FIN), y es la que tiene que volver.
    const guardada = FIN - 2 * DIA_MS;
    const { input } = armar();

    const r = await decidirDiferimiento({
      ...input,
      diferidoDelCheckoutAbierto: checkoutAbierto(guardada).lector,
    });

    expect(r).toEqual({ diferir: true, diferidoHastaMs: guardada });
  });

  it("loguea que reuso el diferimiento, sin salir a MP", async () => {
    const { input } = armar();

    await decidirDiferimiento({
      ...input,
      diferidoDelCheckoutAbierto: checkoutAbierto(FIN).lector,
    });

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se reusa el diferimiento del checkout abierto, " +
        "no se busca en MP",
      { uid: "t1", tier: "plan2", diferidoHastaIso: "2026-09-20T12:00:00.000Z" },
    );
  });

  it("el borde: una fecha a exactamente un dia SI sirve", async () => {
    const { input, lecturas } = armar();
    const borde = AHORA + MIN_DIFERIMIENTO_MS;

    const r = await decidirDiferimiento({
      ...input,
      diferidoDelCheckoutAbierto: checkoutAbierto(borde).lector,
    });

    expect(r).toEqual({ diferir: true, diferidoHastaMs: borde });
    expect(lecturas.planes).toBe(0);
  });

  // Cualquiera de estas cosas deja al checkout abierto sin servir de atajo: se
  // busca en MP como siempre, y esa busqueda manda.
  const sinAtajo: [string, number | null][] = [
    ["no hay checkout abierto", null],
    ["la fecha guardada es NaN", Number.NaN],
    ["la fecha guardada es infinita", Number.POSITIVE_INFINITY],
    ["a la fecha guardada le queda menos de un dia", AHORA + MIN_DIFERIMIENTO_MS - 1],
    ["la fecha guardada ya paso", AHORA - DIA_MS],
    ["la fecha guardada pasa de nuestro fin de periodo", FIN + 1],
  ];

  for (const [caso, guardada] of sinAtajo) {
    it(`si ${caso}, no hay atajo: se busca en MP`, async () => {
      const { input, lecturas } = armar();

      const r = await decidirDiferimiento({
        ...input,
        diferidoDelCheckoutAbierto: checkoutAbierto(guardada).lector,
      });

      expect(r).toEqual({ diferir: true, diferidoHastaMs: FIN });
      expect(lecturas.planes).toBe(1);
      expect(lecturas.suscripciones).toEqual(["p0"]);
    });
  }

  it("sin lector del checkout abierto se busca siempre", async () => {
    const { input, lecturas } = armar();

    await decidirDiferimiento(input);

    expect(lecturas.planes).toBe(1);
  });

  it("no mira el checkout abierto si la elegibilidad barata falla: ninguna lectura antes", async () => {
    const cortes: Record<string, unknown>[] = [
      usuarioCancelado("plan3"),
      { role: "trainer" },
      { subscription: { tier: "plan2", status: "active", currentPeriodEnd: ts(FIN) } },
      usuarioCancelado("plan2", AHORA - DIA_MS),
      usuarioCancelado("plan2", AHORA + MIN_DIFERIMIENTO_MS - 1),
    ];

    for (const userData of cortes) {
      const abierto = checkoutAbierto(FIN);
      const { input, lecturas } = armar({ userData });

      const r = await decidirDiferimiento({
        ...input,
        diferidoDelCheckoutAbierto: abierto.lector,
      });

      expect(r.diferir).toBe(false);
      expect(abierto.llamadas.n).toBe(0);
      expect(lecturas.planes).toBe(0);
    }
  });

  it("si el lector del checkout abierto tira, tira: no se cae a cobrar en el acto", async () => {
    const { input } = armar();

    await expect(decidirDiferimiento({
      ...input,
      diferidoDelCheckoutAbierto: checkoutAbierto(new Error("firestore caido")).lector,
    })).rejects.toThrow("firestore caido");
  });
});

// ---------------------------------------------------------------------------
// El interruptor. Existe por si MP rechaza (o cuenta distinto) una prueba de dias,
// que es lo unico del diseño que no se pudo probar contra la API.
// ---------------------------------------------------------------------------

describe("decidirDiferimiento: el interruptor", () => {
  // Los dos estados se prueban por el parametro `habilitado`, no por el valor de la
  // constante: el interruptor se puede flipear (es el rollback) sin tocar un test.

  it("encendido difiere", async () => {
    const { input } = armar();

    expect(await decidirDiferimiento({ ...input, habilitado: true }))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("apagado NUNCA difiere, aunque todo lo demas lo permita", async () => {
    const { input } = armar();

    expect(await decidirDiferimiento({ ...input, habilitado: false }))
      .toEqual({ diferir: false, motivo: "deshabilitado" });
  });

  it("sin pasarlo vale la constante, sea cual sea su valor", async () => {
    // Fija el CABLEADO del default sin asumir el valor: el resultado sin el
    // parametro es exactamente el que da pasarle la constante.
    const { input } = armar();
    delete (input as { habilitado?: boolean }).habilitado;

    const sinParametro = await decidirDiferimiento(input);
    const conLaConstante = await decidirDiferimiento({
      ...input,
      habilitado: DIFERIR_PRIMER_COBRO_ENABLED,
    });

    expect(sinParametro).toEqual(conLaConstante);
  });

  it("apagado no lee NADA: ni planes, ni MP, ni el checkout abierto", async () => {
    const llamadas = { abierto: 0 };
    const { input, lecturas } = armar();

    await decidirDiferimiento({
      ...input,
      habilitado: false,
      diferidoDelCheckoutAbierto: async () => {
        llamadas.abierto += 1;
        return FIN;
      },
    });

    expect(lecturas.planes).toBe(0);
    expect(lecturas.suscripciones).toEqual([]);
    expect(llamadas.abierto).toBe(0);
  });

  it("apagado gana incluso con un checkout diferido abierto: no se lo reusa", async () => {
    // El rollback tiene que ser real: con el interruptor apagado el pedido no
    // lleva diferimiento y `abrirCheckout` abre un plan normal.
    const { input } = armar();

    const r = await decidirDiferimiento({
      ...input,
      habilitado: false,
      diferidoDelCheckoutAbierto: async () => FIN,
    });

    expect(r.diferir).toBe(false);
  });

  it("apagado loguea el motivo", async () => {
    const { input } = armar();

    await decidirDiferimiento({ ...input, habilitado: false });

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se cobra en el acto",
      expect.objectContaining({ uid: "t1", motivo: "deshabilitado" }),
    );
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
    // El link de un checkout no vence. Pagado tarde, el primer cobro caeria tarde
    // (suponiendo que la prueba corre desde la autorizacion) y el PF tendria plan
    // pago sin haber pagado nada.
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

// ---------------------------------------------------------------------------
// situacionDeLaPrueba: la clasificacion de la que sale el estado Y los warns.
//
// El reconciliador loguea un warn en dos de estas situaciones (la autorizacion
// tardia deja sin plan a quien autorizo un pago; la prueba vencida sin cobro
// podria estar dando acceso gratis), y decide el estado con la misma funcion.
// ---------------------------------------------------------------------------

describe("situacionDeLaPrueba", () => {
  it("a tiempo y antes del horizonte: en-prueba", () => {
    expect(situacionDeLaPrueba(EN_PRUEBA)).toBe("en-prueba");
  });

  it("a tiempo, un milisegundo antes del horizonte: en-prueba", () => {
    expect(situacionDeLaPrueba({
      ...EN_PRUEBA,
      nowMs: FIN + HOLGURA_PRUEBA_MS - 1,
    })).toBe("en-prueba");
  });

  it("a tiempo y en el horizonte exacto: vencida", () => {
    expect(situacionDeLaPrueba({
      ...EN_PRUEBA,
      nowMs: FIN + HOLGURA_PRUEBA_MS,
    })).toBe("vencida");
  });

  it("a tiempo y mucho despues del horizonte: vencida", () => {
    expect(situacionDeLaPrueba({
      ...EN_PRUEBA,
      nowMs: FIN + 30 * DIA_MS,
    })).toBe("vencida");
  });

  it("autorizada fuera de la ventana: fuera-de-ventana, antes o despues del horizonte", () => {
    for (const nowMs of [AHORA, FIN + HOLGURA_PRUEBA_MS + DIA_MS]) {
      expect(situacionDeLaPrueba({ ...autorizadaDespues(5 * 24), nowMs }))
        .toBe("fuera-de-ventana");
    }
  });

  it("sin fechas que se entiendan: fuera-de-ventana", () => {
    expect(situacionDeLaPrueba({ ...EN_PRUEBA, planCreadoMs: null }))
      .toBe("fuera-de-ventana");
    expect(situacionDeLaPrueba({ ...EN_PRUEBA, mpDateCreated: "ayer" }))
      .toBe("fuera-de-ventana");
  });

  it("no-aplica: un plan que no es diferido", () => {
    for (const diferidoHastaMs of [undefined, null, Number.NaN, "x"]) {
      expect(situacionDeLaPrueba({
        ...autorizadaDespues(5 * 24),
        diferidoHastaMs,
      })).toBe("no-aplica");
    }
  });

  it("no-aplica: una suscripcion que ya tuvo un cobro exitoso", () => {
    expect(situacionDeLaPrueba({
      ...autorizadaDespues(5 * 24),
      summarized: { charged_quantity: 1, charged_amount: 22000 },
    })).toBe("no-aplica");
  });

  it("no-aplica: MP no dice authorized", () => {
    for (const mpStatus of ["pending", "paused", "cancelled", undefined]) {
      expect(situacionDeLaPrueba({ ...EN_PRUEBA, mpStatus })).toBe("no-aplica");
    }
  });

  it("un cobro en $0 sigue siendo una prueba", () => {
    expect(situacionDeLaPrueba({
      ...EN_PRUEBA,
      summarized: { charged_quantity: 1, charged_amount: 0 },
    })).toBe("en-prueba");
  });

  it("es coherente con el estado que se escribe", () => {
    // La situacion y el estado salen de la misma regla: si divergieran, el log
    // diria una cosa y el PF tendria otra.
    const casos: [PruebaDiferidaInput, string][] = [
      [EN_PRUEBA, "active"],
      [{ ...EN_PRUEBA, nowMs: FIN + 10 * DIA_MS, statusHoy: "grace" }, "grace"],
      [{ ...EN_PRUEBA, nowMs: FIN + 10 * DIA_MS, statusHoy: "active" }, "active"],
      [autorizadaDespues(5 * 24), "pending"],
      [{ ...EN_PRUEBA, mpStatus: "cancelled", statusHoy: "cancelled" }, "cancelled"],
    ];

    for (const [entrada, estado] of casos) {
      expect(aplicarPruebaDiferidaAlEstado(entrada)).toBe(estado);
    }
  });
});

// ---------------------------------------------------------------------------
// Un cobro de $0 no apaga las reglas de la prueba.
//
// "Sin cobro exitoso" es `charged_quantity` ausente o 0, O un monto cobrado en
// $0 o menos. Si la autorizacion de la prueba contara como un pago, las reglas se
// apagarian antes de que MP haya cobrado un peso.
// ---------------------------------------------------------------------------

describe("las reglas de la prueba con un cobro de $0", () => {
  /** El resumen de una prueba recien autorizada que MP reportara como un cobro de $0. */
  const AUTORIZACION_EN_CERO = {
    charged_quantity: 1,
    charged_amount: 0,
    pending_charge_quantity: 1,
  };

  it("a tiempo y con un 'cobro pendiente' sigue siendo active, no grace", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...EN_PRUEBA,
      statusHoy: "grace",
      summarized: AUTORIZACION_EN_CERO,
    });

    expect(r).toBe("active");
  });

  it("un link viejo pagado tarde sigue siendo pending", () => {
    const r = aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      statusHoy: "active",
      summarized: AUTORIZACION_EN_CERO,
    });

    expect(r).toBe("pending");
  });

  it("una prueba cancelada se acota igual a E", () => {
    const r = aplicarPruebaDiferidaAlPeriodo({
      ...EN_PRUEBA,
      mpStatus: "cancelled",
      statusHoy: "cancelled",
      summarized: AUTORIZACION_EN_CERO,
      periodEndMs: AHORA + 30 * DIA_MS,
    });

    expect(r).toBe(FIN);
  });

  for (const [caso, montos] of MONTOS_SIN_PAGO) {
    it(`con ${caso} las reglas siguen aplicando`, () => {
      const summarized = { charged_quantity: 1, ...montos };

      expect(aplicarPruebaDiferidaAlEstado({
        ...autorizadaDespues(5 * 24),
        summarized,
      })).toBe("pending");
      expect(aplicarPruebaDiferidaAlPeriodo({
        ...EN_PRUEBA,
        mpStatus: "cancelled",
        summarized,
        periodEndMs: AHORA + 30 * DIA_MS,
      })).toBe(FIN);
    });
  }

  it("con un monto POSITIVO el cobro es real y las reglas se apagan", () => {
    const summarized = { charged_quantity: 1, charged_amount: 22000 };

    expect(aplicarPruebaDiferidaAlEstado({
      ...autorizadaDespues(5 * 24),
      statusHoy: "grace",
      summarized,
    })).toBe("grace");
    expect(aplicarPruebaDiferidaAlPeriodo({
      ...EN_PRUEBA,
      mpStatus: "cancelled",
      summarized,
      periodEndMs: AHORA + 30 * DIA_MS,
    })).toBe(AHORA + 30 * DIA_MS);
  });

  for (const [caso, montos] of MONTOS_QUE_CUENTAN) {
    it(`con ${caso} (cantidad 1) el cobro cuenta y las reglas se apagan`, () => {
      expect(aplicarPruebaDiferidaAlEstado({
        ...autorizadaDespues(5 * 24),
        statusHoy: "grace",
        summarized: { charged_quantity: 1, ...montos },
      })).toBe("grace");
    });
  }
});

// ---------------------------------------------------------------------------
// cobroAntesDeLaPrueba: la medicion del supuesto central del diferimiento.
//
// Si MP ignorara o acortara la prueba, la suscripcion del plan nuevo cobraria al
// autorizar, cuando al PF todavia le quedan dias pagos por el plan anterior: pago
// dos veces ese periodo. El reconciliador lo avisa con un warn. Con el interruptor
// encendido, el primer PF real que vuelva a suscribirse con dias pagos es la
// medicion.
// ---------------------------------------------------------------------------

describe("cobroAntesDeLaPrueba", () => {
  const COBRADA = {
    charged_quantity: 1,
    charged_amount: 22000,
    last_charged_amount: 22000,
  };
  const entrada = (
    nowMs: number,
    over: Partial<Pick<PruebaDiferidaInput, "diferidoHastaMs" | "summarized">> = {},
  ) => ({ diferidoHastaMs: FIN, summarized: COBRADA, nowMs, ...over });

  it("un cobro exitoso cuando faltan 13 dias para E: MP ignoro la prueba", () => {
    expect(cobroAntesDeLaPrueba(entrada(AHORA))).toBe(true);
  });

  it("el borde: a exactamente el adelanto maximo de E todavia no avisa", () => {
    // Con dias de calendario argentino el primer cobro cae el mismo dia que E, a la
    // hora en que se autorizo: lo mas temprano que el modelo permite es casi un dia
    // antes de la hora exacta de E (hoy a las 00:01 ART y E a las 23:59 de ese dia),
    // y a ese margen exacto todavia no se avisa.
    expect(cobroAntesDeLaPrueba(entrada(FIN - ADELANTO_MAXIMO_DEL_COBRO_MS)))
      .toBe(false);
  });

  it("un milisegundo antes de ese margen SI avisa", () => {
    expect(cobroAntesDeLaPrueba(entrada(FIN - ADELANTO_MAXIMO_DEL_COBRO_MS - 1)))
      .toBe(true);
  });

  it("en E y despues no avisa: es el primer cobro que se esperaba", () => {
    for (const nowMs of [FIN, FIN + DIA_MS, FIN + 30 * DIA_MS]) {
      expect(cobroAntesDeLaPrueba(entrada(nowMs))).toBe(false);
    }
  });

  it("sin ningun cobro exitoso no avisa", () => {
    for (const summarized of [
      undefined,
      null,
      {},
      { charged_quantity: 0 },
      { charged_quantity: Number.NaN },
      { pending_charge_quantity: 1 },
    ]) {
      expect(cobroAntesDeLaPrueba(entrada(AHORA, { summarized }))).toBe(false);
    }
  });

  it("una autorizacion de $0 no es un cobro: no avisa", () => {
    expect(cobroAntesDeLaPrueba(entrada(AHORA, {
      summarized: { charged_quantity: 1, charged_amount: 0 },
    }))).toBe(false);
  });

  it("un plan que no es diferido nunca avisa, cobre cuando cobre", () => {
    for (const diferidoHastaMs of [undefined, null, Number.NaN, "x", {}]) {
      expect(cobroAntesDeLaPrueba(entrada(AHORA, { diferidoHastaMs }))).toBe(false);
    }
  });
});
