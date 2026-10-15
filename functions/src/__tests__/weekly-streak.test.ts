/**
 * Tests del port TypeScript de la racha semanal (`notifications/weekly-streak.ts`).
 * Sin emulador, sin mocks: el módulo es puro.
 *
 * Tres fuentes de verdad, tres bloques:
 *
 *   1. `conformance/session_counting.json`  — los MISMOS casos que corren Dart y
 *      Swift. Es el seguro contra que el servidor cuente sesiones distinto.
 *   2. `conformance/routine_selection.json` — idem, para qué rutina es la activa.
 *   3. `test/core/utils/weekly_streak_calculator_test.dart` — los casos de la
 *      aritmética de semanas, portados uno a uno (no tienen fixture compartido).
 *
 * Los dos primeros siguen el patrón de `test/conformance/*_conformance_test.dart`:
 * un guard de que el fixture apunta a la implementación correcta, otro de que no
 * está vacío (un archivo sin casos pasa en falso), y TODAS las discrepancias
 * acumuladas antes de fallar en vez de esconder las demás detrás de la primera.
 */

import * as fs from "fs";
import * as path from "path";
import { artDateKey } from "../mail/format";
import {
  WEEKLY_STREAK_FALLBACK_TARGET,
  artDayNumber,
  computeWeeklyStreak,
  daysLeftInWeekArt,
  mondayOfWeekArt,
  resolveActiveRoutineId,
  sessionCountsAsWorkout,
  toArgentina,
  weekStartInstantArt,
  weeklyStreakDetail,
  weeklyStreakFromStarts,
  weeklyStreakOf,
  weeklyTargetFromRoutine,
} from "../notifications/weekly-streak";

// ─── Fixtures compartidos ─────────────────────────────────────────────────────

// functions/src/__tests__ → raíz del repo.
const CONFORMANCE = path.resolve(__dirname, "..", "..", "..", "conformance");

interface Fixture<Given, Expect> {
  rule: string;
  source_of_truth: string;
  cases: Array<{ name: string; given: Given; expect: Expect }>;
}

function loadFixture<Given, Expect>(file: string): Fixture<Given, Expect> {
  const full = path.join(CONFORMANCE, file);
  if (!fs.existsSync(full)) {
    throw new Error(
      `No se encontró ${full}. Los fixtures de conformidad son el contrato con ` +
      "Dart y Swift: si el archivo no está, ese contrato no existe.",
    );
  }
  return JSON.parse(fs.readFileSync(full, "utf8")) as Fixture<Given, Expect>;
}

describe("conformance — session_counting.json", () => {
  const fixture = loadFixture<
    { status: string | null; wasFullyCompleted: boolean | null },
    { countsAsWorkout: boolean }
  >("session_counting.json");

  it("el fixture apunta a la implementación que este test ejercita", () => {
    expect(fixture.rule).toBe("session-counting");
    expect(fixture.source_of_truth).toBe("lib/features/workout/domain/session.dart");
  });

  it("el fixture tiene casos: un archivo vacío pasaría en falso", () => {
    expect(fixture.cases.length).toBeGreaterThan(0);
  });

  it("cada caso resuelve como dice el contrato", () => {
    const failures: string[] = [];
    for (const testCase of fixture.cases) {
      const actual = sessionCountsAsWorkout(
        testCase.given.status,
        testCase.given.wasFullyCompleted,
      );
      if (actual !== testCase.expect.countsAsWorkout) {
        failures.push(
          `  · "${testCase.name}"\n` +
          `      esperado: ${testCase.expect.countsAsWorkout}\n` +
          `      obtenido: ${actual}`,
        );
      }
    }

    // Si el contrato es el correcto, se arregla weekly-streak.ts; si está mal, se
    // corrige conformance/session_counting.json PRIMERO y después las
    // implementaciones — nunca al revés.
    expect(failures.join("\n")).toBe("");
  });

  it("un campo AUSENTE (undefined) da lo mismo que un nulo explícito", () => {
    // El fixture modela las dos cosas con `null`; en TypeScript son dos valores
    // distintos y los datos de Firestore traen el segundo.
    expect(sessionCountsAsWorkout("finished", undefined)).toBe(false);
    expect(sessionCountsAsWorkout(undefined, true)).toBe(false);
    expect(sessionCountsAsWorkout(undefined, undefined)).toBe(false);
  });
});

