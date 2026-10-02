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
  DecidirDiferimientoDeAlumnoInput,
  DecidirDiferimientoInput,
  HOLGURA_PRUEBA_MS,
  MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS,
  MAX_PLANES_A_REVISAR,
  MAX_PLANES_DEL_ALUMNO_A_REVISAR,
  MIN_DIFERIMIENTO_MS,
  PlanDeLaCuenta,
  PruebaDiferidaInput,
  VENTANA_AUTORIZACION_MS,
  aplicarPruebaDiferidaAlEstado,
  aplicarPruebaDiferidaAlPeriodo,
  cobroAntesDeLaPrueba,
  consultarPlanesDelAlumno,
  cobrosExitosos,
  decidirCambioDePlanDelAlumno,
  decidirDiferimiento,
  decidirDiferimientoDeAlumno,
  diasDePrueba,
  finPagoDelPlan,
  evidenciaDePago,
  mpSigueCobrando,
  pagadoHastaDe,
  planesARevisar,
  planesDelAlumnoARevisar,
  situacionDeLaPrueba,
} from "../subscriptions/mp/diferir-primer-cobro";
import {
  MOTIVO_ABANDONO,
  MOTIVO_REEMPLAZO,
} from "../subscriptions/mp/motivos-terminal";
import { numeroDeDia } from "../subscriptions/mp/plazo-arrepentimiento";
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

    // Y es el peor caso por el lado temprano: el primer cobro (hoy + 30 dias de 24 h)
    // cae el 1/11 a las 00:01 ART, 23 h 58 min ANTES de la hora exacta de E. Entra
    // justo en lo que ADELANTO_MAXIMO_DEL_COBRO_MS dice que cubre.
    const cobro = Date.parse("2026-10-02T03:01:00.000Z") + 30 * DIA_MS;
    expect(artDateKey(cobro)).toBe(artDateKey(e));
    expect(e - cobro).toBe(DIA_MS - 2 * 60_000);
    expect(e - cobro).toBeLessThan(ADELANTO_MAXIMO_DEL_COBRO_MS);
  });

  it("E al principio del dia argentino y hoy al final: 31 dias de calendario", () => {
    // Hoy 1/10 a las 23:59 ART (02:59Z del 2/10); vence el 1/11 a las 00:01 ART
    // (03:01Z). Pasan 30 dias y 2 min; del 1/10 al 1/11 son 31 dias de calendario.
    const e = Date.parse("2026-11-01T03:01:00.000Z");

    expect(desde("2026-10-02T02:59:00.000Z", e)).toBe(31);

    // Y es el peor caso por el lado tardio: el primer cobro (hoy + 31 dias de 24 h)
    // cae el 1/11 a las 23:59 ART, 23 h 58 min DESPUES de la hora exacta de E, y
    // todavia deja lugar para que el pagador autorice hasta VENTANA_AUTORIZACION_MS
    // despues sin pasar de la holgura.
    const cobro = Date.parse("2026-10-02T02:59:00.000Z") + 31 * DIA_MS;
    expect(artDateKey(cobro)).toBe(artDateKey(e));
    expect(cobro - e).toBe(DIA_MS - 2 * 60_000);
    expect(cobro - e).toBeLessThan(HOLGURA_PRUEBA_MS - VENTANA_AUTORIZACION_MS);
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

  /**
   * Bajo el modelo (N corridas de 24 h desde la autorizacion, NO medido) el primer
   * cobro cae en `ahora + N * 24 h`. Tiene que caer el MISMO dia argentino que E,
   * comparado con `artDateKey` (la definicion con Intl que usan los mails, ajena a
   * la cuenta que se prueba), y adentro de los margenes que el resto del modulo da
   * por buenos: a menos de ADELANTO_MAXIMO_DEL_COBRO_MS antes de E y, aun con el
   * pagador autorizando lo mas tarde que se tolera (VENTANA_AUTORIZACION_MS), antes
   * de que venza la holgura (E + HOLGURA_PRUEBA_MS).
   */
  const cobroDentroDelModelo = (ahora: number, e: number) => {
    const n = diasDePrueba(e, ahora);
    const cobro = ahora + n * DIA_MS;

    expect(artDateKey(cobro)).toBe(artDateKey(e));
    expect(cobro).toBeGreaterThan(e - ADELANTO_MAXIMO_DEL_COBRO_MS);
    expect(cobro - e).toBeLessThan(HOLGURA_PRUEBA_MS - VENTANA_AUTORIZACION_MS);
  };

  it("barrido: para cualquier hora del dia, ahora + N * 24 h cae el MISMO dia argentino que E", () => {
    for (let min = 0; min < 3 * 24 * 60; min += 7) {
      cobroDentroDelModelo(Date.parse("2026-10-01T00:00:00.000Z") + min * 60_000, E_REAL);
    }
  });

  it("barrido: lo mismo variando la hora de E y la fecha", () => {
    // Mas de mil pares (hoy, E): E en tres fechas distintas (una es un 29/2) y a todas
    // las horas del dia, hoy tambien a todas las horas.
    for (const diaDeE of ["2026-11-01", "2027-03-15", "2028-02-29"]) {
      for (let minE = 0; minE < 24 * 60; minE += 97) {
        const e = Date.parse(`${diaDeE}T00:00:00.000Z`) + minE * 60_000;
        for (let minAhora = 0; minAhora < 24 * 60; minAhora += 53) {
          cobroDentroDelModelo(Date.parse("2026-10-02T00:00:00.000Z") + minAhora * 60_000, e);
        }
      }
    }
  });

  // ── Una sola definicion de "dia argentino" ──

  it("numeroDeDia (sin Intl, el del plazo de arrepentimiento) coincide con artDateKey (con Intl)", () => {
    // Son las dos definiciones de "dia argentino" que hay en el repo. Si divergieran,
    // la cuenta de los dias de prueba y lo que dicen los mails serian dias distintos.
    // Se compara el dia de `numeroDeDia` (su fecha en UTC, formato AAAA-MM-DD) con
    // `artDateKey`, en un barrido que cruza varias medianoches ART y un 29/2.
    const diaDe = (t: number) => new Date(numeroDeDia(t) * DIA_MS).toISOString().slice(0, 10);

    for (const inicio of ["2026-10-01T00:00:00.000Z", "2028-02-28T00:00:00.000Z"]) {
      for (let min = 0; min < 3 * 24 * 60; min += 7) {
        const t = Date.parse(inicio) + min * 60_000;

        expect(diaDe(t)).toBe(artDateKey(t));
      }
    }
    // Y el borde exacto, milisegundo a milisegundo.
    const medianoche = Date.parse("2026-10-02T03:00:00.000Z");
    expect(diaDe(medianoche - 1)).toBe("2026-10-01");
    expect(diaDe(medianoche)).toBe("2026-10-02");
    expect(artDateKey(medianoche - 1)).toBe("2026-10-01");
    expect(artDateKey(medianoche)).toBe("2026-10-02");
  });

  it("un valor que no es una fecha NUNCA da una prueba valida: el cliente de MP lo rechaza", () => {
    // Es aritmetica pura y no tira. NaN, infinito o un numero fuera de rango no son un
    // entero de 1 a MAX_FREE_TRIAL_DAYS, que es lo unico que `createPlan` acepta
    // (`client.ts`) antes de salir a la red.
    const valida = (n: number) =>
      Number.isInteger(n) && n >= 1 && n <= MAX_FREE_TRIAL_DAYS;
    const malos = [
      Number.NaN,
      Number.POSITIVE_INFINITY,
      Number.NEGATIVE_INFINITY,
      9e15,
      -9e15,
    ];

    for (const malo of malos) {
      expect(valida(diasDePrueba(malo, AHORA))).toBe(false);
      expect(valida(diasDePrueba(AHORA, malo))).toBe(false);
      expect(valida(diasDePrueba(malo, malo))).toBe(false);
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
// decidirDiferimientoDeAlumno: la misma decision para el alumno.
//
// Lo que cambia respecto del PF es de donde sale la elegibilidad, y es lo que
// mas se prueba aca: `athleteSubscription` no distingue al que se dio de baja del
// que paga (los dos se leen `active`), el plan dado de baja NO es `terminal`
// mientras le queden dias, y "esta dado de baja" se le pregunta a MP por TODOS los
// planes que pueden cobrar, tengan o no fecha. Diferirle a alguien con una
// suscripcion viva le suma un segundo cobro en E: ese caso no es "volver", es
// cambiar de plan, y lo decide `decidirCambioDePlanDelAlumno` (contando con que el
// reconciliador da de baja el viejo cuando el nuevo se confirma).
// ---------------------------------------------------------------------------

/** `users/{uid}` de un alumno, con el `status` que se pida (`active` por defecto). */
const alumno = (status: unknown = "active"): Record<string, unknown> => ({
  role: "athlete",
  athleteSubscription: { status },
});

/**
 * Un plan de alumno en el que el reconciliador ya vio una suscripcion: tiene
 * `currentPeriodEnd`. Por defecto el que pago y se dio de baja: SIN `terminal`,
 * que es como lo deja el reconciliador del alumno mientras le queden dias.
 */
function planDeAlumno(
  id: string,
  edadDias: number,
  data: Record<string, unknown> = {},
): PlanDeLaCuenta {
  return {
    id,
    data: {
      producto: "athlete",
      uid: "u1",
      cycle: "monthly",
      createdAt: ts(AHORA - edadDias * DIA_MS),
      currentPeriodEnd: ts(FIN),
      ...data,
    },
  };
}

/** Un plan de alumno sin fecha: un checkout sin pagar, o uno que el reconciliador vio sin fecha. */
const sinFecha = (
  id: string,
  edadDias: number,
  data: Record<string, unknown> = {},
): PlanDeLaCuenta => planDeAlumno(id, edadDias, { currentPeriodEnd: undefined, ...data });

/** Una suscripcion VIVA: autorizada, con su cobro hecho. */
const viva = (over: Partial<MpPreapproval> = {}): MpPreapproval =>
  pagada(ULTIMO_COBRO, { id: "s-viva", status: "authorized", ...over });

/** Una suscripcion dada de baja que nunca cobro (`charged_quantity: 0`). */
const sinCobro: MpPreapproval = {
  id: "s-sin-cobro",
  status: "cancelled",
  auto_recurring: { frequency: 1, frequency_type: "months" },
  summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
};

function armarAlumno(
  opts: {
    userData?: Record<string, unknown>;
    planes?: PlanDeLaCuenta[] | Error;
    subs?: Record<string, MpPreapproval[] | Error>;
    nowMs?: number;
  } = {},
) {
  const lecturas = { planes: 0, suscripciones: [] as string[] };
  const input: DecidirDiferimientoDeAlumnoInput = {
    uid: "u1",
    userData: "userData" in opts ? opts.userData : alumno(),
    nowMs: opts.nowMs ?? AHORA,
    // Explicito, como en el PF: los tests no dependen del valor de la constante.
    habilitado: true,
    leerPlanes: async () => {
      lecturas.planes += 1;
      if (opts.planes instanceof Error) throw opts.planes;
      return opts.planes ?? [planDeAlumno("a0", 20)];
    },
    leerSuscripciones: async (planId) => {
      lecturas.suscripciones.push(planId);
      const r = opts.subs?.[planId];
      if (r instanceof Error) throw r;
      // `pagada` viene `cancelled`: es el alumno que se dio de baja.
      return r ?? (planId === "a0" ? [pagada(ULTIMO_COBRO)] : []);
    },
  };
  return { input, lecturas };
}

describe("mpSigueCobrando", () => {
  it("solo `cancelled` y `pending` no cobran", () => {
    expect(mpSigueCobrando("cancelled")).toBe(false);
    expect(mpSigueCobrando("pending")).toBe(false);
  });

  it("autorizada, pausada, un estado nuevo y un estado ausente SI: ante la duda, no se arma un cobro doble", () => {
    for (const s of ["authorized", "paused", "un-estado-nuevo", undefined, null]) {
      expect(mpSigueCobrando(s)).toBe(true);
    }
  });
});

describe("consultarPlanesDelAlumno: la pasada unica por MP", () => {
  function pasada(
    planes: PlanDeLaCuenta[],
    subs: Record<string, MpPreapproval[] | Error> = {},
  ) {
    const lecturas: string[] = [];
    return {
      lecturas,
      correr: () => consultarPlanesDelAlumno({
        planes,
        leerSuscripciones: async (planId) => {
          lecturas.push(planId);
          const r = subs[planId];
          if (r instanceof Error) throw r;
          return r ?? [];
        },
      }),
    };
  }

  it("ninguna cobra: devuelve lo que MP contesto por cada plan, para no volver a preguntar", async () => {
    const { correr, lecturas } = pasada(
      [planDeAlumno("a0", 20), sinFecha("a1", 2)],
      { a0: [pagada(ULTIMO_COBRO)] },
    );

    const r = await correr();

    expect(r.vivo).toBe(false);
    if (r.vivo) return;
    expect([...r.suscripciones.keys()]).toEqual(["a0", "a1"]);
    expect(r.suscripciones.get("a0")).toHaveLength(1);
    expect(r.suscripciones.get("a1")).toEqual([]);
    expect(lecturas).toEqual(["a0", "a1"]);
  });

  it("con UNA viva sigue hasta el final: el cambio de plan necesita haber visto todos", async () => {
    const { correr, lecturas } = pasada(
      [planDeAlumno("a0", 20), planDeAlumno("a1", 5), planDeAlumno("a2", 1)],
      { a0: [pagada(ULTIMO_COBRO)], a1: [viva()] },
    );

    const r = await correr();

    expect(r).toMatchObject({ vivo: true, planId: "a1" });
    if (!r.vivo) return;
    expect(r.vivas.map((v) => v.planId)).toEqual(["a1"]);
    expect(r.vivas[0].plan).toMatchObject({ producto: "athlete" });
    // Lo que MP contesto por TODOS: la decision del cambio mira los dados de baja.
    expect([...r.suscripciones.keys()]).toEqual(["a0", "a1", "a2"]);
    expect(lecturas).toEqual(["a0", "a1", "a2"]);
  });

  it("corta en la SEGUNDA viva: con dos ya no hay nada que decidir", async () => {
    const { correr, lecturas } = pasada(
      [planDeAlumno("a0", 20), planDeAlumno("a1", 5), planDeAlumno("a2", 1), planDeAlumno("a3", 1)],
      { a0: [pagada(ULTIMO_COBRO)], a1: [viva()], a2: [viva()], a3: [viva()] },
    );

    const r = await correr();

    expect(r).toMatchObject({ vivo: true, planId: "a1" });
    if (!r.vivo) return;
    expect(r.vivas.map((v) => v.planId)).toEqual(["a1", "a2"]);
    expect(lecturas).toEqual(["a0", "a1", "a2"]);
  });

  it("dos vivas en el MISMO plan tambien son dos", async () => {
    const { correr, lecturas } = pasada(
      [planDeAlumno("a0", 5), planDeAlumno("a1", 1)],
      { a0: [viva(), viva({ id: "otra" })], a1: [viva()] },
    );

    const r = await correr();

    if (!r.vivo) throw new Error("tenia que haber vivas");
    expect(r.vivas).toHaveLength(2);
    expect(lecturas).toEqual(["a0"]);
  });

  it("una `pending` no cuenta como viva, pero un estado raro o pausado SI", async () => {
    const pend = pasada([planDeAlumno("a0", 5)], { a0: [viva({ status: "pending" })] });
    expect((await pend.correr()).vivo).toBe(false);

    for (const estado of ["paused", "un-estado-nuevo"]) {
      const p = pasada([planDeAlumno("a0", 5)], { a0: [viva({ status: estado })] });
      expect((await p.correr()).vivo).toBe(true);
    }
  });

  it("solo mira planes de alumno que pueden cobrar: no el de PF ni el terminal de hecho", async () => {
    const { correr, lecturas } = pasada([
      planDeAlumno("de-pf", 5, { producto: "trainer" }),
      planDeAlumno("sin-producto", 5, { producto: undefined }),
      planDeAlumno("baja-confirmada", 5, { terminal: true }),
      planDeAlumno("reemplazado", 5, { terminal: true, terminalReason: MOTIVO_REEMPLAZO }),
      planDeAlumno("a0", 5),
    ]);

    await correr();

    expect(lecturas).toEqual(["a0"]);
  });

  it("un checkout abandonado SE mira, con o sin fecha: el init_point no vence y se puede pagar tarde", async () => {
    const { correr, lecturas } = pasada([
      sinFecha("abandonado", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
    ], { abandonado: [viva()] });

    expect(await correr()).toMatchObject({ vivo: true, planId: "abandonado" });
    expect(lecturas).toEqual(["abandonado"]);
  });

  it("si MP falla en un plan, tira: sin saber si cobra no se puede descartar nada", async () => {
    const { correr } = pasada(
      [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      { a1: new Error("429") },
    );

    await expect(correr()).rejects.toThrow("429");
  });

  it("sin planes que puedan cobrar no pregunta nada", async () => {
    const { correr, lecturas } = pasada([]);

    expect(await correr()).toMatchObject({ vivo: false });
    expect(lecturas).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// decidirCambioDePlanDelAlumno: cambiar de ciclo con el viejo cobrando.
//
// El plan nuevo difiere su primer cobro hasta que vence lo que el viejo ya cobro,
// y el reconciliador da de baja el viejo cuando el nuevo se confirma. Lo caro de
// equivocarse: diferir de mas regala dias; diferir de menos (o cobrar en el acto)
// le hace pagar dos veces el solapamiento. Por eso lo que no se puede establecer
// termina en BLOQUEAR (lo de antes, #1305), nunca en cobrar en el acto.
// ---------------------------------------------------------------------------

describe("finPagoDelPlan: el fin pago de UN plan, la unica cuenta de las dos decisiones", () => {
  it("el menor entre la fecha del plan y lo que cubre su pago mas lejano", () => {
    const corto = pagada("2026-08-01T12:00:00.000Z", { id: "a" });
    const largo = pagada(ULTIMO_COBRO, { id: "b" });

    expect(finPagoDelPlan(FIN + 10 * DIA_MS, [corto, largo])).toMatchObject({
      finMs: FIN,
      pago: { hastaMs: FIN },
    });
    // La fecha del plan acota por el otro lado.
    expect(finPagoDelPlan(FIN - DIA_MS, [largo])?.finMs).toBe(FIN - DIA_MS);
  });

  it("sin un cobro real en ninguna suscripcion, null", () => {
    expect(finPagoDelPlan(FIN, [])).toBeNull();
    expect(finPagoDelPlan(FIN, [sinCobro])).toBeNull();
  });
});

describe("decidirCambioDePlanDelAlumno", () => {
  /** El proximo cobro del mensual vivo: dentro de 20 dias. */
  const PROXIMO = AHORA + 20 * DIA_MS;
  /** El cobro que cubre hasta PROXIMO: un mes antes. */
  const COBRO_DEL_PROXIMO = "2026-08-27T12:00:00.000Z";

  /** El mensual autorizado y al dia, con 20 dias pagos por delante. */
  const mensualVivo = (over: Partial<MpPreapproval> = {}): MpPreapproval =>
    pagada(COBRO_DEL_PROXIMO, {
      id: "s-mensual",
      status: "authorized",
      next_payment_date: new Date(PROXIMO).toISOString(),
      ...over,
    });

  function decidir(
    opts: {
      cycle?: "monthly" | "annual";
      sub?: MpPreapproval;
      plan?: Record<string, unknown>;
      otrasVivas?: number;
      planes?: PlanDeLaCuenta[];
      subs?: Record<string, MpPreapproval[]>;
      habilitado?: boolean;
      nowMs?: number;
    } = {},
  ) {
    const plan = planDeAlumno("viejo", 30, { currentPeriodEnd: ts(PROXIMO), ...opts.plan });
    const vivas = [{ planId: "viejo", plan: plan.data, sub: opts.sub ?? mensualVivo() }];
    for (let n = 0; n < (opts.otrasVivas ?? 0); n++) {
      vivas.push({ planId: `otra${n}`, plan: plan.data, sub: mensualVivo() });
    }
    const planes = [plan, ...(opts.planes ?? [])];
    return decidirCambioDePlanDelAlumno({
      uid: "u1",
      cycle: opts.cycle ?? "annual",
      vivas,
      planes,
      suscripciones: new Map(Object.entries({
        viejo: [vivas[0].sub],
        ...(opts.subs ?? {}),
      })),
      nowMs: opts.nowMs ?? AHORA,
      habilitado: opts.habilitado ?? true,
    });
  }

  it("mensual al dia con 20 dias pagos → el anual difiere hasta su proximo cobro", () => {
    const r = decidir();

    expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: PROXIMO });
    if (r.tipo !== "diferir") return;
    expect(diasDePrueba(r.diferidoHastaMs, AHORA)).toBe(20);
  });

  it("anual → mensual con 11 meses por delante: la prueba entra en lo que MP acepta", () => {
    const proximo = Date.parse("2027-08-07T12:00:00.000Z");
    const r = decidir({
      cycle: "monthly",
      plan: { cycle: "annual", currentPeriodEnd: ts(proximo) },
      sub: pagada("2026-08-07T12:00:00.000Z", {
        id: "s-anual",
        status: "authorized",
        next_payment_date: new Date(proximo).toISOString(),
        auto_recurring: { frequency: 12, frequency_type: "months", transaction_amount: 35000 },
        summarized: {
          charged_quantity: 1,
          charged_amount: 35000,
          last_charged_date: "2026-08-07T12:00:00.000Z",
          last_charged_amount: 35000,
          pending_charge_quantity: 0,
        },
      }),
    });

    expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: proximo });
    if (r.tipo !== "diferir") return;
    const dias = diasDePrueba(r.diferidoHastaMs, AHORA);
    expect(dias).toBe(334);
    expect(dias).toBeLessThanOrEqual(MAX_FREE_TRIAL_DAYS);
  });

  it("una prueba que no entra en lo que MP acepta se BLOQUEA, no se recorta", () => {
    // Recortarla seria cobrar antes de que venza lo pago.
    const lejos = AHORA + 500 * DIA_MS;
    const r = decidir({
      plan: { currentPeriodEnd: ts(lejos) },
      sub: mensualVivo({
        next_payment_date: new Date(lejos).toISOString(),
        auto_recurring: { frequency: 24, frequency_type: "months" },
      }),
    });

    expect(r).toMatchObject({ tipo: "bloquear", motivo: "prueba-demasiado-larga" });
  });

  it("el MISMO ciclo es comprar dos veces lo mismo, con el interruptor prendido o apagado", () => {
    expect(decidir({ cycle: "monthly" })).toEqual({ tipo: "mismo-ciclo", planViejo: "viejo" });
    expect(decidir({ cycle: "monthly", habilitado: false }))
      .toEqual({ tipo: "mismo-ciclo", planViejo: "viejo" });
  });

  it("dos suscripciones vivas ya son un cobro doble: se bloquea", () => {
    expect(decidir({ otrasVivas: 1 })).toMatchObject({ tipo: "bloquear", motivo: "varias-vivas" });
  });

  it("un ciclo que no se entiende no se compara: se bloquea", () => {
    expect(decidir({ plan: { cycle: "semestral" } }))
      .toMatchObject({ tipo: "bloquear", motivo: "ciclo-desconocido" });
  });

  it("con el interruptor apagado se bloquea como antes: sin prueba solo queda cobrar en el acto", () => {
    expect(decidir({ habilitado: false }))
      .toMatchObject({ tipo: "bloquear", motivo: "deshabilitado" });
  });

  it("⚠️ sin un cobro real que lo respalde (no se sabe hasta cuando pago) se BLOQUEA", () => {
    for (const sub of [
      { id: "s", status: "authorized" } as MpPreapproval,
      mensualVivo({ summarized: { charged_quantity: 0, pending_charge_quantity: 0 } }),
      // Un cobro de $0 (la autorizacion de una prueba) no es un pago.
      mensualVivo({ summarized: { charged_quantity: 1, charged_amount: 0, pending_charge_quantity: 0 } }),
    ]) {
      expect(decidir({ sub })).toMatchObject({ tipo: "bloquear", motivo: "sin-pago-comprobado" });
    }
  });

  it("un plan viejo en su PROPIA prueba, sin cobrar todavia, se bloquea", () => {
    const r = decidir({
      plan: { diferidoHastaMs: PROXIMO },
      sub: mensualVivo({
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          free_trial: { frequency: 20, frequency_type: "days" },
        },
        summarized: { charged_quantity: 0, pending_charge_quantity: 1 },
      }),
    });

    // `pending_charge_quantity` del cobro programado: para el mapeo seria `grace`.
    expect(r).toMatchObject({ tipo: "bloquear" });
  });

  it("sin la fecha del proximo cobro (ni de MP ni guardada) se bloquea", () => {
    const r = decidir({
      plan: { currentPeriodEnd: undefined },
      sub: mensualVivo({ next_payment_date: undefined }),
    });

    expect(r).toMatchObject({ tipo: "bloquear", motivo: "sin-fecha-de-fin" });
  });

  it("si MP no manda el proximo cobro, vale el que guardo el reconciliador", () => {
    const guardado = AHORA + 15 * DIA_MS;
    const r = decidir({
      plan: { currentPeriodEnd: ts(guardado) },
      sub: mensualVivo({ next_payment_date: undefined }),
    });

    expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: guardado });
  });

  it("de las dos fuentes vale la MENOR: ninguna puede regalar dias", () => {
    // Un reintento cobrado tarde corre `last_charged_date`: el cobro dice 27/9+1 mes
    // pero MP sigue con el proximo cobro el 27/9.
    const tarde = decidir({ sub: mensualVivo({
      summarized: {
        charged_quantity: 2,
        last_charged_date: "2026-09-01T12:00:00.000Z",
        pending_charge_quantity: 0,
      },
    }) });
    expect(tarde).toMatchObject({ diferidoHastaMs: PROXIMO });

    // Y una fecha de proximo cobro que se pasa de lo que el ultimo cobro cubre.
    const corrida = decidir({ sub: mensualVivo({
      next_payment_date: new Date(PROXIMO + 10 * DIA_MS).toISOString(),
    }) });
    expect(corrida).toMatchObject({ diferidoHastaMs: PROXIMO });
  });

  it("un cobro pendiente (rebotado, MP reintenta) es un periodo que no se pago: se bloquea", () => {
    const r = decidir({
      sub: mensualVivo({
        summarized: {
          charged_quantity: 1,
          last_charged_date: COBRO_DEL_PROXIMO,
          pending_charge_quantity: 1,
        },
      }),
    });

    expect(r).toMatchObject({ tipo: "bloquear", motivo: "cobro-rebotado" });
  });

  it("un estado que no conocemos no se interpreta: se bloquea", () => {
    expect(decidir({ sub: mensualVivo({ status: "algo-nuevo" }) }))
      .toMatchObject({ tipo: "bloquear", motivo: "estado-que-no-se-difiere" });
  });

  it("un plan arrepentido con una suscripcion viva es una baja que no termino: se bloquea", () => {
    expect(decidir({ plan: { arrepentidoAtMs: AHORA - DIA_MS } }))
      .toMatchObject({ tipo: "bloquear", motivo: "arrepentido" });
  });

  it("autorizado con menos de un dia: el viejo cobra enseguida y seria una carrera, se bloquea", () => {
    const pronto = AHORA + 6 * 60 * 60 * 1000;
    const r = decidir({
      plan: { currentPeriodEnd: ts(pronto) },
      sub: mensualVivo({ next_payment_date: new Date(pronto).toISOString() }),
    });

    expect(r).toMatchObject({ tipo: "bloquear", motivo: "pago-vence-pronto" });
  });

  describe("pausado: cuenta como vivo (MP lo puede reanudar)", () => {
    it("con dias pagos por delante, difiere igual que el autorizado", () => {
      const r = decidir({ sub: mensualVivo({ status: "paused" }) });

      expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: PROXIMO });
    });

    it("sin nada pago por ninguna de las dos fuentes, el nuevo cobra al autorizar", () => {
      const vencido = AHORA - 40 * DIA_MS;
      const r = decidir({
        plan: { currentPeriodEnd: ts(vencido) },
        sub: pagada("2026-06-28T12:00:00.000Z", {
          id: "s-pausada",
          status: "paused",
          next_payment_date: new Date(vencido).toISOString(),
        }),
      });

      expect(r).toEqual({ tipo: "sin-diferir", planViejo: "viejo" });
    });

    it("si las fuentes no coinciden (una con dias y otra sin), se bloquea", () => {
      const r = decidir({
        plan: { currentPeriodEnd: ts(AHORA - 5 * DIA_MS) },
        sub: mensualVivo({ status: "paused", next_payment_date: undefined }),
      });

      expect(r).toMatchObject({ tipo: "bloquear", motivo: "pago-vence-pronto" });
    });

    it("un cobro pendiente no lo frena: pausado, MP no reintenta nada", () => {
      const r = decidir({ sub: mensualVivo({
        status: "paused",
        summarized: {
          charged_quantity: 1,
          last_charged_date: COBRO_DEL_PROXIMO,
          pending_charge_quantity: 1,
        },
      }) });

      expect(r).toMatchObject({ tipo: "diferir" });
    });
  });

  describe("los dias de los planes DADOS DE BAJA tambien se respetan", () => {
    /** Un plan dado de baja, pago hasta el 16/10 (39 dias): su cobro del 16/9. */
    const LEJOS = Date.parse("2026-10-16T12:00:00.000Z");
    const dadoDeBaja = planDeAlumno("baja", 60, { currentPeriodEnd: ts(LEJOS) });
    const suBaja = pagada("2026-09-16T12:00:00.000Z");

    it("si uno da mas dias que el vivo, se difiere hasta ese: cada uno lo respalda su cobro", () => {
      const r = decidir({ planes: [dadoDeBaja], subs: { baja: [suBaja] } });

      expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: LEJOS });
    });

    it("su fecha no pasa de lo que cubre su cobro", () => {
      const r = decidir({
        planes: [planDeAlumno("baja", 60, { currentPeriodEnd: ts(AHORA + 90 * DIA_MS) })],
        subs: { baja: [suBaja] },
      });

      expect(r).toMatchObject({ diferidoHastaMs: LEJOS });
    });

    it("sin cobro, con MP vacio o con algo que no es `cancelled`, no aporta", () => {
      for (const subs of [[sinCobro], [], [{ ...suBaja, status: "pending" }]]) {
        const r = decidir({ planes: [dadoDeBaja], subs: { baja: subs } });
        expect(r).toMatchObject({ diferidoHastaMs: PROXIMO });
      }
    });

    it("entre varios dados de baja gana el que MAS LEJOS paga, no el mas nuevo (como al volver)", () => {
      // El mismo criterio de `decidirDiferimientoDeAlumno`: un anual viejo pago hasta
      // mas adelante que un mensual nuevo. Una sola nocion de "fin pago".
      const anualViejo = planDeAlumno("anual-viejo", 300, {
        cycle: "annual",
        currentPeriodEnd: ts(Date.parse("2027-01-16T12:00:00.000Z")),
      });
      const suAnual = pagada("2026-01-16T12:00:00.000Z", {
        auto_recurring: { frequency: 12, frequency_type: "months" },
      });
      const mensualNuevo = planDeAlumno("mensual-nuevo", 40, { currentPeriodEnd: ts(LEJOS) });

      for (const planes of [[anualViejo, mensualNuevo], [mensualNuevo, anualViejo]]) {
        const r = decidir({
          planes,
          subs: { "anual-viejo": [suAnual], "mensual-nuevo": [suBaja] },
        });
        expect(r).toMatchObject({ diferidoHastaMs: Date.parse("2027-01-16T12:00:00.000Z") });
      }
    });

    it("un pausado sin dias se difiere igual si un dado de baja los tiene", () => {
      const vencido = AHORA - 40 * DIA_MS;
      const r = decidir({
        plan: { currentPeriodEnd: ts(vencido) },
        sub: pagada("2026-06-28T12:00:00.000Z", {
          id: "s-pausada",
          status: "paused",
          next_payment_date: new Date(vencido).toISOString(),
        }),
        planes: [dadoDeBaja],
        subs: { baja: [suBaja] },
      });

      expect(r).toEqual({ tipo: "diferir", planViejo: "viejo", diferidoHastaMs: LEJOS });
    });
  });
});

