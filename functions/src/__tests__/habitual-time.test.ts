/** Unit tests de habitual-time.ts. Es puro: sin mocks, sin emulador, sin FCM. */

import {
  COMEBACK_REMINDER_FALLBACK_MINUTE,
  COMEBACK_REMINDER_OFFSET_MINUTES,
  HABITUAL_MIN_STARTS,
  HABITUAL_SAMPLE_SIZE,
  HABITUAL_WINDOW_MINUTES,
  REMINDER_MAX_MINUTE,
  REMINDER_MIN_MINUTE,
  STREAK_REMINDER_FALLBACK_MINUTE,
  STREAK_REMINDER_OFFSET_MINUTES,
  clampReminderMinute,
  comebackSendMinute,
  habitualStartMinute,
  minuteOfDayArt,
  startOfDayInstantArt,
  streakSendMinute,
} from "../notifications/habitual-time";

// ─── Builders ─────────────────────────────────────────────────────────────────

/** "HH:MM" → minuto del día. */
const hm = (clock: string): number => {
  const [h, m] = clock.split(":").map(Number);
  return h * 60 + m;
};

const DAY_MS = 24 * 60 * 60 * 1000;
/** 2026-05-01 00:00 ART. Argentina no tiene DST, así que sumar días enteros es exacto. */
const DAY_ONE_MS = new Date("2026-05-01T00:00:00-03:00").getTime();

/**
 * Inicio de sesión: el día [day] de mayo de 2026 a las [clock] hora ART. Un día
 * más alto es una sesión más reciente.
 */
const start = (day: number, clock: string): number =>
  DAY_ONE_MS + (day - 1) * DAY_MS + hm(clock) * 60_000;

/** Una sesión por día, desde el [firstDay], a las horas dadas. */
const run = (firstDay: number, clocks: string[]): number[] =>
  clocks.map((clock, i) => start(firstDay + i, clock));

const reversed = <T>(xs: readonly T[]): T[] => [...xs].reverse();

/** Todas las permutaciones: para afirmar que el ORDEN de entrada no decide. */
function permutations<T>(xs: readonly T[]): T[][] {
  if (xs.length <= 1) return [[...xs]];
  return xs.flatMap((x, i) =>
    permutations([...xs.slice(0, i), ...xs.slice(i + 1)]).map((rest) => [x, ...rest]));
}

// ─── Constantes ───────────────────────────────────────────────────────────────

describe("constantes del contrato de producto", () => {
  it("tienen los valores acordados", () => {
    expect(HABITUAL_SAMPLE_SIZE).toBe(12);
    expect(HABITUAL_MIN_STARTS).toBe(4);
    expect(HABITUAL_WINDOW_MINUTES).toBe(60);
    expect(STREAK_REMINDER_OFFSET_MINUTES).toBe(60);
    expect(COMEBACK_REMINDER_OFFSET_MINUTES).toBe(0);
    expect(REMINDER_MIN_MINUTE).toBe(480); // 08:00
    expect(REMINDER_MAX_MINUTE).toBe(1350); // 22:30
    expect(STREAK_REMINDER_FALLBACK_MINUTE).toBe(1080); // 18:00
    expect(COMEBACK_REMINDER_FALLBACK_MINUTE).toBe(540); // 09:00
  });
});

// ─── Reloj ART ────────────────────────────────────────────────────────────────

describe("minuteOfDayArt / startOfDayInstantArt", () => {
  it("lee la hora de pared argentina, no la UTC", () => {
    expect(minuteOfDayArt(new Date("2026-05-13T13:00:00Z").getTime())).toBe(hm("10:00"));
    // 02:30 UTC del día siguiente es 23:30 ART del anterior.
    expect(minuteOfDayArt(new Date("2026-05-14T02:30:00Z").getTime())).toBe(hm("23:30"));
  });

  it("los bordes del día: 00:00 ART es 0 y 23:59 ART es 1439", () => {
    expect(minuteOfDayArt(new Date("2026-05-13T03:00:00Z").getTime())).toBe(0);
    expect(minuteOfDayArt(new Date("2026-05-13T02:59:59Z").getTime())).toBe(1439);
  });

  it("un instante anterior a 1970 no da un minuto negativo", () => {
    expect(minuteOfDayArt(-60_000)).toBe(hm("20:59"));
  });

  it("startOfDayInstantArt es 00:00 ART como instante real (03:00 UTC)", () => {
    const at = (iso: string) => new Date(iso).getTime();
    expect(startOfDayInstantArt(at("2026-05-13T13:00:00Z")))
      .toBe(at("2026-05-13T03:00:00Z"));
    // 23:30 ART del 13 sigue siendo el día 13 (02:30 UTC del 14).
    expect(startOfDayInstantArt(at("2026-05-14T02:30:00Z")))
      .toBe(at("2026-05-13T03:00:00Z"));
    // Justo a medianoche ART arranca el día nuevo.
    expect(startOfDayInstantArt(at("2026-05-14T03:00:00Z")))
      .toBe(at("2026-05-14T03:00:00Z"));
  });
});

