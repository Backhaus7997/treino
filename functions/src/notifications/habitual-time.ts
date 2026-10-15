/**
 * habitual-time.ts — a qué hora del día suele entrenar un atleta, y de ahí a
 * qué hora le toca cada recordatorio.
 *
 * Es PURO a propósito, igual que `weekly-streak.ts`: sin Firestore, sin reloj
 * implícito, sin logger. Le entran instantes (ms) y devuelve minutos del día
 * ART (0..1439), así que se testea sin mocks.
 *
 * ─── El horario habitual ───────────────────────────────────────────────────
 *
 * Se aprende de los inicios de las sesiones que CUENTAN
 * (`sessionCountsAsWorkout`), y NO se guarda en ningún lado: se recalcula en
 * cada corrida del planificador a partir de lo que ya tiene en memoria.
 *
 *   1. Muestra: las {@link HABITUAL_SAMPLE_SIZE} sesiones más recientes. Por eso
 *      el horario se adapta solo cuando el atleta cambia de hábito: las
 *      sesiones del hábito viejo van saliendo de la muestra a medida que entran
 *      las nuevas. Con un historial más largo, las viejas no pesan.
 *   2. Cada inicio se pasa a minuto del día ART (UTC-3 fijo, como el resto del
 *      módulo; ver `toArgentina`).
 *   3. Se busca la ventana CIRCULAR de {@link HABITUAL_WINDOW_MINUTES} minutos
 *      con más inicios. Circular quiere decir que el día se cierra sobre sí
 *      mismo: 23:50 y 00:10 caen en la misma ventana. Sin eso, quien entrena
 *      pasada la medianoche tendría el patrón partido en dos mitades que nunca
 *      llegan al mínimo.
 *   4. Si esa ventana tiene al menos {@link HABITUAL_MIN_STARTS} inicios, el
 *      horario habitual es la MEDIANA de los inicios de la ventana, desenrollada
 *      respecto del comienzo de la ventana y normalizada a 0..1439. La mediana y
 *      no el promedio: un día que entrenó 40 minutos fuera de lo normal no lo
 *      corre. Con una cantidad par de inicios se promedian los dos del medio y
 *      se redondea PARA ABAJO (17:40, 18:05, 18:12 y 18:15 dan 18:08).
 *   5. Si no llega al mínimo no hay patrón claro y se devuelve `null`.
 *
 * La ventana es CERRADA: dos inicios separados por exactamente 60 minutos caben
 * en la misma. Con 61 no.
 *
 * ─── Desempate (determinista) ──────────────────────────────────────────────
 *
 * Dos ventanas con la misma cantidad de inicios son un caso real: un atleta que
 * pasó de entrenar a la mañana a entrenar a la noche tiene, a mitad del cambio,
 * seis y seis. El orden en que llegan las sesiones no puede decidir, así que se
 * desempata por valores, en este orden:
 *
 *   1. Gana la ventana que contiene la sesión MÁS RECIENTE: es el hábito actual.
 *   2. Gana la más angosta (el grupo más apretado es el patrón más fuerte).
 *   3. Gana la que arranca más temprano en el día.
 *
 * ─── Del horario habitual a la hora del recordatorio ───────────────────────
 *
 *   · Racha en riesgo y «hoy toca entrenar» (`training-due`): habitual +
 *     {@link STREAK_REMINDER_OFFSET_MINUTES} (llega una hora DESPUÉS de cuando
 *     suele entrenar: si no se colgó, ya lo hizo y el despachante no manda
 *     nada). Sin patrón: 18:00. Los dos usan la misma función,
 *     {@link streakSendMinute}.
 *   · Volver a entrenar: habitual + {@link COMEBACK_REMINDER_OFFSET_MINUTES} (a
 *     la hora a la que suele entrenar). Sin patrón: 09:00.
 *   · Los dos quedan acotados a [{@link REMINDER_MIN_MINUTE},
 *     {@link REMINDER_MAX_MINUTE}] = [08:00, 22:30]: ningún push de este módulo
 *     suena de madrugada ni de noche cerrada. El piso es 08:00 y no antes
 *     porque el planificador corre a las 06:00 y necesita margen para escribir
 *     los planes de todos antes de que el primero venza.
 *
 * ⚠️  El acotado puede dejar el recordatorio ANTES del horario habitual (quien
 * entrena a las 23:30 recibe la racha a las 22:30). Es a propósito: es preferible
 * a un push pasada la hora de dormir.
 */

import { ART_OFFSET_MS, DAY_MS, toArgentina } from "./weekly-streak";

/** Cuántas sesiones, las más recientes, forman la muestra del horario habitual. */
export const HABITUAL_SAMPLE_SIZE = 12;

/** Inicios mínimos que tiene que juntar la mejor ventana para haber patrón. */
export const HABITUAL_MIN_STARTS = 4;

/**
 * Ancho, en minutos, de la ventana circular que agrupa los inicios. NO es el
 * offset del aviso: son dos cosas distintas que hoy valen lo mismo por azar.
 */
export const HABITUAL_WINDOW_MINUTES = 60;

/** Minutos DESPUÉS del horario habitual a los que sale el aviso de racha. */
export const STREAK_REMINDER_OFFSET_MINUTES = 60;

/** Minutos después del horario habitual a los que sale el "volvé a entrenar". */
export const COMEBACK_REMINDER_OFFSET_MINUTES = 0;

/** Piso de la hora de cualquier recordatorio: 08:00 ART. */
export const REMINDER_MIN_MINUTE = 480;