describe("conformance — routine_selection.json", () => {
  const fixture = loadFixture<
    {
      activeRoutineId: string | null;
      assignedIds: string[];
      selfCreatedIds: string[];
      catalogIds?: string[];
    },
    { routineId: string | null }
  >("routine_selection.json");

  it("el fixture apunta a la implementación que este test ejercita", () => {
    expect(fixture.rule).toBe("routine-selection");
    expect(fixture.source_of_truth).toBe(
      "lib/features/workout/domain/routine_selection.dart",
    );
  });

  it("el fixture tiene casos: un archivo vacío pasaría en falso", () => {
    expect(fixture.cases.length).toBeGreaterThan(0);
  });

  it("cada caso resuelve como dice el contrato", () => {
    const failures: string[] = [];
    for (const testCase of fixture.cases) {
      const actual = resolveActiveRoutineId({
        activeRoutineId: testCase.given.activeRoutineId,
        assignedIds: testCase.given.assignedIds,
        selfCreatedIds: testCase.given.selfCreatedIds,
        // Opcional en el fixture: ausente significa lista vacía.
        catalogIds: testCase.given.catalogIds ?? [],
      });
      if (actual !== testCase.expect.routineId) {
        failures.push(
          `  · "${testCase.name}"\n` +
          `      esperado: ${testCase.expect.routineId ?? "null"}\n` +
          `      obtenido: ${actual ?? "null"}`,
        );
      }
    }
    expect(failures.join("\n")).toBe("");
  });

  it("sin catalogIds el resultado no cambia (la optimización del llamador)", () => {
    // El llamador pasa [] cuando ya sabe que el catálogo no se hubiera consultado.
    for (const testCase of fixture.cases) {
      if (testCase.given.catalogIds !== undefined) continue;
      expect(
        resolveActiveRoutineId({
          activeRoutineId: testCase.given.activeRoutineId,
          assignedIds: testCase.given.assignedIds,
          selfCreatedIds: testCase.given.selfCreatedIds,
        }),
      ).toBe(testCase.expect.routineId);
    }
  });
});

// ─── Port de weekly_streak_calculator_test.dart ───────────────────────────────

// Fixtures UTC al MEDIODÍA (09:00 ART), misma convención que el test de Dart:
// nunca cruza medianoche, así que el resultado no depende del día en que corra.
const finishedOn = (utc: Date) => ({
  startedAt: utc,
  status: "finished",
  wasFullyCompleted: true,
});

/** n sesiones que califican en la semana que arranca el lunes `monday` (UTC). */
const weekWith = (monday: Date, n: number) =>
  Array.from({ length: n }, (_, i) =>
    finishedOn(
      new Date(Date.UTC(
        monday.getUTCFullYear(),
        monday.getUTCMonth(),
        monday.getUTCDate() + i,
        12,
      )),
    ));

// Lunes 2026-05-11. El "hoy" de casi todos los casos es el miércoles 2026-05-13.
const week0 = new Date(Date.UTC(2026, 4, 11)); // semana en curso
const week1 = new Date(Date.UTC(2026, 4, 4)); // anterior
const week2 = new Date(Date.UTC(2026, 3, 27));
const week3 = new Date(Date.UTC(2026, 3, 20));
const wednesday = new Date(Date.UTC(2026, 4, 13, 12));