// ─── Horario habitual ─────────────────────────────────────────────────────────

describe("habitualStartMinute", () => {
  it("el ejemplo de producto: 17:40, 18:12, 18:15 y 18:05 dan ~18:08", () => {
    const starts = run(1, ["17:40", "18:12", "18:15", "18:05"]);

    expect(habitualStartMinute(starts)).toBe(hm("18:08"));
  });

  it("el orden de entrada no decide: las 24 permutaciones dan lo mismo", () => {
    const starts = run(1, ["17:40", "18:12", "18:15", "18:05"]);

    for (const permutation of permutations(starts)) {
      expect(habitualStartMinute(permutation)).toBe(hm("18:08"));
    }
  });

  it("no modifica el arreglo que recibe", () => {
    const starts = run(1, ["18:15", "17:40", "18:05", "18:12"]);
    const copy = [...starts];

    habitualStartMinute(starts);

    expect(starts).toEqual(copy);
  });

  it("con una cantidad impar de inicios es el del medio", () => {
    expect(habitualStartMinute(run(1, ["18:00", "18:10", "18:20", "18:30", "18:40"])))
      .toBe(hm("18:20"));
  });

  it("la mediana no se deja correr por un día raro dentro de la ventana", () => {
    // Un promedio daría 18:16; la mediana es 18:05.
    expect(habitualStartMinute(run(1, ["18:00", "18:02", "18:05", "18:08", "18:55"])))
      .toBe(hm("18:05"));
  });

  describe("la ventana es CIRCULAR: cruza la medianoche", () => {
    it("23:50, 23:55, 00:05 y 00:10 caen en la misma ventana", () => {
      const starts = run(1, ["23:50", "23:55", "00:05", "00:10"]);

      // Sin ventana circular cada lado junta 2 inicios y el resultado sería null.
      expect(habitualStartMinute(starts)).toBe(0);
    });

    it("el horario se normaliza a 0..1439 después de la medianoche", () => {
      // Desenrollado desde 23:50 la mediana cae en 00:05 del día siguiente.
      expect(habitualStartMinute(run(1, ["23:50", "23:58", "00:05", "00:20", "00:30"])))
        .toBe(hm("00:05"));
    });

    it("un grupo del mediodía no se mezcla con el de la medianoche", () => {
      const midnight = run(1, ["23:50", "23:55", "00:05", "00:10", "00:15"]);
      const noon = run(10, ["12:00", "12:05"]);

      expect(habitualStartMinute([...midnight, ...noon])).toBe(hm("00:05"));
    });
  });

  describe("sin patrón claro devuelve null", () => {
    it("sin sesiones", () => {
      expect(habitualStartMinute([])).toBeNull();
    });

    it("con menos de 4 sesiones, aunque coincidan exacto", () => {
      expect(habitualStartMinute(run(1, ["18:00", "18:00", "18:00"]))).toBeNull();
    });

    it("con 4 sesiones pero repartidas en horas distintas", () => {
      expect(habitualStartMinute(run(1, ["07:00", "11:00", "15:00", "19:00"]))).toBeNull();
    });

    it("con muchas sesiones pero ningún grupo llega a 4", () => {
      // Tres grupos de 3, separados por más de una hora.
      const starts = run(1, [
        "07:00", "07:10", "07:20",
        "13:00", "13:10", "13:20",
        "19:00", "19:10", "19:20",
      ]);

      expect(habitualStartMinute(starts)).toBeNull();
    });

    it("con exactamente 4 en la ventana ya hay patrón (el mínimo es inclusivo)", () => {
      expect(habitualStartMinute(run(1, ["18:00", "18:10", "18:20", "18:30"])))
        .toBe(hm("18:15"));
    });

    it("una sola pieza suelta más no completa el patrón", () => {
      // 3 en la ventana + 1 a las 03:00: la mejor ventana tiene 3.
      expect(habitualStartMinute(run(1, ["18:00", "18:10", "18:20", "03:00"]))).toBeNull();
    });
  });

  describe("el borde de la ventana de 60 minutos", () => {
    it("inicios separados por EXACTAMENTE 60 minutos caben juntos", () => {
      expect(habitualStartMinute(run(1, ["18:00", "18:20", "18:40", "19:00"])))
        .toBe(hm("18:30"));
    });

    it("con 61 minutos ya no", () => {
      // Ninguna ventana de 60 contiene los cuatro: la mejor tiene 3.
      expect(habitualStartMinute(run(1, ["18:00", "18:20", "18:40", "19:01"]))).toBeNull();
    });
  });

  describe("sólo cuentan las 12 sesiones más recientes", () => {
    const morning = (n: number) => Array.from({ length: n }, (_, i) => `07:${String(i * 5).padStart(2, "0")}`);

    it("un cambio de hábito se refleja: las sesiones viejas dejan de pesar", () => {
      // 30 noches viejas (19:00) y las 12 sesiones más nuevas a la mañana. Con
      // todo el historial ganaría la noche, 30 contra 12.
      const old = run(1, Array.from({ length: 30 }, () => "19:00"));
      const recent = run(31, ["07:00", "07:10", "07:20", "07:00", "07:10", "07:20",
        "07:00", "07:10", "07:20", "07:00", "07:10", "07:20"]);

      expect(habitualStartMinute([...old, ...recent])).toBe(hm("07:10"));
    });

    it("el borde es EXACTAMENTE 12, ni 11 ni 13", () => {
      // De más vieja a más nueva: 1 mañana vieja (la sesión 13°), 6 noches, las
      // 5 mañanas siguientes y un mediodía suelto (que no es de ningún grupo).
      //   · Muestra de 12 (días 2-13): 6 noches contra 5 mañanas → gana la noche.
      //   · Si fuera de 11 (sin el día 2): 5 contra 5, y el empate lo gana la
      //     mañana, que tiene la sesión más reciente.
      //   · Si fuera de 13 (con el día 1): 6 contra 6, otra vez la mañana.
      const starts = [
        start(1, "07:00"),
        ...run(2, ["19:00", "19:05", "19:10", "19:15", "19:20", "19:25"]),
        ...run(8, morning(5)),
        start(13, "13:00"),
      ];
      expect(starts).toHaveLength(13);

      expect(habitualStartMinute(starts)).toBe(hm("19:12"));
    });

    it("con 12 sesiones o menos entran todas", () => {
      expect(habitualStartMinute(run(1, ["18:00", "18:10", "18:20", "18:30"])))
        .not.toBeNull();
    });
  });

  describe("desempate determinista", () => {
    const A = ["07:00", "07:10", "07:20", "07:30"]; // mediana 07:15
    const B = ["19:00", "19:10", "19:20", "19:30"]; // mediana 19:15

    it("con dos grupos del mismo tamaño gana el de la sesión MÁS RECIENTE", () => {
      // La mañana es el hábito viejo y la noche el nuevo…
      const mañanaVieja = [...run(1, A), ...run(5, B)];
      expect(habitualStartMinute(mañanaVieja)).toBe(hm("19:15"));

      // …y al revés.
      const nocheVieja = [...run(1, B), ...run(5, A)];
      expect(habitualStartMinute(nocheVieja)).toBe(hm("07:15"));
    });

    it("el orden de llegada no cambia al ganador: las 40320 permutaciones dan lo mismo", () => {
      const starts = [...run(1, A), ...run(5, B)];

      for (const permutation of permutations(starts)) {
        expect(habitualStartMinute(permutation)).toBe(hm("19:15"));
      }
    });

    it("si las dos contienen la sesión más reciente, gana la más angosta", () => {
      // Todas dentro de 60 minutos de 17:00 y de 17:40, con la más nueva (17:50)
      // en las dos ventanas de 4:
      //   · desde 17:00 → 17:00, 17:40, 17:50, 18:00 (ancho 60), mediana 17:45
      //   · desde 17:40 → 17:40, 17:50, 18:00, 18:05 (ancho 25), mediana 17:55
      const starts = [
        start(1, "17:00"),
        start(2, "17:40"),
        start(4, "18:00"),
        start(5, "18:05"),
        start(9, "17:50"),
      ];

      expect(habitualStartMinute(starts)).toBe(hm("17:55"));
      expect(habitualStartMinute(reversed(starts))).toBe(hm("17:55"));
    });

    it("si todo empata, gana la que arranca más temprano en el día", () => {
      // Dos ventanas de 4, las dos con ancho 60 y las dos con la más nueva (17:40):
      //   · desde 17:00 → 17:00, 17:20, 17:40, 18:00 → 17:30
      //   · desde 17:20 → 17:20, 17:40, 18:00, 18:20 → 17:50
      const starts = [
        start(1, "17:00"),
        start(2, "17:20"),
        start(4, "18:00"),
        start(5, "18:20"),
        start(9, "17:40"),
      ];

      expect(habitualStartMinute(starts)).toBe(hm("17:30"));
      for (const permutation of permutations(starts)) {
        expect(habitualStartMinute(permutation)).toBe(hm("17:30"));
      }
    });
  });

  it("ignora valores que no son instantes (NaN, Infinity)", () => {
    const starts = [...run(1, ["18:00", "18:10", "18:20", "18:30"]), NaN, Infinity];

    expect(habitualStartMinute(starts)).toBe(hm("18:15"));
  });
});

