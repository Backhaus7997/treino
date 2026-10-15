/**
 * notifyDailyReminders — el push diario de recordatorio para el atleta.
 *
 * Corre todos los días a las 10:00 ART y manda COMO MÁXIMO UN push por atleta
 * por día. Todo se calcula en el servidor: el cliente no participa, así que un
 * teléfono apagado, una app sin abrir o una versión vieja no cambian nada.
 *
 * ─── Los dos recordatorios, en orden de prioridad ──────────────────────────
 *
 * 1. `streak-at-risk` — "Hoy o se corta 🔥". El atleta tiene una racha semanal
 *    de 1 semana o más (semanas cumplidas consecutivas ANTERIORES a la actual),
 *    la semana en curso no cumplió, y le faltan exactamente tantos
 *    entrenamientos como días le quedan contando hoy (lunes=7 … domingo=1):
 *    si hoy no entrena, matemáticamente ya no llega. Se excluye a quien ya
 *    completó una sesión hoy.
 *
 * 2. `comeback-reminder` — "Te extrañamos en el gym 💪". Su última sesión que
 *    cuenta tiene 4 días ART calendario o más, y no se le mandó este tipo en los
 *    últimos 7 días (se reintenta recién al día 7, no al 6).
 *
 * Si califica para los dos, gana el 1 y el 2 NO se consume: no se escribe
 * `lastComebackReminderDate`, así que el cooldown de 7 días no corre.
 *
 * ─── Quién NO recibe el "volvé a entrenar", A PROPÓSITO ────────────────────
 *
 * Sólo se consideran atletas con alguna sesión que cuenta dentro de la VENTANA
 * de la query (las últimas 8 semanas + la actual). Quien se fue hace más tiempo
 * no aparece en el escaneo y no recibe nada. No es un hueco: es el producto.
 * No perseguimos a los churneados — un push semanal a alguien que dejó de usar
 * la app hace tres meses es la forma más rápida de que desinstale o apague las
 * notificaciones de TODO. El borde es entonces móvil: un atleta que sigue
 * inactivo recibe a lo sumo un "volvé" por semana, hasta que su última sesión
 * sale de la ventana.
 *
 * ─── La racha: port, no reglas propias ─────────────────────────────────────
 *
 * El cálculo vive en `weekly-streak.ts`, un port de la lógica de Dart contrastado
 * contra los fixtures compartidos (`conformance/session_counting.json`,
 * `conformance/routine_selection.json`). Si el servidor tuviera su propia regla,
 * el push diría "tu racha de 4 semanas" y la app 3. El objetivo semanal sale de
 * la rutina ACTIVA del atleta, que se resuelve con la misma cadena de tres
 * niveles que usa el Home.
 *
 * ─── Costo de lecturas ─────────────────────────────────────────────────────
 *
 * 1. UNA collectionGroup query paginada sobre `sessions` (ventana de 9 semanas),
 *    filtrada y agrupada en memoria por uid. Cuesta una lectura por sesión de la
 *    ventana, todos los días: crece con la base de usuarios y con la frecuencia
 *    de entrenamiento, no con cuántos reciben push. Si algún día pesa, el
 *    remedio es denormalizar `lastSessionAt` en `users/{uid}`, no achicar la
 *    ventana.
 * 2. Un atleta pasa a ser CANDIDATO sólo si por las sesiones ya cargadas puede
 *    llegar a calificar (ver `summarizeActivity`). El resto no cuesta una lectura
 *    más. Para los candidatos: el doc del usuario.
 * 3. Las lecturas de RUTINAS (2 queries, y 1 doc más si el marcador apunta al
 *    catálogo) se hacen SÓLO para el candidato a racha en riesgo que ya pasó los
 *    filtros baratos (es atleta, no apagó el push, no se le mandó hoy).
 * 4. Si la racha llega al borde de la ventana, se completa con una query extra
 *    sobre las sesiones de ESE usuario, para que el "racha de M semanas" del
 *    texto sea exacto y no un piso.
 *
 * ⚠️  ÍNDICE: la collectionGroup query exige el single-field index de scope
 * COLLECTION_GROUP sobre `sessions.startedAt`, que ya existe como `fieldOverrides`
 * en `firestore.indexes.json` (lo agregó `notifyMonthlyReport`; el porqué largo
 * está en la cabecera de `notify-monthly-report.ts`). NO se agrega otro override:
 * un fieldOverride REEMPLAZA la configuración del campo en vez de sumarse, y
 * declarar uno nuevo le borraría a `startedAt` los índices que ya sostienen
 * `SessionRepository.listByUid`, los contadores del finish y `ranking-aggregate`.
 * Las queries de rutinas usan los tres compuestos que el cliente ya declara.
 *
 * ─── Idempotencia ──────────────────────────────────────────────────────────
 *
 * `users/{uid}.lastDailyReminderDate` (YYYY-MM-DD ART) guarda el día del último
 * push; si ya vale hoy, el atleta se saltea. `lastComebackReminderDate` guarda el
 * último "volvé a entrenar" para el cooldown. Mismo patrón que `notifyMonthlyReport`:
 * el día se RESERVA en una transacción ANTES de despachar —dos corridas solapadas
 * no pueden mandar las dos— y se SUELTA, restaurando los valores previos, si el
 * envío falla, para que el reintento no se lo trague.
 *
 * ─── Opt-out: ANTES de reservar, y no sólo en sendFcm ──────────────────────
 *
 * `notificationPrefs.recordatorios_entrenamiento.push === false` saltea al
 * usuario antes de reservar y antes de llamar a `sendFcm`. No es redundante con
 * el `prefKey` que se le pasa igual: `sendFcm` con una preferencia apagada frena
 * el banner del sistema pero SÍ escribe la entrada de `users/{uid}/notifications`
 * (el historial in-app es otro canal). Sin este corte, quien apagó los
 * recordatorios se encontraría una fila nueva por día en su bandeja. Una
 * preferencia ausente cuenta como encendida.
 *
 * ─── Deep link ─────────────────────────────────────────────────────────────
 *
 * Los dos tipos aterrizan en `/home`: la pestaña Inicio del atleta, que es donde
 * vive `EmpezarEntrenamientoCard` ("EMPEZAR ENTRENAMIENTO", con el día de hoy ya
 * resuelto y un toque a la sesión). `/workout` también es válido, pero deja al
 * atleta frente a la lista de rutinas a elegir, un paso más lejos de entrenar.
 *
 * ─── Reglas de Firestore ───────────────────────────────────────────────────
 *
 * Los dos marcadores los escribe este backend con el Admin SDK, pero
 * `firestore.rules` NO los pinea: el dueño puede actualizar cualquier campo no
 * protegido de su propio `users/{uid}`. No importa: el único perjudicado por
 * pisarlos es el propio dueño. Con `lastDailyReminderDate` futuro se silencia a
 * sí mismo; borrándolo, o borrando `lastComebackReminderDate`, se saltea el
 * cooldown, pero igual recibe a lo sumo UN push por corrida del scheduler. Y
 * apagar los recordatorios ya tiene su interruptor oficial en
 * `notificationPrefs`. Nadie puede tocar el doc de OTRO, y `role` SÍ está
 * pineado (inmutable), así que el filtro "sólo atletas" no se puede falsear.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  FieldValue,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { Messaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { artDateKey } from "../mail/format";
import { sendFcm } from "./send-fcm";
import {
  DAY_MS,
  WEEK_MS,
  artDayNumber,
  daysLeftInWeekArt,
  mondayOfWeekArt,
  previousWeekArt,
  resolveActiveRoutineId,
  sessionCountsAsWorkout,
  toArgentina,
  weekStartInstantArt,
  weeklyStreakFromStarts,
  weeklyTargetFromRoutine,
} from "./weekly-streak";

/**
 * La clave de `users/{uid}.notificationPrefs` que apaga estos recordatorios.
 *
 * Es el MISMO literal que `kPrefRecordatoriosEntrenamiento` en
 * `lib/features/profile/domain/notification_pref_keys.dart`; el test de deriva
 * `notification_pref_keys_drift_test.dart` lee este archivo y los compara. Tiene
 * que seguir siendo un literal simple en una sola línea.
 */
