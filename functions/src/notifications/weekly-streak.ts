/**
 * weekly-streak.ts — port a TypeScript de la racha semanal del atleta.
 *
 * Es PURO a propósito: sin Firestore, sin reloj implícito, sin logger. Todo lo
 * que necesita llega por parámetro, así que se testea sin mocks y se puede
 * contrastar contra los fixtures compartidos con Dart y Swift.
 *
 * ─── Fuentes de verdad (Dart) ───────────────────────────────────────────────
 *
 *   · `lib/core/utils/weekly_streak_calculator.dart`
 *       → `weeklyStreakOf`, `computeWeeklyStreak`, `weeklyTargetFromRoutine`.
 *   · `lib/core/utils/argentina_time.dart`
 *       → `toArgentina`, `mondayOfWeekArt`. Semana lunes-domingo en UTC-3 FIJO,
 *         sin DST (Argentina no lo tiene desde 2009).
 *   · `lib/features/workout/domain/session.dart`
 *       → `sessionCountsAsWorkout` (`status == 'finished' && wasFullyCompleted`).
 *   · `lib/features/workout/domain/routine_selection.dart`
 *       → `resolveActiveRoutineId` (tres niveles).
 *
 * ─── Por qué hay un port y no una consulta ─────────────────────────────────
 *
 * La racha NO está denormalizada en ningún documento que sirva para esto
 * (`rachaSemanas` sólo se sella al terminar una sesión y decae con una semana
 * de gracia: no dice "la semana en curso va 1 de 3"). Hay que recalcularla
 * desde las sesiones, igual que hace el cliente. Y si el servidor la calcula
 * con una regla propia, el push dice "tu racha de 4 semanas" mientras la app
 * dice 3: exactamente el #552 otra vez.
 *
 * ─── El seguro contra la divergencia ────────────────────────────────────────
 *
 * Dos de las cuatro reglas están bajo contrato compartido y los tests de TS
 * corren los MISMOS JSON que Dart y Swift:
 *
 *   · `conformance/session_counting.json`  → `sessionCountsAsWorkout`
 *   · `conformance/routine_selection.json` → `resolveActiveRoutineId`
 *
 * La aritmética de semanas (`weeklyStreakOf`, `weeklyTargetFromRoutine`) NO
 * tiene fixture compartido —tampoco el reloj la implementa—; sus casos son los
 * de `test/core/utils/weekly_streak_calculator_test.dart` portados uno a uno.
 * Si se agrega un fixture `weekly_streak.json`, este es el tercer consumidor.
 *
 * ─── Desvíos respecto de Dart, y por qué ───────────────────────────────────
 *
 *   1. `now` es OBLIGATORIO. Dart cae en `AppClock.now()` para poder congelar
 *      el reloj en un test de widget; en el servidor el reloj ya se inyecta en
 *      cada handler (`notifyXxxHandler(app, now)`), no hay nada que congelar.
 *   2. `weeklyStreakDetail` devuelve de más: cuántas sesiones lleva la semana
 *      en curso (hace falta para "te faltan N") y si la corrida de semanas
 *      llegó al borde de los datos (`truncated`). `weeklyStreakOf` devuelve
 *      exactamente lo mismo que el de Dart.
 *   3. Los instantes son `number` (ms) y las semanas se identifican por el
 *      milisegundo del lunes en el MARCO ART (el mismo truco que Dart: un
 *      `DateTime.utc` cuyos campos de calendario leen como hora argentina).
 *
 * Los archivos de esta carpeta son planos y no hay un `lib/`: `functions/.gitignore`
 * ignora `lib/` a CUALQUIER profundidad (es la salida de `tsc`), así que un
 * `notifications/lib/weekly-streak.ts` no entraría al repo.
 */

/** UTC-3 fijo. Igual que `argentinaUtcOffset` en `argentina_time.dart`. */
export const ART_OFFSET_MS = 3 * 60 * 60 * 1000;
export const DAY_MS = 24 * 60 * 60 * 1000;
export const WEEK_MS = 7 * DAY_MS;