// ─── Hora del recordatorio ────────────────────────────────────────────────────

describe("hora del recordatorio", () => {
  it("clampReminderMinute acota a [08:00, 22:30]", () => {
    expect(clampReminderMinute(0)).toBe(480);
    expect(clampReminderMinute(479)).toBe(480);
    expect(clampReminderMinute(480)).toBe(480);
    expect(clampReminderMinute(900)).toBe(900);
    expect(clampReminderMinute(1350)).toBe(1350);
    expect(clampReminderMinute(1351)).toBe(1350);
    expect(clampReminderMinute(1439)).toBe(1350);
  });

  describe("racha en riesgo: habitual + 60, o 18:00 sin patrón", () => {
    it("el ejemplo de producto: habitual ~18:08 → 19:08", () => {
      expect(streakSendMinute(hm("18:08"))).toBe(hm("19:08"));
    });

    it("sin patrón sale a las 18:00", () => {
      expect(streakSendMinute(null)).toBe(1080);
    });

    it("el piso es 08:00: quien entrena a las 06:00 lo recibe a las 08:00", () => {
      expect(streakSendMinute(hm("06:00"))).toBe(480);
      expect(streakSendMinute(hm("07:00"))).toBe(480); // 07:00 + 60 = 08:00 justo
      expect(streakSendMinute(hm("07:01"))).toBe(hm("08:01"));
    });

    it("el techo es 22:30: quien entrena a las 22:00 lo recibe a las 22:30", () => {
      expect(streakSendMinute(hm("22:00"))).toBe(1350);
      expect(streakSendMinute(hm("21:30"))).toBe(1350); // 21:30 + 60 = 22:30 justo
      expect(streakSendMinute(hm("21:29"))).toBe(hm("22:29"));
      expect(streakSendMinute(hm("23:50"))).toBe(1350);
    });

    it("quien entrena pasada la medianoche cae en el piso, no en la madrugada", () => {
      expect(streakSendMinute(hm("00:05"))).toBe(480);
    });
  });

  describe("volvé a entrenar: la hora habitual, o 09:00 sin patrón", () => {
    it("sale a la hora a la que suele entrenar", () => {
      expect(comebackSendMinute(hm("18:08"))).toBe(hm("18:08"));
    });

    it("sin patrón sale a las 09:00", () => {
      expect(comebackSendMinute(null)).toBe(540);
    });

    it("el piso es 08:00: quien entrena a las 06:30 lo recibe a las 08:00", () => {
      expect(comebackSendMinute(hm("06:30"))).toBe(480);
      expect(comebackSendMinute(hm("08:00"))).toBe(480);
      expect(comebackSendMinute(hm("07:59"))).toBe(480);
      expect(comebackSendMinute(hm("08:01"))).toBe(hm("08:01"));
    });

    it("el techo es 22:30", () => {
      expect(comebackSendMinute(hm("22:30"))).toBe(1350);
      expect(comebackSendMinute(hm("22:45"))).toBe(1350);
    });
  });

  it("de punta a punta, de las sesiones a la hora de cada recordatorio", () => {
    const starts = run(1, ["17:40", "18:12", "18:15", "18:05"]);
    const habitual = habitualStartMinute(starts);

    expect(streakSendMinute(habitual)).toBe(hm("19:08"));
    expect(comebackSendMinute(habitual)).toBe(hm("18:08"));
  });
});