/** Techo de la hora de cualquier recordatorio: 22:30 ART. */
export const REMINDER_MAX_MINUTE = 1350;

/** Hora del aviso de racha cuando no hay patrón: 18:00 ART. */
export const STREAK_REMINDER_FALLBACK_MINUTE = 1080;

/** Hora del "volvé a entrenar" cuando no hay patrón: 09:00 ART. */
export const COMEBACK_REMINDER_FALLBACK_MINUTE = 540;

const MINUTE_MS = 60_000;
const MINUTES_PER_DAY = 1440;

// ─── Reloj ART ────────────────────────────────────────────────────────────────

/** Minuto del día ART (0..1439) del instante. 00:00 ART = 0, 23:59 ART = 1439. */
export function minuteOfDayArt(instantMs: number): number {
  const minutes = Math.floor(toArgentina(instantMs) / MINUTE_MS);
  return ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
}

/**
 * El INSTANTE real (ms) en que arranca el día ART que contiene [instantMs]:
 * 00:00 ART = 03:00 UTC. Es la forma de hablar con Firestore ("sesiones desde
 * hoy"), que guarda instantes y no marcos.
 */
export function startOfDayInstantArt(instantMs: number): number {
  return Math.floor(toArgentina(instantMs) / DAY_MS) * DAY_MS + ART_OFFSET_MS;
}

// ─── Horario habitual ─────────────────────────────────────────────────────────

interface Cluster {
  /** Minuto del día donde arranca la ventana (siempre es un inicio de la muestra). */
  anchor: number;
  /** Distancia de cada inicio contenido al ancla, en minutos (0..ventana). */
  offsets: number[];
  /** Posición, en la muestra de más nueva a más vieja, del inicio más reciente. */
  newestIndex: number;
  /** Mayor distancia al ancla: qué tan apretado es el grupo. */
  spread: number;
}

/** ¿`a` es mejor ventana que `b`? Ver «Desempate» en la cabecera. */
function isBetter(a: Cluster, b: Cluster): boolean {
  if (a.offsets.length !== b.offsets.length) return a.offsets.length > b.offsets.length;
  if (a.newestIndex !== b.newestIndex) return a.newestIndex < b.newestIndex;
  if (a.spread !== b.spread) return a.spread < b.spread;
  return a.anchor < b.anchor;
}

/**
 * El horario habitual de entrenamiento, como minuto del día ART (0..1439), o
 * `null` si no hay un patrón claro. Ver la cabecera para el algoritmo completo.
 *
 * @param startsMs Inicios (ms) de las sesiones que CUENTAN. Quien llama filtró
 *   con `sessionCountsAsWorkout`. Cualquier orden; no se modifica.
 */
export function habitualStartMinute(startsMs: readonly number[]): number | null {
  // De más nueva a más vieja; el índice 0 es la sesión más reciente.
  const minutes = startsMs
    .filter((ms) => Number.isFinite(ms))
    .sort((a, b) => b - a)
    .slice(0, HABITUAL_SAMPLE_SIZE)
    .map(minuteOfDayArt);

  let best: Cluster | null = null;
  // Basta con probar ventanas que arrancan en un inicio de la muestra: cualquier
  // ventana óptima se puede deslizar hasta que su borde izquierdo toque uno.
  for (const anchor of new Set(minutes)) {
    const offsets: number[] = [];
    let newestIndex = Number.POSITIVE_INFINITY;
    minutes.forEach((minute, index) => {
      // La resta módulo un día es lo que hace circular a la ventana.
      const offset = (minute - anchor + MINUTES_PER_DAY) % MINUTES_PER_DAY;
      if (offset > HABITUAL_WINDOW_MINUTES) return;
      offsets.push(offset);
      if (index < newestIndex) newestIndex = index;
    });
    const cluster: Cluster = { anchor, offsets, newestIndex, spread: Math.max(...offsets) };
    if (best === null || isBetter(cluster, best)) best = cluster;
  }

  if (best === null || best.offsets.length < HABITUAL_MIN_STARTS) return null;

  // Mediana de los inicios "desenrollados" respecto del comienzo de la ventana.
  const sorted = [...best.offsets].sort((a, b) => a - b);
  const lower = sorted[Math.floor((sorted.length - 1) / 2)];
  const upper = sorted[Math.floor(sorted.length / 2)];
  const medianOffset = Math.floor((lower + upper) / 2);
  return (best.anchor + medianOffset) % MINUTES_PER_DAY;
}

// ─── Hora del recordatorio ────────────────────────────────────────────────────

/** Acota un minuto del día a [{@link REMINDER_MIN_MINUTE}, {@link REMINDER_MAX_MINUTE}]. */
export function clampReminderMinute(minute: number): number {
  return Math.min(REMINDER_MAX_MINUTE, Math.max(REMINDER_MIN_MINUTE, minute));
}

/** Minuto del día ART al que sale el aviso de racha en riesgo y el de «hoy toca entrenar». */
export function streakSendMinute(habitualMinute: number | null): number {
  if (habitualMinute === null) return STREAK_REMINDER_FALLBACK_MINUTE;
  return clampReminderMinute(habitualMinute + STREAK_REMINDER_OFFSET_MINUTES);
}

/** Minuto del día ART al que sale el "volvé a entrenar". */
export function comebackSendMinute(habitualMinute: number | null): number {
  if (habitualMinute === null) return COMEBACK_REMINDER_FALLBACK_MINUTE;
  return clampReminderMinute(habitualMinute + COMEBACK_REMINDER_OFFSET_MINUTES);
}
