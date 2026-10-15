/**
 * dispatchDailyReminders — el DESPACHANTE de los recordatorios diarios.
 *
 * Corre cada 15 minutos. El planificador (`notify-daily-reminders.ts`, 06:00 ART)
 * deja en `users/{uid}.dailyReminderPlan` qué recordatorio le toca hoy a cada
 * atleta y a partir de qué minuto del día; este es quien lo manda cuando llega la
 * hora. Lee el porqué del diseño, los horarios y el tope del "volvé a entrenar"
 * en la cabecera de ese archivo: acá sólo va lo propio del despachante.
 *
 * Despacha los tres tipos de plan: `streak-at-risk` ("Hoy o se corta"),
 * `training-due` ("Hoy toca entrenar") y `comeback-reminder` ("Te extrañamos").
 * Todos pasan por el MISMO camino y las mismas reglas —no manda si el atleta
 * arrancó cualquier sesión hoy, reserva en una transacción, tope de reintentos—;
 * lo único que cambia por tipo es el texto (`reminderCopy`) y que el cooldown de
 * 7 días y su marcador son sólo del comeback.
 *
 * ─── Qué hace en cada tick ─────────────────────────────────────────────────
 *
 * 1. Antes de las 08:00 ART no hace nada, ni siquiera lee: ningún plan puede
 *    vencer antes del piso (`REMINDER_MIN_MINUTE`). Evita releer los planes que
 *    el planificador todavía está escribiendo.
 * 2. UNA query a `users` por IGUALDAD: `dailyReminderPlan.date == hoy`. Nada de
 *    rangos ni `orderBy`, a propósito: una igualdad sobre un campo de un mapa la
 *    indexa Firestore sola, así que no hace falta tocar `firestore.indexes.json`
 *    (un deploy de índices a producción). El filtro `sendAtMinute <= ahora` se
 *    hace en memoria.
 * 3. Por cada plan VENCIDO, en este orden:
 *    a. Lee las sesiones que ese atleta arrancó HOY (una query de una lectura:
 *       `users/{uid}/sessions`, `startedAt >= hoy 00:00 ART`, `limit(1)`).
 *    b. Si arrancó CUALQUIERA, en el estado que sea —en curso, terminada o
 *       abandonada—, no manda NADA y borra el plan. Ni la racha (ya está
 *       entrenando) ni el "volvé a entrenar" (ya volvió). Un `sessionCountsAsWorkout`
 *       acá sería un error: una sesión en curso a las 18:05 es justo el atleta
 *       al que NO hay que escribirle. Vale para los tres tipos: la racha y el
 *       «hoy toca» ya están entrenando, el comeback ya volvió.
 *    c. Si no, RESERVA en una transacción (ver abajo) y manda con `sendFcm`.
 *    d. Si el envío falla, restaura los marcadores previos Y el plan, y el
 *       próximo tick reintenta.
 *
 * ─── La reserva ────────────────────────────────────────────────────────────
 *
 * Mismo patrón que el resto de los productores: el día se RESERVA en una
 * transacción antes de mandar, así dos ticks solapados (el anterior sigue
 * corriendo cuando arranca el siguiente) no pueden mandar los dos. La
 * transacción vuelve a verificar TODO contra el doc fresco, porque entre la
 * query y la reserva pasó tiempo:
 *
 *   · que sea atleta,
 *   · que no haya apagado el push (`pushOptedOut`, el mismo predicado que el
 *     planificador),
 *   · que `lastDailyReminderDate !== hoy`,
 *   · que el plan siga siendo de HOY (y bien formado),
 *   · y, sólo para el comeback, que haya pasado el cooldown de 7 días.
 *
 * Si todo pasa escribe `lastDailyReminderDate` (y `lastComebackReminderDate` si
 * es comeback; la racha y el «hoy toca» NO tocan el cooldown) y borra el plan.
 * Si algo falla por una razón terminal (opt-out, ya enviado, cooldown, plan
 * malformado) también borra el plan, para no releerlo y reintentarlo en cada
 * tick del resto del día.
 *
 * ⚠️  Queda una ventana entre el paso (a) y el envío: un atleta que arranca una
 * sesión JUSTO ahí recibe igual el push. No es un descuido de orden sino algo que
 * no se puede cerrar del todo: aunque la lectura de sesiones se moviera adentro
 * de la transacción, el atleta puede arrancar la sesión un instante DESPUÉS del
 * envío y el resultado es el mismo. Se achica (la lectura va inmediatamente antes
 * de la reserva, por atleta y sin esperas entre medio), no se elimina. El costo
 * de la ventana es un push de más a quien justo estaba por entrenar.
 *
 * ─── Reintentos ────────────────────────────────────────────────────────────
 *
 * Un envío fallido deja el plan en pie (con un contador `attempts`), así que se
 * reintenta en el tick siguiente. El tope es {@link MAX_SEND_ATTEMPTS} = 3: al
 * tercer fallo el plan se descarta y ese día no hay aviso. No es solo por costo
 * (cada intento es una query de sesiones, una transacción y el envío): `sendFcm`
 * escribe la fila del historial in-app ANTES de llamar a FCM, así que cada
 * intento fallido deja una fila repetida en la campanita. Un `sendFcm` que tira
 * de verdad (no un token muerto: eso lo absorbe `sendFcm`) significa FCM o la
 * red caídos. Ver el punto «d.» en `dispatchOne`.
 *
 * ─── Planes viejos ─────────────────────────────────────────────────────────
 *
 * Un plan de un día anterior que haya quedado en el doc no matchea la query de
 * hoy, así que el despachante no lo ve y no hace falta limpiarlo: ocupa unos
 * bytes hasta que el planificador lo pise con el plan de otro día.
 *
 * ─── Costo ─────────────────────────────────────────────────────────────────
 *
 * Por tick: la query de planes de hoy (una lectura por plan, VENCIDO O NO; ver
 * «Costo de lecturas» en `notify-daily-reminders.ts` para la cuenta y el remedio)
 * y, por cada plan vencido, la query de sesiones (una lectura) más la transacción
 * (una lectura y una escritura). Un plan que se despacha o se descarta sale de la
 * query: se paga una sola vez.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { DocumentReference, FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { Messaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { artDateKey } from "../mail/format";
import {
  REMINDER_MIN_MINUTE,
  minuteOfDayArt,
  startOfDayInstantArt,
} from "./habitual-time";
import {
  DAILY_REMINDERS_PREF_KEY,
  DAILY_REMINDER_DEEP_LINK,
  DAILY_REMINDER_PLAN_DATE_PATH,
  DAILY_REMINDER_PLAN_FIELD,
  DailyReminderKind,
  DailyReminderPlan,
  comebackCooldownElapsed,
  pushOptedOut,
  reminderCopy,
} from "./notify-daily-reminders";
import { sendFcm } from "./send-fcm";

type Db = ReturnType<typeof getFirestore>;

export interface DispatchDailyRemindersResult {
  /** Pushes despachados (`sendFcm` no tiró). */
  notified: number;
  notifiedStreakAtRisk: number;
  notifiedTrainingDue: number;
  notifiedComeback: number;
  /** Planes de hoy que devolvió la query. */
  plans: number;
  /** Planes a los que todavía no les toca: `sendAtMinute` > minuto actual. */
  notDue: number;
  /** Planes vencidos que terminaron sin push por una razón de negocio. */
  skipped: number;
  skippedTrainedToday: number;
  skippedNotAthlete: number;
  skippedOptedOut: number;
  skippedAlreadySent: number;
  skippedCooldown: number;
  /** Otro tick (o una corrida del planificador) ya lo consumió o lo cambió. */
  skippedPlanGone: number;
  skippedInvalidPlan: number;
  /** Planes vencidos que tiraron un error. */
  failed: number;
  /** Hoy en ART, YYYY-MM-DD. */
  dateKey: string;
  /** Minuto del día ART contra el que se comparó `sendAtMinute`. */
  minuteOfDay: number;
}