/**
 * Objetivo semanal cuando el atleta no tiene rutina activa, o la que tiene no
 * define ni un día con ejercicios. Uno, no cero: con cero el `>=` daría siempre
 * verdadero y la racha contaría semanas en las que no entrenó nunca.
 */
export const WEEKLY_STREAK_FALLBACK_TARGET = 1;

// ─── Qué cuenta como entrenamiento ────────────────────────────────────────────

/**
 * Si una sesión cuenta como entrenamiento HECHO, a partir de sus valores de
 * wire. Contrato compartido: `conformance/session_counting.json`.
 *
 * La condición es IGUALDAD contra `"finished"`, nunca desigualdad contra
 * `"active"`: si mañana aparece un estado nuevo, no puede empezar a contar solo.
 * `wasFullyCompleted` ausente o nulo es `false` (el `@Default(false)` de Dart).
 * Abandonar guarda `status=finished` con `wasFullyCompleted=false`, así que
 * `status` solo no alcanza.
 */
export function sessionCountsAsWorkout(
  status: unknown,
  wasFullyCompleted: unknown,
): boolean {
  return status === "finished" && wasFullyCompleted === true;
}

// ─── Objetivo semanal ─────────────────────────────────────────────────────────

/**
 * Cuántas sesiones por semana exige [routine] para que la semana cuente: la
 * cantidad de días del plan CON al menos un ejercicio. Un día con `slots` vacío
 * es un día de descanso; contarlo inflaría el objetivo y le mataría la racha a
 * alguien que cumplió su plan completo.
 *
 * Sin rutina, o con una que es toda días vacíos, cae en
 * {@link WEEKLY_STREAK_FALLBACK_TARGET}.
 */
export function weeklyTargetFromRoutine(
  routine: { days?: unknown } | null | undefined,
): number {
  if (routine == null) return WEEKLY_STREAK_FALLBACK_TARGET;
  const days: unknown[] = Array.isArray(routine.days) ? routine.days : [];
  const trainingDays = days.filter((day) => {
    const slots = (day as { slots?: unknown } | null | undefined)?.slots;
    return Array.isArray(slots) && slots.length > 0;
  }).length;
  return trainingDays > 0 ? trainingDays : WEEKLY_STREAK_FALLBACK_TARGET;
}

// ─── Qué rutina es la activa ──────────────────────────────────────────────────

export interface ActiveRoutineInput {
  /** Marcador explícito del perfil. `null`, ausente o `""` = sin marcador. */
  activeRoutineId: string | null | undefined;
  /** Asignadas por un PF, más nueva primero. */
  assignedIds: readonly string[];
  /** Creadas por el atleta, más nueva primero. */
  selfCreatedIds: readonly string[];
  /**
   * Plantillas del sistema que el atleta puede estar SIGUIENDO. Sólo participan
   * del tier 0: una plantilla del catálogo nunca se auto-activa.
   */
  catalogIds?: readonly string[];
}

/**
 * Elige QUÉ rutina es la activa del atleta. Contrato compartido:
 * `conformance/routine_selection.json`.
 *
 *   0. Marcador explícito, buscado en las tres listas. Un id obsoleto cae al resto.
 *   1. Plan asignado por un PF (el más nuevo: la lista llega ordenada).
 *   2. Una sola auto-creada.
 *   3./4. Varias auto-creadas sin marcador válido, o ninguna: `null`.
 */
export function resolveActiveRoutineId({
  activeRoutineId,
  assignedIds,
  selfCreatedIds,
  catalogIds = [],
}: ActiveRoutineInput): string | null {
  // Tier 0 — marcador explícito.
  if (activeRoutineId != null && activeRoutineId !== "") {
    if (assignedIds.includes(activeRoutineId)) return activeRoutineId;
    if (selfCreatedIds.includes(activeRoutineId)) return activeRoutineId;
    if (catalogIds.includes(activeRoutineId)) return activeRoutineId;
    // Id obsoleto: sigue la cadena en vez de devolver null.
  }

  // Tier 1 — plan de PF.
  if (assignedIds.length > 0) return assignedIds[0];

  // Tier 2 — única auto-creada.
  if (selfCreatedIds.length === 1) return selfCreatedIds[0];

  // Tiers 3 y 4 — varias auto-creadas sin marcador, o ninguna.
  return null;
}