describe("computeWeeklyStreak — la semana en curso nunca corta", () => {
  it("el caso del producto: 3 semanas cumplidas y la 4ta falla → 3", () => {
    const sessions = [
      ...weekWith(week0, 1),
      ...weekWith(week1, 3),
      ...weekWith(week2, 3),
      ...weekWith(week3, 3),
    ];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(3);
  });

  it("la semana en curso ya cumplida SÍ suma", () => {
    const sessions = [...weekWith(week0, 3), ...weekWith(week1, 3)];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(2);
  });

  it("semana en curso vacía no corta: cuenta desde la anterior", () => {
    const sessions = [...weekWith(week1, 3), ...weekWith(week2, 3)];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(2);
  });

  it("una semana cerrada incompleta corta la racha ahí", () => {
    // week1 va 2 de 3 → corta. week2/week3 cumplen pero quedan del otro lado.
    const sessions = [
      ...weekWith(week0, 3),
      ...weekWith(week1, 2),
      ...weekWith(week2, 3),
      ...weekWith(week3, 3),
    ];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(1);
  });
});

describe("computeWeeklyStreak — bordes", () => {
  it("sin sesiones → 0", () => {
    expect(computeWeeklyStreak({ sessions: [], weeklyTarget: 3, now: wednesday })).toBe(0);
  });

  it("sesiones abandonadas no cuentan para el objetivo", () => {
    const sessions = [
      ...weekWith(week1, 2),
      {
        startedAt: new Date(Date.UTC(2026, 4, 7, 12)), // dentro de week1
        status: "finished",
        wasFullyCompleted: false,
      },
    ];
    // 2 reales + 1 abandonada: si la abandonada contara, daría 1.
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(0);
  });

  it("una sesión EN CURSO tampoco cuenta", () => {
    const sessions = [
      ...weekWith(week1, 2),
      { startedAt: new Date(Date.UTC(2026, 4, 7, 12)), status: "active", wasFullyCompleted: true },
    ];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 3, now: wednesday })).toBe(0);
  });

  it("objetivo 0 degrada al fallback de 1, no cuenta semanas vacías", () => {
    // Con un `>=0` crudo la racha contaría hacia atrás para siempre.
    const sessions = [...weekWith(week1, 1)];
    expect(computeWeeklyStreak({ sessions, weeklyTarget: 0, now: wednesday })).toBe(1);
  });

  it("el borde de semana es lunes ART, no el domingo", () => {
    // Domingo 2026-05-10 21:00 ART = 2026-05-11 00:00 UTC. En UTC ya es lunes y
    // caería en la semana en curso; en ART todavía es la semana anterior. Con
    // objetivo 1 y "hoy" el lunes 11, la sesión tiene que bucketear en week1.
    const domingoTardeArt = new Date(Date.UTC(2026, 4, 11, 0));
    const lunes = new Date(Date.UTC(2026, 4, 11, 15)); // 12:00 ART del lunes
    expect(
      computeWeeklyStreak({
        sessions: [finishedOn(domingoTardeArt)],
        weeklyTarget: 1,
        now: lunes,
      }),
    ).toBe(1);
  });
});

describe("weeklyStreakOf — currentWeekMet", () => {
  it("semana en curso cumplida → true", () => {
    const r = weeklyStreakOf({ sessions: weekWith(week0, 3), weeklyTarget: 3, now: wednesday });
    expect(r.currentWeekMet).toBe(true);
    expect(r.streak).toBe(1);
  });

  it("semana en curso a medias → false, aunque la racha sea > 0", () => {
    const r = weeklyStreakOf({
      sessions: [...weekWith(week0, 1), ...weekWith(week1, 3), ...weekWith(week2, 3)],
      weeklyTarget: 3,
      now: wednesday,
    });
    expect(r.streak).toBe(2);
    expect(r.currentWeekMet).toBe(false);
  });

  it("semana en curso vacía → false", () => {
    const r = weeklyStreakOf({ sessions: weekWith(week1, 3), weeklyTarget: 3, now: wednesday });
    expect(r.currentWeekMet).toBe(false);
  });

  it("devuelve exactamente {streak, currentWeekMet}, como Dart", () => {
    const r = weeklyStreakOf({ sessions: [], weeklyTarget: 3, now: wednesday });
    expect(Object.keys(r).sort()).toEqual(["currentWeekMet", "streak"]);
  });
});