type SkipReason =
  | "trained-today"
  | "not-athlete"
  | "opted-out"
  | "already-sent"
  | "cooldown"
  | "plan-gone"
  | "invalid-plan";

type Outcome =
  | { status: "notified"; kind: DailyReminderKind }
  | { status: "skipped"; reason: SkipReason };

type Claim =
  | { status: SkipReason }
  | {
      status: "claimed";
      plan: DailyReminderPlan;
      previousDaily: unknown;
      previousComeback: unknown;
      previousPlan: unknown;
    };

interface DispatchContext {
  app: App;
  db: Db;
  messaging?: Messaging;
  todayKey: string;
  /** Instante real en que arrancó hoy (00:00 ART). */
  dayStartMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Intentos de envío por plan antes de descartarlo. Ver el punto «d.» en
 * `dispatchOne`: cada intento fallido deja una fila en el historial in-app.
 */
export const MAX_SEND_ATTEMPTS = 3;

// ─── El plan, leído con desconfianza ──────────────────────────────────────────

function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 1;
}

/**
 * Valida la forma de un plan leído de Firestore, o `null` si no sirve.
 *
 * El planificador es el único que debería escribirlo, pero `firestore.rules` no
 * pinea el campo (ver «Reglas de Firestore» en la cabecera del planificador): el
 * dueño del doc puede escribirlo a mano. Lo peor que logra es mandarse un push a
 * sí mismo, pero un `missing` que no es un número no tiene por qué terminar en el
 * texto de una notificación. Por eso el texto se arma sólo con enteros validados.
 */