// ─── Calendario ART ───────────────────────────────────────────────────────────

/**
 * Desplaza un instante real al marco ART: el resultado, leído con los getters
 * UTC, da la hora de pared argentina. Espejo de `toArgentina`.
 */
export function toArgentina(utcMs: number): number {
  return utcMs - ART_OFFSET_MS;
}

/**
 * Lunes 00:00 de la semana que contiene [artFrameMs], en el MARCO ART. Espejo
 * de `mondayOfWeekArt`: recibe un valor YA desplazado con {@link toArgentina}.
 *
 * Va por el constructor de calendario y no restando `n * DAY_MS` para mantener
 * el borde clavado a medianoche, igual que Dart.
 */
export function mondayOfWeekArt(artFrameMs: number): number {
  const d = new Date(artFrameMs);
  // getUTCDay: domingo=0 … sábado=6. Dart: lunes=1 … domingo=7, menos lunes.
  const daysFromMonday = (d.getUTCDay() + 6) % 7;
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - daysFromMonday);
}

/** Lunes de la semana anterior a [weekStartFrameMs]. Espejo de `_previousWeek`. */
export function previousWeekArt(weekStartFrameMs: number): number {
  const d = new Date(weekStartFrameMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - 7);
}

/**
 * El INSTANTE REAL (ms) en que arranca la semana ART que contiene [instantMs]:
 * lunes 00:00 ART = lunes 03:00 UTC. Es la forma de hablar con Firestore, que
 * guarda instantes y no marcos.
 */
export function weekStartInstantArt(instantMs: number): number {
  return mondayOfWeekArt(toArgentina(instantMs)) + ART_OFFSET_MS;
}

/**
 * Número de día calendario ART del instante (días desde 1970-01-01 en hora de
 * pared argentina). Dos instantes con el mismo número cayeron el mismo día ART;
 * la resta es "cuántos días calendario pasaron".
 *
 * Es aritmética de offset fijo, sin `Intl`. Coincide con `artDateKey` (que sí usa
 * `Intl`) en todo el rango que importa: lo fija un test que barre varias
 * medianoches ART.
 */
export function artDayNumber(instantMs: number): number {
  return Math.floor(toArgentina(instantMs) / DAY_MS);
}

/**
 * Cuántos días le quedan a la semana ART contando HOY: lunes=7 … domingo=1.
 */
export function daysLeftInWeekArt(nowMs: number): number {
  const daysFromMonday = (new Date(toArgentina(nowMs)).getUTCDay() + 6) % 7;
  return 7 - daysFromMonday;
}

// ─── La racha ─────────────────────────────────────────────────────────────────

export interface WeeklyStreakDetail {
  /** Racha semanal, igual que `weeklyStreakOf(...).streak`. */
  streak: number;
  /** Si la semana EN CURSO ya cumplió el objetivo. */
  currentWeekMet: boolean;
  /** Sesiones que cuentan en la semana en curso (para "te faltan N"). */
  currentWeekCount: number;
  /**
   * `true` si la corrida de semanas cumplidas llegó al borde de los datos
   * (`dataStart`) sin encontrar un corte: la racha REAL puede ser mayor que
   * `streak`. Con `false`, `streak` es exacto.
   */
  truncated: boolean;
}

export interface WeeklyStreakFromStartsInput {
  /**
   * Instantes (ms) de inicio de sesiones que YA cuentan como entrenamiento.
   * Quien llama filtró con {@link sessionCountsAsWorkout}.
   */
  countingStartsMs: readonly number[];
  weeklyTarget: number;
  now: Date;
  /**
   * Desde cuándo (instante real) los datos están COMPLETOS. Una semana que
   * arranca antes de este instante no se puede juzgar —que figure con 0
   * sesiones puede ser sólo que no se cargó— y la corrida se corta marcando
   * `truncated`. Ausente = se tiene todo el historial.
   */
  dataStart?: Date;
}