export const DAILY_REMINDERS_PREF_KEY = "recordatorios_entrenamiento";

/** Adónde llevan los dos tipos de push. Ver «Deep link» en la cabecera. */
export const DAILY_REMINDER_DEEP_LINK = "/home";

/** Cuántos días calendario ART sin entrenar disparan el "volvé a entrenar". */
export const COMEBACK_MIN_DAYS = 4;

/** Días que tienen que pasar desde el último "volvé a entrenar" para otro. */
export const COMEBACK_COOLDOWN_DAYS = 7;

/** Semanas COMPLETAS anteriores a la actual que cubre la query de sesiones. */
export const STREAK_WINDOW_WEEKS = 8;

const PAGE_SIZE = 500;

/**
 * Tope de páginas de la query de extensión por usuario. Es un cinturón: 20
 * páginas son 10.000 sesiones, que ningún atleta junta. Sin tope, un dato raro
 * (una racha "infinita" por un objetivo mal leído) sería un bucle de lecturas.
 */
const MAX_EXTENSION_PAGES = 20;

type Db = ReturnType<typeof getFirestore>;

export type DailyReminderKind = "streak-at-risk" | "comeback-reminder";

export interface NotifyDailyRemindersResult {
  /** Pushes despachados (`sendFcm` no tiró). */
  notified: number;
  notifiedStreakAtRisk: number;
  notifiedComeback: number;
  /** Candidatos que terminaron sin push por una razón de negocio. */
  skipped: number;
  skippedNotAthlete: number;
  skippedOptedOut: number;
  skippedAlreadySent: number;
  skippedCooldown: number;
  skippedNotAtRisk: number;
  /** Candidatos que tiraron un error. */
  failed: number;
  /** Atletas que pasaron el filtro barato por sesiones: notified + skipped + failed. */
  candidates: number;
  scannedSessions: number;
  /** Atletas con al menos una sesión que cuenta en la ventana. */
  athletesWithSessions: number;
  /** Hoy en ART, YYYY-MM-DD: el valor que se estampa en `lastDailyReminderDate`. */
  dateKey: string;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

// ─── Copy ─────────────────────────────────────────────────────────────────────

/** Título y cuerpo del "racha en riesgo". Singular y plural correctos. */
export function streakAtRiskCopy(
  missing: number,
  streakWeeks: number,
): { title: string; body: string } {
  const sesiones = missing === 1 ? "entrenamiento" : "entrenamientos";
  const semanas = streakWeeks === 1 ? "semana" : "semanas";
  return {
    title: "Hoy o se corta 🔥",
    body:
      `Te faltan ${missing} ${sesiones} esta semana ` +
      `para sostener tu racha de ${streakWeeks} ${semanas}.`,
  };
}

/** Título y cuerpo del "volvé a entrenar". */
export function comebackCopy(daysSince: number): { title: string; body: string } {
  const dias = daysSince === 1 ? "día" : "días";
  return {
    title: "Te extrañamos en el gym 💪",
    body: `Hace ${daysSince} ${dias} que no entrenás. ¿Arrancamos hoy?`,
  };
}

// ─── Fechas ART como texto ────────────────────────────────────────────────────

const DATE_KEY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Días calendario entre dos claves YYYY-MM-DD, o `null` si alguna no parsea. */
export function daysBetweenDateKeys(fromKey: string, toKey: string): number | null {
  const from = DATE_KEY.exec(fromKey);
  const to = DATE_KEY.exec(toKey);
  if (!from || !to) return null;
  const fromMs = Date.UTC(Number(from[1]), Number(from[2]) - 1, Number(from[3]));
  const toMs = Date.UTC(Number(to[1]), Number(to[2]) - 1, Number(to[3]));
  return Math.round((toMs - fromMs) / DAY_MS);
}

/**
 * ¿Pasó el cooldown del "volvé a entrenar"? Nunca enviado (o un valor que no es
 * una fecha) cuenta como cumplido. Con `COMEBACK_COOLDOWN_DAYS = 7`: enviado el
 * día D, el D+6 sigue bloqueado y el D+7 pasa.
 */
export function comebackCooldownElapsed(last: unknown, todayKey: string): boolean {
  if (typeof last !== "string") return true;
  const elapsed = daysBetweenDateKeys(last, todayKey);
  if (elapsed === null) return true;
  return elapsed >= COMEBACK_COOLDOWN_DAYS;
}

// ─── Lo que se sabe de un atleta sólo por sus sesiones ───────────────────────

interface Activity {
  /** Sesiones que cuentan en la semana en curso. */
  currentWeekCount: number;
  /** Sesiones que cuentan en la semana anterior. */
  previousWeekCount: number;
  /** Ya completó una sesión HOY (fecha ART). */
  trainedToday: boolean;
  /** Días calendario ART desde la última sesión que cuenta. */
  daysSinceLast: number;
}

interface Calendar {
  /** Lunes de la semana en curso, en el marco ART. */
  currentWeek: number;
  previousWeek: number;
  todayNumber: number;
  daysLeft: number;
  todayKey: string;
}

function summarizeActivity(startsMs: readonly number[], cal: Calendar): Activity {
  let currentWeekCount = 0;
  let previousWeekCount = 0;
  let trainedToday = false;
  let lastMs = Number.NEGATIVE_INFINITY;

  for (const ms of startsMs) {
    const week = mondayOfWeekArt(toArgentina(ms));
    if (week === cal.currentWeek) currentWeekCount++;
    else if (week === cal.previousWeek) previousWeekCount++;
    if (artDayNumber(ms) === cal.todayNumber) trainedToday = true;
    if (ms > lastMs) lastMs = ms;
  }

  return {
    currentWeekCount,
    previousWeekCount,
    trainedToday,
    daysSinceLast: cal.todayNumber - artDayNumber(lastMs),
  };
}

// ─── Lecturas de rutinas → objetivo semanal ──────────────────────────────────

/**
 * El objetivo semanal del atleta: los días con ejercicios de su rutina ACTIVA,
 * o 1 si no tiene ninguna. Mismas queries que `RoutineRepository` y misma
 * cadena de prioridad que `todaysRoutineProvider`, que es la que alimenta la
 * racha que el atleta ve en la app.
 */
async function loadWeeklyTarget(
  db: Db,
  uid: string,
  activeRoutineId: unknown,
): Promise<number> {
  const marker = typeof activeRoutineId === "string" ? activeRoutineId : null;

  const [assignedSnap, ownSnap] = await Promise.all([
    // `RoutineRepository.listAssignedTo`: el `limit(20)` va ANTES de descartar
    // las archivadas, igual que allá (las archivadas ocupan lugar).
    db
      .collection("routines")
      .where("assignedTo", "==", uid)
      .where("source", "==", "trainer-assigned")
      .orderBy("createdAt", "desc")
      .limit(20)
      .get(),
    // `RoutineRepository.listUserCreated`.
    db
      .collection("routines")
      .where("createdBy", "==", uid)
      .where("source", "==", "user-created")
      .where("status", "==", "active")
      .orderBy("createdAt", "desc")
      .get(),
  ]);

  // El filtro de archivadas va del lado del cliente en Dart (los docs viejos no
  // traen `status`), y acá también: `!== "archived"` deja pasar los que no lo
  // traen y los valores desconocidos, que Dart interpreta como `active`.
  const assigned = assignedSnap.docs.filter((d) => d.data().status !== "archived");
  const own = ownSnap.docs;

  let resolvedId = resolveActiveRoutineId({
    activeRoutineId: marker,
    assignedIds: assigned.map((d) => d.id),
    selfCreatedIds: own.map((d) => d.id),
  });

  // El catálogo se consulta en un único caso, igual que en el Home: hay
  // marcador y no matcheó contra los planes del atleta. Entonces puede ser una
  // plantilla del sistema que eligió SEGUIR sin copiarla. Como el catálogo sólo
  // participa del tier 0, alcanza con preguntar si ESE id es una plantilla del
  // catálogo (`listSystemTemplates`: source == 'system' && visibility ==
  // 'public'), sin traer las demás.
  let catalogData: DocumentData | undefined;
  if (marker !== null && marker !== "" && resolvedId !== marker) {
    const snap = await db.collection("routines").doc(marker).get();
    const data = snap.data();
    if (snap.exists && data?.source === "system" && data.visibility === "public") {
      catalogData = data;
      resolvedId = resolveActiveRoutineId({
        activeRoutineId: marker,
        assignedIds: assigned.map((d) => d.id),
        selfCreatedIds: own.map((d) => d.id),
        catalogIds: [marker],
      });
    }
  }

  if (resolvedId === null) return weeklyTargetFromRoutine(null);

  const routine =
    assigned.find((d) => d.id === resolvedId)?.data() ??
    own.find((d) => d.id === resolvedId)?.data() ??
    (resolvedId === marker ? catalogData : undefined);

  return weeklyTargetFromRoutine(routine);
}

// ─── Racha exacta cuando toca el borde de la ventana ─────────────────────────

function timestampMs(value: unknown): number | null {
  const date = (value as { toDate?: () => Date } | null | undefined)?.toDate?.();
  return date instanceof Date && !Number.isNaN(date.getTime()) ? date.getTime() : null;
}

/**
 * Completa la racha de UN usuario cuando la corrida de semanas cumplidas llegó
 * al borde de la ventana: pide, de a páginas y de la más nueva a la más vieja,
 * las sesiones anteriores a la ventana hasta encontrar una semana que corte (o
 * quedarse sin sesiones).
 *
 * Una página puede cortar una semana por la mitad, así que cada vez se declara
 * «completo» sólo desde el lunes SIGUIENTE a la sesión más vieja de la página:
 * una semana a medio cargar no puede juzgarse.
 */
async function exactStreakWeeks(
  db: Db,
  uid: string,
  input: { startsMs: readonly number[]; target: number; now: Date; windowStartMs: number },
): Promise<number> {
  const { target, now, windowStartMs } = input;
  const starts = [...input.startsMs];
  let detail = weeklyStreakFromStarts({
    countingStartsMs: starts,
    weeklyTarget: target,
    now,
    dataStart: new Date(windowStartMs),
  });

  let cursor: QueryDocumentSnapshot | undefined;
  for (let page = 0; detail.truncated && page < MAX_EXTENSION_PAGES; page++) {
    let query: Query = db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .where("startedAt", "<", Timestamp.fromDate(new Date(windowStartMs)))
      .orderBy("startedAt", "desc")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();

    let oldestMs = Number.POSITIVE_INFINITY;
    for (const doc of snap.docs) {
      const data = doc.data();
      const ms = timestampMs(data.startedAt);
      if (ms === null) continue;
      if (ms < oldestMs) oldestMs = ms;
      if (sessionCountsAsWorkout(data.status, data.wasFullyCompleted)) starts.push(ms);
    }

    const exhausted = snap.size < PAGE_SIZE || !Number.isFinite(oldestMs);
    cursor = snap.docs[snap.docs.length - 1];
    detail = weeklyStreakFromStarts({
      countingStartsMs: starts,
      weeklyTarget: target,
      now,
      // Agotadas las sesiones no hay nada más que cargar: se tiene todo.
      dataStart: exhausted ? undefined : new Date(weekStartInstantArt(oldestMs) + WEEK_MS),
    });
    if (exhausted) break;
  }

  if (detail.truncated) {
    // Sólo si se agotó MAX_EXTENSION_PAGES. El número es un piso, no una mentira
    // grande: se loguea para poder verlo.
    logger.warn("notifyDailyReminders: streak still truncated after extension pages", {
      uid,
      streak: detail.streak,
      pages: MAX_EXTENSION_PAGES,
    });
  }
  return detail.streak;
}

// ─── Decisión por atleta ──────────────────────────────────────────────────────

type Reminder =
  | { kind: "streak-at-risk"; missing: number; streakWeeks: number }
  | { kind: "comeback-reminder"; daysSince: number };

type SkipReason = "not-athlete" | "opted-out" | "already-sent" | "cooldown" | "not-at-risk";

type Outcome =
  | { status: "notified"; kind: DailyReminderKind }
  | { status: "skipped"; reason: SkipReason };

interface RunContext {
  app: App;
  db: Db;
  messaging?: Messaging;
  now: Date;
  cal: Calendar;
  windowStartMs: number;
}

/** Sólo un `push === false` EXPLÍCITO apaga; igual criterio que `sendFcm`. */
function pushOptedOut(user: DocumentData): boolean {
  const prefs = user.notificationPrefs as
    | Record<string, { push?: unknown } | undefined>
    | null
    | undefined;
  return prefs?.[DAILY_REMINDERS_PREF_KEY]?.push === false;
}

/**
 * ¿Está la racha en riesgo HOY? Devuelve el recordatorio o `null`.
 *
 * El pre-filtro del que sale el candidato ya garantiza una condición necesaria
 * (`previousWeekCount >= currentWeekCount + daysLeft`, ver `handler`); acá se
 * confirma con el objetivo REAL del atleta, que es lo único que no se sabía.
 */
async function streakReminderFor(
  ctx: RunContext,
  uid: string,
  user: DocumentData,
  startsMs: readonly number[],
  activity: Activity,
): Promise<Reminder | null> {
  const target = await loadWeeklyTarget(ctx.db, uid, user.activeRoutineId);

  // «Faltan exactamente tantos como días quedan»: el objetivo tiene que ser lo
  // que lleva la semana más los días que restan.
  const missing = target - activity.currentWeekCount;
  if (missing <= 0 || missing !== ctx.cal.daysLeft) return null;

  const detail = weeklyStreakFromStarts({
    countingStartsMs: startsMs,
    weeklyTarget: target,
    now: ctx.now,
    dataStart: new Date(ctx.windowStartMs),
  });
  if (detail.currentWeekMet || detail.streak < 1) return null;

  // La corrida llegó al borde de la ventana: el número real puede ser mayor.
  let streakWeeks = detail.streak;
  if (detail.truncated) {
    streakWeeks = await exactStreakWeeks(ctx.db, uid, {
      startsMs,
      target,
      now: ctx.now,
      windowStartMs: ctx.windowStartMs,
    });
  }

  return { kind: "streak-at-risk", missing, streakWeeks };
}

async function processCandidate(
  ctx: RunContext,
  uid: string,
  startsMs: readonly number[],
  activity: Activity,
  flags: { streakCandidate: boolean; comebackCandidate: boolean },
): Promise<Outcome> {
  const userRef = ctx.db.collection("users").doc(uid);

  // Lectura previa, sólo para descartar barato ANTES de leer rutinas. La
  // autoridad es la transacción de abajo, que vuelve a verificar todo.
  const snap = await userRef.get();
  const user = snap.data();
  if (!snap.exists || !user || user.role !== "athlete") {
    return { status: "skipped", reason: "not-athlete" };
  }
  if (pushOptedOut(user)) return { status: "skipped", reason: "opted-out" };
  if (user.lastDailyReminderDate === ctx.cal.todayKey) {
    return { status: "skipped", reason: "already-sent" };
  }

  let reminder: Reminder | null = null;
  if (flags.streakCandidate) {
    reminder = await streakReminderFor(ctx, uid, user, startsMs, activity);
  }
  const cooldownOk = comebackCooldownElapsed(user.lastComebackReminderDate, ctx.cal.todayKey);
  if (!reminder && flags.comebackCandidate && cooldownOk) {
    reminder = { kind: "comeback-reminder", daysSince: activity.daysSinceLast };
  }
  if (!reminder) {
    return {
      status: "skipped",
      reason: flags.comebackCandidate && !cooldownOk ? "cooldown" : "not-at-risk",
    };
  }
  const chosen = reminder;

  // Se RESERVA el día en una transacción ANTES de despachar, no después.
  //
  // Con el marcador escrito al final, dos corridas solapadas —el scheduler
  // reintenta ante un timeout parcial— podían leer las dos el marcador viejo,
  // mandar las dos el push y recién ahí escribirlo: dos notificaciones y dos
  // filas de historial por el mismo día. La transacción hace que sólo una gane.
  //
  // El riesgo se invierte: si el envío falla DESPUÉS de reservar, el día queda
  // marcado sin push. Por eso el catch de abajo suelta la reserva.
  const claim = await ctx.db.runTransaction(async (tx) => {
    const fresh = await tx.get(userRef);
    const data = fresh.data();
    if (!fresh.exists || !data || data.role !== "athlete") {
      return { status: "not-athlete" as const };
    }
    if (pushOptedOut(data)) return { status: "opted-out" as const };
    if (data.lastDailyReminderDate === ctx.cal.todayKey) {
      return { status: "already-sent" as const };
    }
    if (
      chosen.kind === "comeback-reminder" &&
      !comebackCooldownElapsed(data.lastComebackReminderDate, ctx.cal.todayKey)
    ) {
      return { status: "cooldown" as const };
    }

    const update: Record<string, unknown> = { lastDailyReminderDate: ctx.cal.todayKey };
    if (chosen.kind === "comeback-reminder") {
      update.lastComebackReminderDate = ctx.cal.todayKey;
    }
    tx.update(userRef, update);
    return {
      status: "claimed" as const,
      previousDaily: data.lastDailyReminderDate as unknown,
      previousComeback: data.lastComebackReminderDate as unknown,
    };
  });

  if (claim.status !== "claimed") return { status: "skipped", reason: claim.status };

  const copy =
    chosen.kind === "streak-at-risk"
      ? streakAtRiskCopy(chosen.missing, chosen.streakWeeks)
      : comebackCopy(chosen.daysSince);

  try {
    await sendFcm(
      ctx.app,
      {
        uids: [uid],
        kind: chosen.kind,
        notification: copy,
        data: { deepLink: DAILY_REMINDER_DEEP_LINK },
        // El opt-out ya se resolvió arriba, ANTES de reservar. Se pasa igual por
        // consistencia con el resto de los productores: si alguien lo apaga entre
        // la transacción y el envío, `sendFcm` todavía frena el banner.
        prefKey: DAILY_REMINDERS_PREF_KEY,
      },
      ctx.messaging,
    );
  } catch (sendError: unknown) {
    // Soltar la reserva restaurando lo que había: sin esto el día queda marcado
    // y el atleta no recibe el aviso, ni en el reintento.
    const restore: Record<string, unknown> = {
      lastDailyReminderDate:
        claim.previousDaily === undefined ? FieldValue.delete() : claim.previousDaily,
    };
    if (chosen.kind === "comeback-reminder") {
      restore.lastComebackReminderDate =
        claim.previousComeback === undefined ? FieldValue.delete() : claim.previousComeback;
    }
    await userRef.update(restore).catch(() => undefined);
    throw sendError;
  }

  return { status: "notified", kind: chosen.kind };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

/** Handler con el reloj y Messaging inyectados para que los tests no toquen FCM. */
export async function notifyDailyRemindersHandler(
  app: App,
  now: Date,
  messaging?: Messaging,
): Promise<NotifyDailyRemindersResult> {
  const db = getFirestore(app);
  const nowMs = now.getTime();

  const currentWeek = mondayOfWeekArt(toArgentina(nowMs));
  const cal: Calendar = {
    currentWeek,
    previousWeek: previousWeekArt(currentWeek),
    todayNumber: artDayNumber(nowMs),
    daysLeft: daysLeftInWeekArt(nowMs),
    todayKey: artDateKey(now),
  };
  // Lunes 00:00 ART de hace 8 semanas, como INSTANTE real.
  const windowStartMs = weekStartInstantArt(nowMs) - STREAK_WINDOW_WEEKS * WEEK_MS;

  // ── 1. Una sola query paginada, agrupada por uid en memoria ──
  const startsByUid = new Map<string, number[]>();
  let scannedSessions = 0;
  let cursor: QueryDocumentSnapshot | undefined;

  do {
    let query: Query = db
      .collectionGroup("sessions")
      .where("startedAt", ">=", Timestamp.fromDate(new Date(windowStartMs)))
      .where("startedAt", "<", Timestamp.fromDate(now))
      .orderBy("startedAt", "asc")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();

    for (const sessionDoc of page.docs) {
      scannedSessions++;
      const data = sessionDoc.data();
      if (!sessionCountsAsWorkout(data.status, data.wasFullyCompleted)) continue;

      const startedMs = timestampMs(data.startedAt);
      const uid = sessionDoc.ref.parent.parent?.id;
      if (startedMs === null || !uid) {
        logger.warn("notifyDailyReminders: session without startedAt or user parent", {
          sessionPath: sessionDoc.ref.path,
        });
        continue;
      }
      const list = startsByUid.get(uid);
      if (list) list.push(startedMs);
      else startsByUid.set(uid, [startedMs]);
    }

    cursor = page.size === PAGE_SIZE ? page.docs[page.docs.length - 1] : undefined;
  } while (cursor);

  // ── 2. Por atleta ──
  const ctx: RunContext = { app, db, messaging, now, cal, windowStartMs };
  const result: NotifyDailyRemindersResult = {
    notified: 0,
    notifiedStreakAtRisk: 0,
    notifiedComeback: 0,
    skipped: 0,
    skippedNotAthlete: 0,
    skippedOptedOut: 0,
    skippedAlreadySent: 0,
    skippedCooldown: 0,
    skippedNotAtRisk: 0,
    failed: 0,
    candidates: 0,
    scannedSessions,
    athletesWithSessions: startsByUid.size,
    dateKey: cal.todayKey,
  };

  for (const [uid, startsMs] of startsByUid) {
    const activity = summarizeActivity(startsMs, cal);

    // Filtros baratos, sólo con lo que ya está en memoria: un atleta que no
    // puede calificar a ninguno de los dos no cuesta una lectura más.
    //
    // Racha: tiene que haber cumplido la semana anterior con el objetivo que
    // haría que hoy «le falten tantos como días quedan». Ese objetivo es
    // `semana en curso + días que quedan`; si la semana anterior no llegó ni a
    // eso, ninguna rutina posible lo pone en riesgo. Es una condición NECESARIA
    // (la racha ≥ 1 exige `previousWeekCount >= objetivo`), calculada sin leer
    // rutinas, y la decisión final se toma con el objetivo real.
    const streakCandidate =
      !activity.trainedToday &&
      activity.previousWeekCount >= activity.currentWeekCount + cal.daysLeft;
    const comebackCandidate = activity.daysSinceLast >= COMEBACK_MIN_DAYS;
    if (!streakCandidate && !comebackCandidate) continue;

    result.candidates++;
    try {
      const outcome = await processCandidate(ctx, uid, startsMs, activity, {
        streakCandidate,
        comebackCandidate,
      });

      if (outcome.status === "notified") {
        result.notified++;
        if (outcome.kind === "streak-at-risk") result.notifiedStreakAtRisk++;
        else result.notifiedComeback++;
        continue;
      }

      result.skipped++;
      switch (outcome.reason) {
      case "not-athlete":
        result.skippedNotAthlete++;
        break;
      case "opted-out":
        result.skippedOptedOut++;
        break;
      case "already-sent":
        result.skippedAlreadySent++;
        break;
      case "cooldown":
        result.skippedCooldown++;
        break;
      case "not-at-risk":
        result.skippedNotAtRisk++;
        break;
      }
    } catch (error: unknown) {
      result.failed++;
      // `Error` no se serializa en el logger (sale `{}`): se loguea el mensaje.
      logger.error("notifyDailyReminders: failed for athlete", {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  logger.info("notifyDailyReminders: run complete", result);
  return result;
}

/**
 * Corre todos los días a las 10:00 ART, en la misma región que el resto de las
 * CFs de TREINO. `timeoutSeconds: 540` porque, a diferencia del reporte mensual,
 * el escaneo es de 9 semanas todos los días y el envío es secuencial.
 */
export const notifyDailyReminders = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    timeoutSeconds: 540,
  },
  async () => {
    const result = await notifyDailyRemindersHandler(ensureApp(), new Date());
    logger.info("notifyDailyReminders: scheduled run done", result);
  },
);