describe("weeklyTargetFromRoutine", () => {
  const day = (n: number, slots = 1) => ({
    dayNumber: n,
    name: `Día ${n}`,
    slots: Array.from({ length: slots }, () => ({ exerciseId: "x" })),
  });

  it("sin rutina activa → fallback 1", () => {
    expect(weeklyTargetFromRoutine(null)).toBe(WEEKLY_STREAK_FALLBACK_TARGET);
    expect(weeklyTargetFromRoutine(undefined)).toBe(WEEKLY_STREAK_FALLBACK_TARGET);
  });

  it("cuenta los días del plan", () => {
    expect(weeklyTargetFromRoutine({ days: [day(1), day(2), day(3)] })).toBe(3);
  });

  it("los días sin ejercicios son descanso y NO suman al objetivo", () => {
    const plan = { days: [day(1), day(2, 0), day(3), day(4, 0)] };
    expect(weeklyTargetFromRoutine(plan)).toBe(2);
  });

  it("rutina de puros días vacíos → fallback 1", () => {
    expect(weeklyTargetFromRoutine({ days: [day(1, 0), day(2, 0)] })).toBe(
      WEEKLY_STREAK_FALLBACK_TARGET,
    );
  });

  it("rutina sin días → fallback 1", () => {
    expect(weeklyTargetFromRoutine({ days: [] })).toBe(WEEKLY_STREAK_FALLBACK_TARGET);
  });

  it("un doc sin `days`, o con basura, no tira: fallback 1", () => {
    expect(weeklyTargetFromRoutine({})).toBe(WEEKLY_STREAK_FALLBACK_TARGET);
    expect(weeklyTargetFromRoutine({ days: "no-es-una-lista" })).toBe(WEEKLY_STREAK_FALLBACK_TARGET);
    expect(weeklyTargetFromRoutine({ days: [null, { slots: "x" }, {}] })).toBe(
      WEEKLY_STREAK_FALLBACK_TARGET,
    );
  });
});

// ─── Lo que el port agrega ────────────────────────────────────────────────────

describe("weeklyStreakDetail", () => {
  it("currentWeekCount es lo que lleva la semana en curso, sin abandonadas", () => {
    const d = weeklyStreakDetail({
      sessions: [
        ...weekWith(week0, 2),
        { startedAt: new Date(Date.UTC(2026, 4, 12, 15)), status: "finished", wasFullyCompleted: false },
      ],
      weeklyTarget: 5,
      now: wednesday,
    });
    expect(d.currentWeekCount).toBe(2);
  });

  it("sin dataStart nunca queda truncada", () => {
    const d = weeklyStreakDetail({ sessions: weekWith(week1, 3), weeklyTarget: 3, now: wednesday });
    expect(d.truncated).toBe(false);
  });
});