describe("decidirDiferimientoDeAlumno: cuando SI se difiere", () => {
  it("dado de baja con dias por delante y un cobro real en MP", async () => {
    // El plan que pago NO es `terminal` (asi lo deja el reconciliador del alumno
    // mientras le queden dias): con el filtro del PF no contaria.
    const { input } = armarAlumno();

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("gana la fecha MENOR: si MP respalda menos que el fin del plan, manda MP", async () => {
    const { input } = armarAlumno({
      subs: { a0: [pagada("2026-08-12T12:00:00.000Z")] },
    });

    expect(await decidirDiferimientoDeAlumno(input)).toEqual({
      diferir: true,
      diferidoHastaMs: Date.parse("2026-09-12T12:00:00.000Z"),
    });
  });

  it("gana la fecha MENOR: si el fin del plan es antes que lo que cubre el cobro, manda el plan", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20, { currentPeriodEnd: ts(AHORA + 4 * DIA_MS) })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: AHORA + 4 * DIA_MS });
  });

  it("el fin que acota es el del plan QUE PAGO, no el de otro plan del alumno", async () => {
    // a0 pago hasta el 25/9 pero su acceso termina en FIN (20/9); a1, mas nuevo,
    // se dio de baja sin cobrar nada y tiene un fin mas lejano. Acotar con el fin
    // de a1 dejaria la prueba en el 25/9: cinco dias que nadie pago con a0.
    const { input } = armarAlumno({
      planes: [
        planDeAlumno("a0", 20),
        planDeAlumno("a1", 5, { currentPeriodEnd: ts(FIN + 10 * DIA_MS) }),
      ],
      subs: {
        a0: [pagada("2026-08-25T12:00:00.000Z")],
        a1: [sinCobro],
      },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  describe("con varios planes que prueban un pago: gana el que mas lejos llega, no el mas nuevo", () => {
    /** Un anual dado de baja, pago el 15/1/2026: llega hasta el 15/1/2027. */
    const FIN_ANUAL = Date.parse("2027-01-15T12:00:00.000Z");
    const anual = (id: string, edadDias: number) => planDeAlumno(id, edadDias, {
      cycle: "annual",
      currentPeriodEnd: ts(FIN_ANUAL),
    });
    const COBRO_ANUAL = pagada("2026-01-15T12:00:00.000Z", {
      id: "s-anual",
      auto_recurring: {
        frequency: 12,
        frequency_type: "months",
        transaction_amount: 220000,
      },
    });
    /** El mensual posterior, pago hasta FIN (20/9/2026). */
    const mensual = (id: string, edadDias: number) => planDeAlumno(id, edadDias);
    const COBRO_MENSUAL = pagada(ULTIMO_COBRO, { id: "s-mensual" });

    it("un anual viejo hasta enero y un mensual nuevo hasta septiembre: difiere hasta enero", async () => {
      // Quedarse con el plan mas nuevo difiere hasta septiembre y le cobra de
      // septiembre a enero lo que ya pago con el anual.
      const { input } = armarAlumno({
        planes: [anual("anual", 240), mensual("mensual", 18)],
        subs: { anual: [COBRO_ANUAL], mensual: [COBRO_MENSUAL] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: true, diferidoHastaMs: FIN_ANUAL });
    });

    it("el mismo resultado con los planes en el orden contrario en el store", async () => {
      const { input } = armarAlumno({
        planes: [mensual("mensual", 18), anual("anual", 240)],
        subs: { anual: [COBRO_ANUAL], mensual: [COBRO_MENSUAL] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: true, diferidoHastaMs: FIN_ANUAL });
    });

    it("si el plan mas NUEVO es el que llega mas lejos, gana el nuevo", async () => {
      const { input } = armarAlumno({
        planes: [mensual("mensual", 240), anual("anual", 18)],
        subs: { anual: [COBRO_ANUAL], mensual: [COBRO_MENSUAL] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: true, diferidoHastaMs: FIN_ANUAL });
    });

    it("cada plan se acota con SU fin: el cobro de uno no estira el fin del otro", async () => {
      // El anual cobro hasta enero pero su acceso termina antes (FIN + 3 dias); el
      // mensual llega hasta FIN. Gana el anual, con SU fin, no con el del cobro.
      const finAnual = FIN + 3 * DIA_MS;
      const { input } = armarAlumno({
        planes: [
          planDeAlumno("anual", 240, { cycle: "annual", currentPeriodEnd: ts(finAnual) }),
          mensual("mensual", 18),
        ],
        subs: { anual: [COBRO_ANUAL], mensual: [COBRO_MENSUAL] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: true, diferidoHastaMs: finAnual });
    });

    it("un empate se resuelve por id, no por el orden de lectura", async () => {
      const dos = [
        planDeAlumno("b", 30, { currentPeriodEnd: ts(FIN) }),
        planDeAlumno("a", 10, { currentPeriodEnd: ts(FIN) }),
      ];
      for (const planes of [dos, [...dos].reverse()]) {
        const { input } = armarAlumno({
          planes,
          subs: {
            a: [pagada(ULTIMO_COBRO, { id: "sa" })],
            b: [pagada(ULTIMO_COBRO, { id: "sb" })],
          },
        });
        expect(await decidirDiferimientoDeAlumno(input))
          .toEqual({ diferir: true, diferidoHastaMs: FIN });
      }
      // Y el plan que nombra el log es el mismo en los dos ordenes.
      const nombrados = (logger.info as jest.Mock).mock.calls
        .filter(([m]) => m === "mp/diferir-primer-cobro: se difiere el primer cobro")
        .slice(-2)
        .map(([, datos]) => datos.planConPago);
      expect(nombrados).toEqual(["a", "a"]);
    });

    it("el log nombra al plan elegido, no al mas nuevo", async () => {
      const { input } = armarAlumno({
        planes: [anual("anual", 240), mensual("mensual", 18)],
        subs: { anual: [COBRO_ANUAL], mensual: [COBRO_MENSUAL] },
      });

      await decidirDiferimientoDeAlumno(input);

      expect(logger.info).toHaveBeenLastCalledWith(
        "mp/diferir-primer-cobro: se difiere el primer cobro",
        expect.objectContaining({ planConPago: "anual", fuenteDelPago: "ultimo-cobro" }),
      );
    });

    it("un plan SIN fecha con un cobro no cuenta como evidencia: se elige el valido", async () => {
      // Sin `currentPeriodEnd` no hay contra que acotar lo que cubre ese cobro, asi
      // que no es candidato por mas que MP lo muestre (semantica de siempre). El que
      // si tiene fecha y cobro se elige, aunque sea el mas viejo.
      const { input } = armarAlumno({
        planes: [
          sinFecha("sin-fecha", 5, { cycle: "annual" }),
          mensual("mensual", 40),
        ],
        subs: {
          "sin-fecha": [{ ...COBRO_ANUAL, id: "s-sf" }],
          mensual: [COBRO_MENSUAL],
        },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: true, diferidoHastaMs: FIN });
    });

    it("la viva en CUALQUIERA de los planes sigue frenando, aunque el mas largo este dado de baja", async () => {
      const { input } = armarAlumno({
        planes: [anual("anual", 240), mensual("mensual", 18)],
        subs: { anual: [COBRO_ANUAL], mensual: [{ ...COBRO_MENSUAL, status: "authorized" }] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
    });

    it("un plan con fecha cuya lista de MP viene vacia sigue sin diferir, aunque el otro pruebe un pago", async () => {
      const { input } = armarAlumno({
        planes: [anual("anual", 240), mensual("mensual", 18)],
        subs: { anual: [], mensual: [COBRO_MENSUAL] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo: "sin-respuesta-de-mp" });
    });
  });

  it("pero NO de un plan que no puede probar un pago, aunque sea el mas nuevo y muestre un cobro", async () => {
    // a1 se arrepintio (se le devolvio todo) y MP sigue mostrando su cobro, que
    // cubriria hasta el 27/9. El pago que vale es el de a0, hasta FIN.
    const { input } = armarAlumno({
      planes: [
        planDeAlumno("a0", 40),
        planDeAlumno("a1", 10, {
          currentPeriodEnd: ts(FIN + 7 * DIA_MS),
          arrepentidoAtMs: AHORA - DIA_MS,
        }),
      ],
      subs: {
        a0: [pagada(ULTIMO_COBRO)],
        a1: [pagada("2026-08-27T12:00:00.000Z", { id: "s-a1" })],
      },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("dentro del plan que pago, gana el pago MAS LEJANO", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 50, { currentPeriodEnd: ts(FIN + 40 * DIA_MS) })],
      subs: {
        a0: [
          pagada("2026-08-10T12:00:00.000Z", { id: "s-vieja" }),
          pagada("2026-08-25T12:00:00.000Z", { id: "s-nueva" }),
        ],
      },
    });

    expect(await decidirDiferimientoDeAlumno(input)).toEqual({
      diferir: true,
      diferidoHastaMs: Date.parse("2026-09-25T12:00:00.000Z"),
    });
  });

  it("el borde: exactamente un dia por delante SI se difiere", async () => {
    const fin = AHORA + MIN_DIFERIMIENTO_MS;
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20, { currentPeriodEnd: ts(fin) })],
      subs: { a0: [pagada("2026-08-08T12:00:00.000Z")] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: fin });
  });

  it("loguea la decision con el uid, el producto y la fecha, sin datos personales", async () => {
    const { input } = armarAlumno();

    await decidirDiferimientoDeAlumno(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se difiere el primer cobro",
      expect.objectContaining({
        uid: "u1",
        producto: "athlete",
        planConPago: "a0",
        fuenteDelPago: "ultimo-cobro",
        // Del 7/9 (AHORA, 09:00 ART) al 20/9 (FIN, 09:00 ART): 7 + 13 = 20.
        diasDePrueba: 13,
        diferidoHastaIso: "2026-09-20T12:00:00.000Z",
      }),
    );
    expect(logger.warn).not.toHaveBeenCalled();
  });
});

describe("decidirDiferimientoDeAlumno: el documento corta primero, sin leer nada", () => {
  // `athleteSubscription` es `{status}` con `active`, `grace` o `expired`. Solo
  // `active` puede ser alguien dado de baja con dias pagos.
  const cortes: [string, Record<string, unknown> | undefined, string][] = [
    ["un alumno que nunca pago", { role: "athlete" }, "sin-suscripcion"],
    ["un usuario sin documento", undefined, "sin-suscripcion"],
    ["un acceso vencido", alumno("expired"), "sin-acceso-vigente"],
    ["una suscripcion en gracia (viva, MP reintenta)", alumno("grace"), "no-esta-cancelada"],
    // `cancelled` NO existe en el vocabulario del alumno: no es "dado de baja".
    ["`cancelled`, que no es un estado del alumno", alumno("cancelled"), "estado-degradado"],
    ["un status que no es un string", alumno(1), "estado-degradado"],
    ["el mapa como string", { role: "athlete", athleteSubscription: "active" }, "estado-degradado"],
  ];

  for (const [caso, userData, motivo] of cortes) {
    it(`${caso}: ${motivo}, sin leer planes ni MP`, async () => {
      const { input, lecturas } = armarAlumno({ userData });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo });
      expect(lecturas.planes).toBe(0);
      expect(lecturas.suscripciones).toEqual([]);
    });
  }

  it("el motivo va al log con el producto", async () => {
    const { input } = armarAlumno({ userData: alumno("expired") });

    await decidirDiferimientoDeAlumno(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se cobra en el acto",
      { uid: "u1", producto: "athlete", motivo: "sin-acceso-vigente" },
    );
  });
});

describe("decidirDiferimientoDeAlumno: NINGUNA suscripcion viva", () => {
  // Es la mitad de "esta dado de baja" que el documento no dice. Una viva es
  // alguien que ya paga: diferirle un plan nuevo le suma un segundo cobro en E, y
  // para el alumno no hay baja de reemplazados que lo corrija.

  it("con una suscripcion viva en otro plan NO difiere, aunque el que pago muestre el cobro", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      subs: { a1: [viva()] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("la misma cuenta con esa suscripcion dada de baja SI difiere (el control del test anterior)", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      subs: { a1: [viva({ status: "cancelled" })] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("si la viva es la del plan que pago (no se dio de baja), tampoco", async () => {
    // Un alumno que paga y aprieta de nuevo: `active` en el documento, igual que
    // uno dado de baja. Solo MP los distingue.
    const { input } = armarAlumno({ subs: { a0: [viva()] } });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("la viva puede ser la SEGUNDA suscripcion del plan: se miran todas", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      subs: { a1: [viva({ id: "s-baja", status: "cancelled" }), viva({ id: "s-otra" })] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("una prueba en curso cuenta como viva: ya va a cobrar en E", async () => {
    // El alumno ya volvio una vez con prueba (a1, autorizada y sin cobrar) y
    // aprieta de nuevo. a1 no puede probar un pago, pero SI esta viva.
    const { input } = armarAlumno({
      planes: [
        planDeAlumno("a0", 20),
        planDeAlumno("a1", 1, { diferidoHastaMs: FIN, currentPeriodEnd: ts(FIN) }),
      ],
      subs: {
        a1: [{
          id: "s-prueba",
          status: "authorized",
          auto_recurring: {
            frequency: 1,
            frequency_type: "months",
            free_trial: { frequency: 13, frequency_type: "days" },
          },
          summarized: { charged_quantity: 0, pending_charge_quantity: 0 },
        }],
      },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("⚠️ un link diferido pagado TARDE queda sin fecha (lo corta la guarda) y se consulta igual", async () => {
    // El hueco que encontro la revision: el reconciliador lee esa autorizacion
    // como `pending`, la guarda no escribe nada, y el plan queda SIN fecha aunque
    // la suscripcion este viva. Filtrar por fecha lo dejaba afuera, y un tercer
    // checkout le sumaba un segundo cobro.
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("a1", 3, { diferidoHastaMs: FIN })],
      subs: { a1: [viva({ id: "s-tarde" })] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("⚠️ una suscripcion viva sin fecha (MP no mando next_payment_date) se consulta igual", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("a1", 3)],
      subs: { a1: [viva({ id: "s-sin-fecha" })] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  for (const estado of ["paused", "pending", "un-estado-nuevo", undefined]) {
    it(`un estado que no es \`cancelled\` cuenta como viva: ${String(estado)}`, async () => {
      // El criterio de `sigueViva`: ante la duda de si ya paga, se cobra en el
      // acto como antes, nunca se le suma un segundo cobro en E.
      const { input } = armarAlumno({
        planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
        subs: { a1: [viva({ status: estado })] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
    });
  }

  it("mira TODOS los planes que pueden cobrar, no solo hasta el primero que pago", async () => {
    // El PF corta en el primer plan con pago; el alumno no puede, porque la viva
    // puede estar en un plan mas viejo.
    const { input, lecturas } = armarAlumno({
      planes: [
        planDeAlumno("a0", 30, { currentPeriodEnd: ts(AHORA + 2 * DIA_MS) }),
        planDeAlumno("a1", 20),
        planDeAlumno("a2", 10, { currentPeriodEnd: ts(FIN + DIA_MS) }),
      ],
      subs: {
        a0: [viva()],
        a1: [pagada(ULTIMO_COBRO)],
        a2: [sinCobro],
      },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
    // Del mas nuevo al mas viejo, hasta encontrar la viva.
    expect(lecturas.suscripciones).toEqual(["a2", "a1", "a0"]);
  });

  it("un checkout abandonado que despues se pago SE consulta: puede estar vivo", async () => {
    // `terminal` con [MOTIVO_ABANDONO] no es un hecho: el `init_point` no vence.
    const { input } = armarAlumno({
      planes: [
        planDeAlumno("a0", 20),
        planDeAlumno("a1", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
      ],
      subs: { a1: [viva()] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });

  it("loguea cual es el plan vivo", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      subs: { a1: [viva()] },
    });

    await decidirDiferimientoDeAlumno(input);

    expect(logger.info).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: se cobra en el acto",
      expect.objectContaining({
        producto: "athlete",
        motivo: "no-esta-cancelada",
        planVivo: "a1",
      }),
    );
  });
});

describe("decidirDiferimientoDeAlumno: un plan con fecha que MP devuelve vacio NO esta dado de baja", () => {
  // Un plan con fecha tuvo una suscripcion. Si la busqueda no la trae, MP no
  // contesto por ella: su indice llega tarde a una recien autorizada, y el cliente
  // convierte una respuesta rara en `[]`. Para el PF eso es "sin evidencia" y cobra
  // en el acto; para el alumno seria dar por dada de baja a una que quiza cobra.

  it("⚠️ otro plan con fecha que vuelve vacio: sin-respuesta-de-mp, no se difiere", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), planDeAlumno("a1", 5)],
      subs: { a1: [] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-respuesta-de-mp" });
  });

  it("el plan que pago vacio tampoco se da por dado de baja", async () => {
    const { input } = armarAlumno({ subs: { a0: [] } });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-respuesta-de-mp" });
  });

  it("un checkout SIN fecha que vuelve vacio es lo normal: no impide diferir", async () => {
    // Nadie lo pago: que MP no tenga ninguna suscripcion es la respuesta.
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("c1", 1)],
      subs: { c1: [] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });
});

describe("decidirDiferimientoDeAlumno: que planes se consultan y cuales prueban un pago", () => {
  it("los checkouts sin pagar se consultan (MP dice que no tienen nada) y no impiden diferir", async () => {
    const { input, lecturas } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("c1", 1), sinFecha("c2", 2)],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["c1", "c2", "a0"]);
  });

  it("un abandonado SIN fecha no prueba un pago, pero se consulta para saber si esta vivo", async () => {
    // Al cerrarse no tenia ninguna suscripcion: no puede ser evidencia. Pero si MP
    // le devuelve una cancelada (o nada), el diferimiento sigue como si no estuviera.
    const { input, lecturas } = armarAlumno({
      planes: [
        planDeAlumno("a0", 20),
        sinFecha("ab", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
      ],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toEqual(["a0", "ab"]);
  });

  for (const estado of ["pending", "authorized", "paused", "un-estado-nuevo"]) {
    it(`⚠️ ${estado} en un abandonado SIN fecha frena el diferimiento, como en cualquier otro plan`, async () => {
      // Si se autoriza despues, cobra desde E junto con el plan nuevo: el mismo
      // criterio que una `pending` en un plan con fecha o sin ella.
      const { input } = armarAlumno({
        planes: [
          planDeAlumno("a0", 20),
          sinFecha("ab", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
        ],
        subs: { ab: [viva({ status: estado })] },
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
    });
  }

  it("un abandonado SIN fecha que MP no conoce (lista vacia) no frena nada", async () => {
    const { input } = armarAlumno({
      planes: [
        planDeAlumno("a0", 20),
        sinFecha("ab", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
      ],
      subs: { ab: [] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("sin ningun plan con fecha de fin: sin-fecha-de-fin, sin preguntarle a MP", async () => {
    const { input, lecturas } = armarAlumno({ planes: [sinFecha("c1", 1)] });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-fecha-de-fin" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("un plan terminal ya no cobra y no se consulta", async () => {
    // El reconciliador del alumno marca `terminal` cuando el acceso ya vencio.
    const { input, lecturas } = armarAlumno({
      planes: [planDeAlumno("a0", 20, { terminal: true })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-fecha-de-fin" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("un plan de PF del mismo uid no cuenta, tenga o no el campo `producto`", async () => {
    // No deberia pasar (`role` es inmutable), pero un plan de PF no dice nada de
    // la suscripcion del alumno. Sin el campo es de PF: es el default de `lookupPlan`.
    for (const producto of ["trainer", undefined]) {
      const { input } = armarAlumno({
        planes: [planDeAlumno("a0", 20, { producto })],
      });

      expect(await decidirDiferimientoDeAlumno(input))
        .toEqual({ diferir: false, motivo: "sin-fecha-de-fin" });
    }
  });

  it("un plan ARREPENTIDO no prueba un pago: se devolvio entero", async () => {
    // El reconciliador lo marca `terminal` apenas lo procesa, pero si esa corrida
    // fallo el plan sigue con su fecha, y MP sigue mostrando el cobro.
    const { input, lecturas } = armarAlumno({
      planes: [planDeAlumno("a0", 20, { arrepentidoAtMs: AHORA - DIA_MS })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("un plan con prueba que todavia no pudo cobrar no prueba un pago", async () => {
    // El filtro 3 del PF: E esta a mas de un dia, el primer cobro no pudo ocurrir.
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 1, { diferidoHastaMs: AHORA + 2 * DIA_MS })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("una prueba que vence dentro del adelanto (menos de un dia) SI puede haber cobrado", async () => {
    // El primer cobro puede caer hasta [ADELANTO_MAXIMO_DEL_COBRO_MS] antes de E.
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 30, { diferidoHastaMs: AHORA + DIA_MS / 2 })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
  });

  it("un checkout abandonado que despues se pago no prueba un pago", async () => {
    // Mismo criterio que el PF (ver `planesARevisar`).
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("si a ningun plan le queda un dia: queda-menos-de-un-dia, sin preguntarle a MP", async () => {
    const { input, lecturas } = armarAlumno({
      planes: [planDeAlumno("a0", 20, { currentPeriodEnd: ts(AHORA + DIA_MS / 2) })],
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "queda-menos-de-un-dia" });
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("sin un cobro real en MP: sin-pago-comprobado", async () => {
    const { input } = armarAlumno({ subs: { a0: [sinCobro] } });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "sin-pago-comprobado" });
  });

  it("si lo que MP respalda vence en menos de un dia: pago-vence-pronto", async () => {
    // El cobro del 7/8 a las 20:00 cubre hasta el 7/9 a las 20:00: 8 horas.
    const { input } = armarAlumno({
      subs: { a0: [pagada("2026-08-07T20:00:00.000Z")] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "pago-vence-pronto" });
  });
});

describe("decidirDiferimientoDeAlumno: el tope", () => {
  const planes = (n: number) => [
    planDeAlumno("a0", 30),
    ...Array.from({ length: n - 1 }, (_, k) => sinFecha(`c${k}`, 1 + k)),
  ];

  it("con mas planes que pueden cobrar que el tope NO difiere, y avisa", async () => {
    // No se puede saber si alguno sigue vivo sin pasarse de llamadas: se cobra en
    // el acto, como antes, y queda un warn para que alguien lo mire.
    const { input, lecturas } = armarAlumno({ planes: planes(MAX_PLANES_DEL_ALUMNO_A_REVISAR + 1) });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "demasiados-planes" });
    expect(lecturas.suscripciones).toEqual([]);
    expect(logger.warn).toHaveBeenCalledWith(
      "mp/diferir-primer-cobro: el alumno tiene mas planes que pueden cobrar " +
        "que los que se revisan, no se difiere",
      expect.objectContaining({ uid: "u1", tope: MAX_PLANES_DEL_ALUMNO_A_REVISAR }),
    );
  });

  it("con exactamente el tope los consulta a todos y difiere", async () => {
    const { input, lecturas } = armarAlumno({ planes: planes(MAX_PLANES_DEL_ALUMNO_A_REVISAR) });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: true, diferidoHastaMs: FIN });
    expect(lecturas.suscripciones).toHaveLength(MAX_PLANES_DEL_ALUMNO_A_REVISAR);
  });

  it("el tope del alumno es mas ancho que el del PF: tiene que contar los checkouts sin pagar", () => {
    expect(MAX_PLANES_DEL_ALUMNO_A_REVISAR).toBeGreaterThan(MAX_PLANES_A_REVISAR);
  });
});

describe("decidirDiferimientoDeAlumno: si no puede LEER, tira", () => {
  it("si fallan los planes", async () => {
    const { input } = armarAlumno({ planes: new Error("UNAVAILABLE") });

    await expect(decidirDiferimientoDeAlumno(input)).rejects.toThrow("UNAVAILABLE");
  });

  it("si falla MP, aunque sea en un plan que no prueba nada", async () => {
    // Ese plan podria tener la suscripcion viva: no saberlo no es "no hay".
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("c1", 1)],
      subs: { c1: new Error("503") },
    });

    await expect(decidirDiferimientoDeAlumno(input)).rejects.toThrow("503");
  });
});

describe("decidirDiferimientoDeAlumno: sin atajo del doble click", () => {
  // El atajo del PF reusa la fecha del checkout abierto sin preguntarle nada a MP.
  // Para el alumno esa pregunta es la que dice que nadie esta vivo (y la que
  // levanta la guarda del mismo ciclo): cada toque la vuelve a hacer.

  it("dos toques iguales llegan a la MISMA fecha: es lo que deja reusar el checkout abierto", async () => {
    const primero = armarAlumno();
    const segundo = armarAlumno({
      // El checkout diferido del primer toque, abierto y sin pagar.
      planes: [planDeAlumno("a0", 20), sinFecha("nuevo", 0, { diferidoHastaMs: FIN })],
    });

    const a = await decidirDiferimientoDeAlumno(primero.input);
    const b = await decidirDiferimientoDeAlumno(segundo.input);

    expect(b).toEqual(a);
    expect(segundo.lecturas.suscripciones).toEqual(["nuevo", "a0"]);
  });

  it("si en el medio autorizo ese checkout, el segundo toque lo ve vivo y no difiere", async () => {
    const { input } = armarAlumno({
      planes: [planDeAlumno("a0", 20), sinFecha("nuevo", 0, { diferidoHastaMs: FIN })],
      subs: { nuevo: [viva({ id: "s-nueva" })] },
    });

    expect(await decidirDiferimientoDeAlumno(input))
      .toEqual({ diferir: false, motivo: "no-esta-cancelada" });
  });
});

describe("decidirDiferimientoDeAlumno: el interruptor", () => {
  it("apagado NUNCA difiere y no lee NADA", async () => {
    const { input, lecturas } = armarAlumno();

    expect(await decidirDiferimientoDeAlumno({ ...input, habilitado: false }))
      .toEqual({ diferir: false, motivo: "deshabilitado" });
    expect(lecturas.planes).toBe(0);
    expect(lecturas.suscripciones).toEqual([]);
  });

  it("sin pasarlo vale la constante, sea cual sea su valor", async () => {
    const { input } = armarAlumno();
    delete (input as { habilitado?: boolean }).habilitado;

    const sinParametro = await decidirDiferimientoDeAlumno(input);
    const conLaConstante = await decidirDiferimientoDeAlumno({
      ...input,
      habilitado: DIFERIR_PRIMER_COBRO_ENABLED,
    });

    expect(sinParametro).toEqual(conLaConstante);
  });
});

describe("planesDelAlumnoARevisar", () => {
  it("del mas nuevo al mas viejo, con el fin de cada uno, tengan o no fecha", () => {
    const r = planesDelAlumnoARevisar(
      [
        planDeAlumno("viejo", 30),
        sinFecha("sin-pagar", 1),
        planDeAlumno("nuevo", 2, { currentPeriodEnd: ts(FIN + DIA_MS) }),
      ],
      AHORA,
    );

    expect(r).toEqual([
      { id: "sin-pagar", finMs: null, puedeSerEvidencia: false },
      { id: "nuevo", finMs: FIN + DIA_MS, puedeSerEvidencia: true },
      { id: "viejo", finMs: FIN, puedeSerEvidencia: true },
    ]);
  });

  it("una fecha que no es un Timestamp no cuenta como fecha", () => {
    for (const currentPeriodEnd of [FIN, "2026-09-20", null, { toMillis: () => NaN }]) {
      expect(planesDelAlumnoARevisar([planDeAlumno("a0", 20, { currentPeriodEnd })], AHORA))
        .toEqual([{ id: "a0", finMs: null, puedeSerEvidencia: false }]);
    }
  });

  it("deja afuera lo que ya no puede cobrar y el abandonado sin fecha", () => {
    const r = planesDelAlumnoARevisar(
      [
        planDeAlumno("terminal", 30, { terminal: true }),
        planDeAlumno("reemplazado", 30, { terminal: true, terminalReason: MOTIVO_REEMPLAZO }),
        sinFecha("abandonado", 40, { terminal: true, terminalReason: MOTIVO_ABANDONO }),
        planDeAlumno("de-pf", 30, { producto: undefined }),
      ],
      AHORA,
    );

    expect(r).toEqual([]);
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

  it("cancelada: un fin MUY anterior a E (5 dias) se respeta, no lo explica ningun calendario", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - 5 * DIA_MS)))
      .toBe(FIN - 5 * DIA_MS);
  });

  // ── El primer cobro programado cae unas horas ANTES de E: el acceso llega a E ──
  //
  // Con dias de calendario argentino, el primer cobro de la prueba cae el mismo dia
  // que E a la hora en que se autorizo. En el caso real (autorizada a las 09:35 ART,
  // E a las 11:47 ART) cae 2 h 12 min antes. Si el PF cancela antes de ese cobro y
  // MP devuelve esa fecha, `min(fin, E)` le cortaba el acceso ahi: horas de un
  // periodo que ya pago a traves del plan anterior.

  /** El caso real: el primer cobro programado, 2 h 12 min antes de E. */
  const DOS_HORAS_Y_DOCE = (2 * 60 + 12) * 60 * 1000;

  it("cancelada con el fin 2 h 12 min ANTES de E (el primer cobro programado): conserva hasta E", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - DOS_HORAS_Y_DOCE)))
      .toBe(FIN);
  });

  it("y con el peor caso del modelo, casi un dia antes de la hora exacta de E: tambien E", () => {
    // Hoy a las 00:01 ART y E a las 23:59 de ese dia: el cobro cae 23 h 58 min antes.
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - (DIA_MS - 2 * 60_000))))
      .toBe(FIN);
  });

  it("el borde: a exactamente ADELANTO_MAXIMO_DEL_COBRO_MS antes de E tambien es E", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(
      cancelada(FIN - ADELANTO_MAXIMO_DEL_COBRO_MS),
    )).toBe(FIN);
  });

  it("y un milisegundo mas lejos se respeta tal cual", () => {
    const fin = FIN - ADELANTO_MAXIMO_DEL_COBRO_MS - 1;

    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(fin))).toBe(fin);
  });

  it("pausada con el fin unas horas antes de E tambien llega hasta E", () => {
    expect(aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - DOS_HORAS_Y_DOCE, {
      mpStatus: "paused",
      statusHoy: "paused" as const,
    }))).toBe(FIN);
  });

  it("autorizada o pendiente: un fin unas horas antes de E NO se toca", () => {
    // Solo una suscripcion cancelada o pausada se ajusta: la autorizada tiene como fin
    // el proximo cobro de MP, tal cual.
    for (const mpStatus of ["authorized", "pending"]) {
      expect(aplicarPruebaDiferidaAlPeriodo({
        ...EN_PRUEBA,
        mpStatus,
        periodEndMs: FIN - DOS_HORAS_Y_DOCE,
      })).toBe(FIN - DOS_HORAS_Y_DOCE);
    }
  });

  it("con cobros >= 1 un fin antes de E tampoco se toca: el PF ya esta pagando este plan", () => {
    const r = aplicarPruebaDiferidaAlPeriodo(cancelada(FIN - DOS_HORAS_Y_DOCE, {
      summarized: { charged_quantity: 1, charged_amount: 22000 },
    }));

    expect(r).toBe(FIN - DOS_HORAS_Y_DOCE);
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

  it("el borde: a exactamente el margen del aviso antes de E todavia no avisa", () => {
    expect(cobroAntesDeLaPrueba(entrada(FIN - MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS)))
      .toBe(false);
  });

  it("un milisegundo antes de ese margen SI avisa", () => {
    expect(cobroAntesDeLaPrueba(entrada(FIN - MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS - 1)))
      .toBe(true);
  });

  it("el peor caso del modelo (casi un dia antes de la hora exacta de E) no avisa", () => {
    // Con dias de calendario argentino el primer cobro cae el mismo dia que E, a la
    // hora en que se autorizo: lo mas temprano es hoy a las 00:01 ART con E a las
    // 23:59 de ese dia, o sea 23 h 58 min antes. Es lo esperado, no un cobro doble.
    expect(cobroAntesDeLaPrueba(entrada(FIN - (DIA_MS - 2 * 60_000)))).toBe(false);
  });

  it("tampoco avisa con un dia de calendario MAS de adelanto: el calendario propio de MP", () => {
    // Si MP cuenta los dias en su calendario (-04:00, no esta medido), el cobro puede
    // caer un dia de calendario antes que en el modelo: a casi dos dias de E. Con un
    // margen de exactamente un dia este cobro legitimo hubiera avisado.
    const casiDosDias = ADELANTO_MAXIMO_DEL_COBRO_MS + DIA_MS - 60_000;

    expect(cobroAntesDeLaPrueba(entrada(FIN - casiDosDias))).toBe(false);
  });

  it("el aviso es mas ancho que el filtro de evidencia, y cada uno manda en lo suyo", () => {
    // A un dia y medio de E: el plan con prueba todavia no pudo cobrar, asi que no es
    // evidencia de un pago (el filtro usa ADELANTO_MAXIMO_DEL_COBRO_MS), pero un cobro
    // que apareciera igual en ese punto no avisa (el aviso usa su margen mas ancho).
    const e = AHORA + 1.5 * DIA_MS;

    expect(planesARevisar([plan("diferido", 1, { diferidoHastaMs: e })], "plan2", AHORA).ids)
      .toEqual([]);
    expect(cobroAntesDeLaPrueba(entrada(AHORA, { diferidoHastaMs: e }))).toBe(false);
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