/**
 * El cálculo de la racha sobre instantes ya filtrados. Es el cuerpo de
 * `weeklyStreakOf` de Dart.
 *
 * LA SEMANA EN CURSO NUNCA ROMPE LA RACHA: si ya cumplió suma; si todavía no,
 * no suma pero tampoco corta, y se sigue contando desde la anterior. Sin esto la
 * racha de todo el mundo se caería a 0 cada lunes a la medianoche.
 *
 * LIMITACIÓN CONOCIDA (idéntica a la de Dart): `weeklyTarget` es el de la
 * rutina activa de HOY, aplicado hacia atrás a todas las semanas.
 */
export function weeklyStreakFromStarts({
  countingStartsMs,
  weeklyTarget,
  now,
  dataStart,
}: WeeklyStreakFromStartsInput): WeeklyStreakDetail {
  // Un objetivo de 0 haría que `>=` diera verdadero para toda semana vacía.
  const target = weeklyTarget > 0 ? weeklyTarget : WEEKLY_STREAK_FALLBACK_TARGET;

  const currentWeek = mondayOfWeekArt(toArgentina(now.getTime()));

  const countByWeek = new Map<number, number>();
  for (const startMs of countingStartsMs) {
    const weekStart = mondayOfWeekArt(toArgentina(startMs));
    countByWeek.set(weekStart, (countByWeek.get(weekStart) ?? 0) + 1);
  }

  const met = (weekStart: number): boolean => (countByWeek.get(weekStart) ?? 0) >= target;
  // El instante real en que arranca esa semana, contra el borde de los datos.
  const dataStartMs = dataStart?.getTime();
  const known = (weekStart: number): boolean =>
    dataStartMs === undefined || weekStart + ART_OFFSET_MS >= dataStartMs;

  let streak = 0;

  // La semana en curso suma sólo si ya cumplió; si no, se saltea sin cortar.
  const currentWeekMet = met(currentWeek);
  if (currentWeekMet) streak++;

  let cursor = previousWeekArt(currentWeek);
  while (known(cursor) && met(cursor)) {
    streak++;
    cursor = previousWeekArt(cursor);
  }

  return {
    streak,
    currentWeekMet,
    currentWeekCount: countByWeek.get(currentWeek) ?? 0,
    // Salió del bucle por falta de datos, no por una semana incumplida.
    truncated: !known(cursor),
  };
}

/** Lo mínimo que se le pide a una sesión para la racha. */
export interface WeeklySessionLike {
  startedAt: Date;
  /** Valor de wire de `status`. */
  status?: unknown;
  /** Valor de wire de `wasFullyCompleted`. */
  wasFullyCompleted?: unknown;
}

export interface WeeklyStreakInput {
  sessions: readonly WeeklySessionLike[];
  weeklyTarget: number;
  now: Date;
  dataStart?: Date;
}

/**
 * Como {@link weeklyStreakFromStarts}, pero filtrando con
 * {@link sessionCountsAsWorkout}. Es la forma fiel a `weeklyStreakOf` de Dart.
 */
export function weeklyStreakDetail({
  sessions,
  weeklyTarget,
  now,
  dataStart,
}: WeeklyStreakInput): WeeklyStreakDetail {
  return weeklyStreakFromStarts({
    countingStartsMs: sessions
      .filter((s) => sessionCountsAsWorkout(s.status, s.wasFullyCompleted))
      .map((s) => s.startedAt.getTime()),
    weeklyTarget,
    now,
    dataStart,
  });
}

/**
 * La racha semanal + si la semana EN CURSO ya cumplió el objetivo. Mismo
 * contrato que `weeklyStreakOf` de Dart.
 */
export function weeklyStreakOf(
  input: WeeklyStreakInput,
): { streak: number; currentWeekMet: boolean } {
  const { streak, currentWeekMet } = weeklyStreakDetail(input);
  return { streak, currentWeekMet };
}

/** Sólo el número. Mismo contrato que `computeWeeklyStreak` de Dart. */
export function computeWeeklyStreak(input: WeeklyStreakInput): number {
  return weeklyStreakOf(input).streak;
}
