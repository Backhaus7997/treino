/**
 * mp-plazo-arrepentimiento.test.ts — ¿este arrepentimiento llega a tiempo?
 *
 * PURO, con fechas concretas. Esta es la decisión que dice si hay plata que
 * devolver, así que cada borde tiene su caso: el último minuto del último día,
 * el primer minuto después, el fin de semana, y el cambio de día que en UTC cae
 * tres horas antes que en Argentina.
 *
 * Calendario de referencia (septiembre de 2026): el 14 es lunes, el 24 jueves,
 * el 26 sábado, el 27 domingo, el 28 lunes.
 */

import {
  DIAS_DE_DUDA,
  PLAZO_DIAS,
  evaluarPlazo,
} from "../subscriptions/mp/plazo-arrepentimiento";

/** Un instante en hora de Argentina (UTC-3, sin horario de verano). */
const art = (dia: number, hora = 12, min = 0, mes = 9) =>
  Date.UTC(2026, mes - 1, dia, hora + 3, min);

/** El día (en hora Argentina) que muestra `ultimoDiaMs`, como YYYY-MM-DD. */
const dia = (ms: number | null) =>
  ms === null ? null : new Date(ms - 3 * 60 * 60 * 1000).toISOString().slice(0, 10);

describe("los diez días corridos", () => {
  it("el plazo es de 10 días y la franja de duda de 4", () => {
    // Si alguien toca estos números, que sea a propósito.
    expect(PLAZO_DIAS).toBe(10);
    expect(DIAS_DE_DUDA).toBe(4);
  });

  it("el último minuto del décimo día todavía está DENTRO", () => {
    // Contrató el lunes 14; el décimo día es el jueves 24.
    const p = evaluarPlazo(art(14, 15), art(24, 23, 59));

    expect(p.estado).toBe("dentro");
    expect(dia(p.ultimoDiaMs)).toBe("2026-09-24");
  });

  it("el primer minuto del día 11 ya no: pasa a revisar, no a rechazar", () => {
    expect(evaluarPlazo(art(14, 15), art(25, 0, 1)).estado).toBe("a-revisar");
  });

  it("el día de la contratación no cuenta: el plazo corre desde el siguiente", () => {
    // Contrató el 14 a las 23:59; sigue dentro el 24, no el 23.
    expect(evaluarPlazo(art(14, 23, 59), art(24, 23, 59)).estado).toBe("dentro");
  });

  it("cuenta los días transcurridos en hora Argentina", () => {
    expect(evaluarPlazo(art(14), art(14, 20)).diasTranscurridos).toBe(0);
    expect(evaluarPlazo(art(14), art(24)).diasTranscurridos).toBe(10);
  });
});

describe("⚠️ hora de Argentina, no UTC", () => {
  it("quien contrató de noche no contrató «mañana»", () => {
    // Domingo 13 a las 22:30 ART = lunes 14 a las 01:30 UTC. Si se contara en
    // UTC, el décimo día sería el jueves 24 y no el miércoles 23.
    const contrato = Date.UTC(2026, 8, 14, 1, 30);

    expect(evaluarPlazo(contrato, art(23, 23, 30)).estado).toBe("dentro");
    // 00:00 ART del 24 = 03:00 UTC. En UTC ya sería «dentro» hasta el 24.
    expect(evaluarPlazo(contrato, Date.UTC(2026, 8, 24, 3, 0)).estado).toBe("a-revisar");
  });
});

describe("el último día cae en fin de semana: se corre al lunes (términos §6)", () => {
  it("sábado → lunes", () => {
    // Contrató el miércoles 16: el décimo día es el sábado 26.
    const p = evaluarPlazo(art(16), art(28, 23, 59));

    expect(p.estado).toBe("dentro");
    expect(dia(p.ultimoDiaMs)).toBe("2026-09-28");
  });

  it("domingo → lunes", () => {
    // Contrató el jueves 17: el décimo día es el domingo 27.
    const p = evaluarPlazo(art(17), art(28, 23, 59));

    expect(p.estado).toBe("dentro");
    expect(dia(p.ultimoDiaMs)).toBe("2026-09-28");
  });

  it("y el martes siguiente ya es revisar", () => {
    expect(evaluarPlazo(art(16), art(29, 0, 1)).estado).toBe("a-revisar");
  });
});

describe("⚠️ la franja de duda: un feriado pudo haber corrido el plazo", () => {
  it("dura DIAS_DE_DUDA días después del último día", () => {
    // Último día: jueves 24. La franja llega hasta el lunes 28 inclusive.
    expect(evaluarPlazo(art(14), art(28, 23, 59)).estado).toBe("a-revisar");
  });

  it("y después se rechaza", () => {
    expect(evaluarPlazo(art(14), art(29, 0, 1)).estado).toBe("fuera");
    expect(evaluarPlazo(art(14), art(30)).estado).toBe("fuera");
  });

  it("un pedido de hace meses es FUERA, sin franja que valga", () => {
    // El caso que motivó todo esto: contrató en junio, pide en septiembre.
    const p = evaluarPlazo(art(15, 12, 0, 6), art(28));

    expect(p.estado).toBe("fuera");
    expect(dia(p.ultimoDiaMs)).toBe("2026-06-25");
  });
});

describe("sin fecha no se decide", () => {
  it.each([null, Number.NaN, Number.POSITIVE_INFINITY])(
    "%s → a revisar, sin aprobar ni rechazar a ciegas",
    (contrato) => {
      // Aprobar devuelve plata que no sabemos si corresponde; rechazar le quita
      // un derecho irrenunciable por un dato que nos faltó a nosotros.
      const p = evaluarPlazo(contrato, art(28));

      expect(p).toEqual({ estado: "a-revisar", ultimoDiaMs: null, diasTranscurridos: null });
    },
  );

  it("una fecha de contratación futura (reloj corrido) no rechaza a nadie", () => {
    expect(evaluarPlazo(art(29), art(28)).estado).toBe("dentro");
  });
});