describe("weeklyStreakFromStarts — el borde de los datos", () => {
  // El lunes (UTC 00:00) de cada `weekN` es domingo 21:00 ART; el instante real en
  // que ARRANCA esa semana ART es el lunes 03:00 UTC.
  const ART_MIDNIGHT_OFFSET_MS = 3 * 60 * 60 * 1000;

  // Tres semanas cumplidas con objetivo 2 → week1, week2, week3.
  const starts = [week1, week2, week3].flatMap((w) =>
    weekWith(w, 2).map((s) => s.startedAt.getTime()));

  it("si los datos cubren hasta ANTES del corte, la racha es exacta", () => {
    // Datos completos desde week4: week4 está vacía → corta y es exacto.
    const week4 = Date.UTC(2026, 3, 13, 3);
    const d = weeklyStreakFromStarts({
      countingStartsMs: starts,
      weeklyTarget: 2,
      now: wednesday,
      dataStart: new Date(week4),
    });
    expect(d.streak).toBe(3);
    expect(d.truncated).toBe(false);
  });

  it("si la corrida llega al primer dato incompleto, queda TRUNCADA", () => {
    // Datos completos recién desde week3: week3 cumple, y la siguiente (week4)
    // no se puede juzgar → la racha real puede ser mayor.
    const d = weeklyStreakFromStarts({
      countingStartsMs: starts,
      weeklyTarget: 2,
      now: wednesday,
      dataStart: new Date(week3.getTime() + ART_MIDNIGHT_OFFSET_MS),
    });
    expect(d.streak).toBe(3);
    expect(d.truncated).toBe(true);
  });

  it("una semana incompleta de DATOS no se confunde con una incumplida", () => {
    // Datos completos desde week2: week3 no se juzga, así que la racha es un
    // piso de 2 y se declara truncada, en vez de «cortar» ahí.
    const d = weeklyStreakFromStarts({
      countingStartsMs: starts,
      weeklyTarget: 2,
      now: wednesday,
      dataStart: new Date(week2.getTime() + ART_MIDNIGHT_OFFSET_MS),
    });
    expect(d.streak).toBe(2);
    expect(d.truncated).toBe(true);
  });
});

describe("calendario ART", () => {
  it("mondayOfWeekArt devuelve el lunes 00:00 del marco ART", () => {
    // Miércoles 2026-05-13 12:00 UTC → 09:00 ART → lunes 2026-05-11.
    const monday = mondayOfWeekArt(toArgentina(wednesday.getTime()));
    expect(new Date(monday).toISOString()).toBe("2026-05-11T00:00:00.000Z");
  });

  it("domingo 23:59 ART sigue en su semana; lunes 00:00 ART arranca la siguiente", () => {
    const domingo = Date.UTC(2026, 4, 11, 2, 59); // 2026-05-10 23:59 ART
    const lunes = Date.UTC(2026, 4, 11, 3, 0); //    2026-05-11 00:00 ART
    expect(new Date(mondayOfWeekArt(toArgentina(domingo))).toISOString()).toBe(
      "2026-05-04T00:00:00.000Z",
    );
    expect(new Date(mondayOfWeekArt(toArgentina(lunes))).toISOString()).toBe(
      "2026-05-11T00:00:00.000Z",
    );
  });

  it("weekStartInstantArt es el lunes 03:00 UTC (00:00 ART)", () => {
    expect(new Date(weekStartInstantArt(wednesday.getTime())).toISOString()).toBe(
      "2026-05-11T03:00:00.000Z",
    );
  });

  it("daysLeftInWeekArt: lunes=7 … domingo=1", () => {
    // 2026-05-11 es lunes. Mediodía UTC = 09:00 ART del mismo día.
    const dias = [7, 6, 5, 4, 3, 2, 1];
    dias.forEach((esperado, i) => {
      expect(daysLeftInWeekArt(Date.UTC(2026, 4, 11 + i, 12))).toBe(esperado);
    });
  });

  it("daysLeftInWeekArt usa el día ART, no el UTC", () => {
    // Domingo 2026-05-10 22:00 ART = lunes 2026-05-11 01:00 UTC. Es domingo.
    expect(daysLeftInWeekArt(Date.UTC(2026, 4, 11, 1))).toBe(1);
  });

  it("artDayNumber coincide con artDateKey (Intl) a través de varias medianoches ART", () => {
    // Barrido cada 30 minutos durante 10 días que cruzan un fin de mes y un 29/2.
    // La clave `YYYY-MM-DD` es una fecha; su número de día es ms-desde-epoch / 1 día.
    const dayOfKey = (ms: number) => Date.parse(`${artDateKey(new Date(ms))}T00:00:00Z`) / 86400000;
    for (const inicio of [Date.UTC(2028, 1, 25), Date.UTC(2026, 11, 28)]) {
      for (let t = inicio; t < inicio + 10 * 86400000; t += 30 * 60 * 1000) {
        expect(artDayNumber(t)).toBe(dayOfKey(t));
      }
    }
  });
});