export function parseDailyReminderPlan(raw: unknown): DailyReminderPlan | null {
  if (raw === null || typeof raw !== "object") return null;
  const plan = raw as Record<string, unknown>;
  const { date, kind, sendAtMinute } = plan;
  if (typeof date !== "string") return null;
  if (typeof sendAtMinute !== "number" || !Number.isFinite(sendAtMinute)) return null;

  if (kind === "streak-at-risk") {
    if (!isCount(plan.missing) || !isCount(plan.streakWeeks)) return null;
    return { date, kind, sendAtMinute, missing: plan.missing, streakWeeks: plan.streakWeeks };
  }
  if (kind === "training-due") {
    if (!isCount(plan.missing)) return null;
    return { date, kind, sendAtMinute, missing: plan.missing };
  }
  if (kind === "comeback-reminder") {
    if (!isCount(plan.daysSince)) return null;
    return { date, kind, sendAtMinute, daysSince: plan.daysSince };
  }
  return null;
}

// ─── Un plan vencido ──────────────────────────────────────────────────────────

async function dispatchOne(
  ctx: DispatchContext,
  userRef: DocumentReference,
): Promise<Outcome> {
  // ── a. ¿Arrancó CUALQUIER sesión hoy? Sin filtrar por estado, a propósito. ──
  const startedToday = await userRef
    .collection("sessions")
    .where("startedAt", ">=", Timestamp.fromDate(new Date(ctx.dayStartMs)))
    .limit(1)
    .get();
  if (!startedToday.empty) {
    await userRef.update({ [DAILY_REMINDER_PLAN_FIELD]: FieldValue.delete() });
    return { status: "skipped", reason: "trained-today" };
  }

  // ── c. Reserva transaccional. ──
  const claim = await ctx.db.runTransaction(async (tx): Promise<Claim> => {
    const fresh = await tx.get(userRef);
    const data = fresh.data();
    if (!fresh.exists || !data) return { status: "not-athlete" };

    const rawPlan: unknown = data[DAILY_REMINDER_PLAN_FIELD];
    const dropPlan = (): void => {
      if (rawPlan !== undefined) {
        tx.update(userRef, { [DAILY_REMINDER_PLAN_FIELD]: FieldValue.delete() });
      }
    };

    if (data.role !== "athlete") {
      dropPlan();
      return { status: "not-athlete" };
    }
    if (pushOptedOut(data)) {
      dropPlan();
      return { status: "opted-out" };
    }
    if (data.lastDailyReminderDate === ctx.todayKey) {
      dropPlan();
      return { status: "already-sent" };
    }

    // El plan puede haber cambiado desde la query: se manda lo que dice AHORA.
    if (rawPlan === undefined) return { status: "plan-gone" };
    const current = parseDailyReminderPlan(rawPlan);
    if (current === null) {
      dropPlan();
      return { status: "invalid-plan" };
    }
    // Un plan de otro día no es nuestro: no se manda ni se toca.
    if (current.date !== ctx.todayKey) return { status: "plan-gone" };

    if (
      current.kind === "comeback-reminder" &&
      !comebackCooldownElapsed(data.lastComebackReminderDate, ctx.todayKey)
    ) {
      dropPlan();
      return { status: "cooldown" };
    }

    const update: Record<string, unknown> = {
      lastDailyReminderDate: ctx.todayKey,
      [DAILY_REMINDER_PLAN_FIELD]: FieldValue.delete(),
    };
    if (current.kind === "comeback-reminder") {
      update.lastComebackReminderDate = ctx.todayKey;
    }
    tx.update(userRef, update);
    return {
      status: "claimed",
      plan: current,
      previousDaily: data.lastDailyReminderDate as unknown,
      previousComeback: data.lastComebackReminderDate as unknown,
      previousPlan: rawPlan,
    };
  });

  if (claim.status !== "claimed") return { status: "skipped", reason: claim.status };

  const { plan: chosen } = claim;
  try {
    await sendFcm(
      ctx.app,
      {
        uids: [userRef.id],
        kind: chosen.kind,
        notification: reminderCopy(chosen),
        data: { deepLink: DAILY_REMINDER_DEEP_LINK },
        // El opt-out ya se resolvió en la reserva. Se pasa igual por consistencia
        // con el resto de los productores: si alguien lo apaga entre la
        // transacción y el envío, `sendFcm` todavía frena el banner.
        prefKey: DAILY_REMINDERS_PREF_KEY,
      },
      ctx.messaging,
    );
  } catch (sendError: unknown) {
    // ── d. Soltar la reserva: marcadores previos Y plan. Sin esto el día queda
    // marcado sin push, y sin el plan el próximo tick no tiene nada que reintentar.
    //
    // Pero con TOPE: `sendFcm` escribe la fila del historial in-app ANTES de
    // llamar a FCM, así que cada intento fallido deja una fila del mismo
    // recordatorio en la campanita. Sin tope, una caída de FCM de una tarde eran
    // hasta ~60 filas iguales. Al [MAX_SEND_ATTEMPTS]-ésimo fallo el plan se descarta: ese
    // día no hay aviso, y los marcadores igual se restauran.
    const previous = claim.previousPlan as Record<string, unknown>;
    const attempts = (typeof previous.attempts === "number" ? previous.attempts : 0) + 1;
    const giveUp = attempts >= MAX_SEND_ATTEMPTS;
    if (giveUp) {
      logger.warn("dispatchDailyReminders: giving up after repeated send failures", {
        uid: userRef.id,
        attempts,
      });
    }
    const restore: Record<string, unknown> = {
      lastDailyReminderDate:
        claim.previousDaily === undefined ? FieldValue.delete() : claim.previousDaily,
      [DAILY_REMINDER_PLAN_FIELD]: giveUp ? FieldValue.delete() : { ...previous, attempts },
    };
    if (chosen.kind === "comeback-reminder") {
      restore.lastComebackReminderDate =
        claim.previousComeback === undefined ? FieldValue.delete() : claim.previousComeback;
    }
    await userRef.update(restore).catch((restoreError: unknown) => {
      // Sin esto el atleta pierde el aviso de hoy sin que quede rastro de por qué.
      logger.warn("dispatchDailyReminders: could not release the reservation", {
        uid: userRef.id,
        error: restoreError instanceof Error ? restoreError.message : String(restoreError),
      });
    });
    throw sendError;
  }

  return { status: "notified", kind: chosen.kind };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

function tally(result: DispatchDailyRemindersResult, outcome: Outcome): void {
  if (outcome.status === "notified") {
    result.notified++;
    if (outcome.kind === "streak-at-risk") result.notifiedStreakAtRisk++;
    else if (outcome.kind === "training-due") result.notifiedTrainingDue++;
    else result.notifiedComeback++;
    return;
  }
  result.skipped++;
  switch (outcome.reason) {
  case "trained-today":
    result.skippedTrainedToday++;
    break;
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
  case "plan-gone":
    result.skippedPlanGone++;
    break;
  case "invalid-plan":
    result.skippedInvalidPlan++;
    break;
  }
}

/** Handler con el reloj y Messaging inyectados para que los tests no toquen FCM. */
export async function dispatchDailyRemindersHandler(
  app: App,
  now: Date,
  messaging?: Messaging,
): Promise<DispatchDailyRemindersResult> {
  const db = getFirestore(app);
  const nowMs = now.getTime();
  const todayKey = artDateKey(now);
  const minuteOfDay = minuteOfDayArt(nowMs);

  const result: DispatchDailyRemindersResult = {
    notified: 0,
    notifiedStreakAtRisk: 0,
    notifiedTrainingDue: 0,
    notifiedComeback: 0,
    plans: 0,
    notDue: 0,
    skipped: 0,
    skippedTrainedToday: 0,
    skippedNotAthlete: 0,
    skippedOptedOut: 0,
    skippedAlreadySent: 0,
    skippedCooldown: 0,
    skippedPlanGone: 0,
    skippedInvalidPlan: 0,
    failed: 0,
    dateKey: todayKey,
    minuteOfDay,
  };

  // Ningún plan vence antes del piso: ni se lee. Ver el punto 1 de la cabecera.
  if (minuteOfDay < REMINDER_MIN_MINUTE) return result;

  const ctx: DispatchContext = {
    app,
    db,
    messaging,
    todayKey,
    dayStartMs: startOfDayInstantArt(nowMs),
  };

  // Sólo igualdad: ver el punto 2 de la cabecera.
  const plansSnap = await db
    .collection("users")
    .where(DAILY_REMINDER_PLAN_DATE_PATH, "==", todayKey)
    .get();
  result.plans = plansSnap.size;

  for (const doc of plansSnap.docs) {
    try {
      const plan = parseDailyReminderPlan(doc.data()[DAILY_REMINDER_PLAN_FIELD]);
      if (plan === null) {
        await doc.ref.update({ [DAILY_REMINDER_PLAN_FIELD]: FieldValue.delete() });
        tally(result, { status: "skipped", reason: "invalid-plan" });
        continue;
      }
      if (plan.sendAtMinute > minuteOfDay) {
        result.notDue++;
        continue;
      }
      tally(result, await dispatchOne(ctx, doc.ref));
    } catch (error: unknown) {
      result.failed++;
      // `Error` no se serializa en el logger (sale `{}`): se loguea el mensaje.
      logger.error("dispatchDailyReminders: failed for athlete", {
        uid: doc.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  // Un tick sin planes es lo normal en casi todos los 96 del día: no vale un log.
  if (result.plans > 0) logger.info("dispatchDailyReminders: run complete", result);
  return result;
}

/**
 * Cada 15 minutos, en la misma región que el resto de las CFs de TREINO.
 * `timeoutSeconds: 300`: bien por debajo del período, así un tick lento no se
 * superpone con el siguiente (si igual pasa, la reserva transaccional evita el
 * doble envío).
 */
export const dispatchDailyReminders = onSchedule(
  {
    schedule: "*/15 * * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    timeoutSeconds: 300,
  },
  async () => {
    await dispatchDailyRemindersHandler(ensureApp(), new Date());
  },
);
