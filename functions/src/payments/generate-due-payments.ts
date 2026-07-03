/**
 * generateDuePayments — Cloud Function for TREINO.
 *
 * Runs on a daily cron schedule at 03:00 ART. For every active trainer↔athlete
 * link whose billing cadence is `mensual` or `semanal`, it creates a deterministic
 * pending Payment document for the current period — if one does not already exist.
 *
 * Why server-side:
 *   - Admin SDK bypasses Firestore security rules (dueAt is write-protected for
 *     clients).
 *   - Deterministic ids + `create()` make the operation idempotent even under
 *     concurrent invocations (concurrent loser gets ALREADY_EXISTS → skipped).
 *   - Field-based existence check (trainerId, athleteId, periodKey) catches both
 *     deterministic ids from a previous CF run AND legacy auto-id docs created
 *     manually by the trainer, preventing double-billing.
 *
 * periodKey / dueAt:
 *   - mensual  → periodKey `YYYY-MM`; dueAt = last day of month 23:59:59 UTC
 *   - semanal  → periodKey `YYYY-Www`; dueAt = Sunday 23:59:59 UTC of ISO week
 *
 * The ISO-week math is a TypeScript port of pagos_por_cobrar_provider.dart
 * lines 20-45 so the client and CF always agree on periodKey.
 *
 * Deployed to southamerica-east1 (matches all other TREINO CFs).
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

// ---------------------------------------------------------------------------
// Lazy app singleton (project convention — mirrors cleanup-assigned-plans.ts)
// ---------------------------------------------------------------------------

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

// ---------------------------------------------------------------------------
// ISO-week helpers — TypeScript port of pagos_por_cobrar_provider.dart:20-45
//
// Must match Dart exactly so client and CF always produce the same periodKey.
// ---------------------------------------------------------------------------

/**
 * Returns the Thursday in the same ISO week as `date` (UTC).
 *
 * ISO weeks start on Monday. The "week-identifying Thursday" is the canonical
 * anchor used by both _isoWeekNumber and _isoWeekYear in the Dart client.
 */
function isoThursday(date: Date): Date {
  // date.getUTCDay(): 0=Sun,1=Mon,...,6=Sat  — Thursday = 4
  const dayOfWeek = date.getUTCDay(); // 0-6
  // Convert to Mon-based weekday 1-7
  const mondayBased = dayOfWeek === 0 ? 7 : dayOfWeek;
  // Thursday offset from current weekday (positive = forward, negative = backward)
  const offsetToThursday = 4 - mondayBased;
  const thursday = new Date(date);
  thursday.setUTCDate(date.getUTCDate() + offsetToThursday);
  return thursday;
}

/**
 * Returns the ISO 8601 week number for `date` (UTC).
 *
 * Mirrors Dart `_isoWeekNumber(date)`:
 *   final thursday = date.subtract(Duration(days: date.weekday - 4));
 *   final jan4 = DateTime.utc(thursday.year, 1, 4);
 *   final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
 *   return ((thursday.difference(week1Monday).inDays) ~/ 7) + 1;
 *
 * `date.weekday` in Dart is 1=Mon..7=Sun; `date.getUTCDay()` in JS is 0=Sun..6=Sat.
 * The formula here uses the same Thursday-anchor approach.
 */
export function isoWeekNumber(date: Date): number {
  const thu = isoThursday(date);
  const thuYear = thu.getUTCFullYear();

  // Jan 4 of Thursday's year — always in week 1 by ISO 8601 definition
  const jan4 = new Date(Date.UTC(thuYear, 0, 4));

  // Monday of week 1 (jan4's weekday, Mon-based)
  const jan4DayOfWeek = jan4.getUTCDay();
  const jan4MondayBased = jan4DayOfWeek === 0 ? 7 : jan4DayOfWeek;
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - (jan4MondayBased - 1));

  const diffMs = thu.getTime() - week1Monday.getTime();
  const diffDays = Math.floor(diffMs / 86400000);
  return Math.floor(diffDays / 7) + 1;
}

/**
 * Returns the ISO 8601 week-owning year for `date` (UTC).
 *
 * Mirrors Dart `_isoWeekYear(date)`:
 *   date.subtract(Duration(days: date.weekday - 4)).year
 *
 * Near the New Year boundary this may differ from the calendar year.
 * E.g. 2027-01-01 (Fri) is ISO week 53 of 2026 → owning year = 2026.
 */
export function isoWeekYear(date: Date): number {
  return isoThursday(date).getUTCFullYear();
}

/**
 * Returns `YYYY-Www` period key for the ISO week containing `date` (UTC).
 *
 * Mirrors Dart `isoWeekPeriodKey(date)`:
 *   '${_isoWeekYear(date)}-W${_isoWeekNumber(date).toString().padLeft(2, '0')}'
 */
export function isoWeekPeriodKey(date: Date): string {
  const ww = isoWeekNumber(date).toString().padStart(2, "0");
  return `${isoWeekYear(date)}-W${ww}`;
}

// ---------------------------------------------------------------------------
// Spanish month names — mirrors Dart _kMeses (1-indexed)
// ---------------------------------------------------------------------------

const MESES = [
  "",
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre",
];

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

export interface GenerateDueResult {
  created: number;
  skipped: number;
  scanned: number;
}

// ---------------------------------------------------------------------------
// Pure handler — emulator-testable, `now` injected for deterministic tests
// ---------------------------------------------------------------------------

/**
 * Generates pending Payment documents for the current period.
 *
 * @param app - Admin SDK app instance.
 * @param now - The reference timestamp (injected for testability; production
 *              passes `new Date()`).
 * @returns Counts of created, skipped, and scanned athlete-billing entries.
 */
export async function generateDuePaymentsHandler(
  app: admin.app.App,
  now: Date,
): Promise<GenerateDueResult> {
  const db = admin.firestore(app);

  let created = 0;
  let skipped = 0;
  let scanned = 0;

  // ── 1. Fetch all active trainer links ─────────────────────────────────────
  // Single equality filter → automatic single-field index, no composite needed.
  const linksSnap = await db
    .collection("trainer_links")
    .where("status", "==", "active")
    .get();

  if (linksSnap.empty) {
    logger.info("generateDuePayments: no active links found");
    return { created, skipped, scanned };
  }

  // ── 2. Pre-compute period keys and dueAt values from `now` (UTC) ──────────
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth() + 1; // 1-based month

  // mensual
  const monthKey = `${y}-${m.toString().padStart(2, "0")}`;
  // dueAt for mensual = last day of month 23:59:59 UTC.
  // Date.UTC(y, m, 0) gives the last day of month m (day 0 of month m+1).
  const mensualDueAt = new Date(Date.UTC(y, m, 0, 23, 59, 59));

  // semanal
  const weekKey = isoWeekPeriodKey(now);
  const weekNum = isoWeekNumber(now);
  // dueAt for semanal = Sunday 23:59:59 UTC of the ISO week.
  // ISO week starts Monday; Sunday is day 7 (Monday + 6 days).
  // Find Monday of this ISO week first.
  const dayOfWeek = now.getUTCDay(); // 0=Sun..6=Sat
  const mondayBased = dayOfWeek === 0 ? 7 : dayOfWeek;
  const mondayOfWeek = new Date(now);
  mondayOfWeek.setUTCDate(now.getUTCDate() - (mondayBased - 1));
  mondayOfWeek.setUTCHours(0, 0, 0, 0);
  const sundayOfWeek = new Date(mondayOfWeek);
  sundayOfWeek.setUTCDate(mondayOfWeek.getUTCDate() + 6);
  const semanaDueAt = new Date(
    Date.UTC(
      sundayOfWeek.getUTCFullYear(),
      sundayOfWeek.getUTCMonth(),
      sundayOfWeek.getUTCDate(),
      23,
      59,
      59,
    ),
  );

  // concept strings — mirror Dart client
  const mensualConcept = `Mensual ${MESES[m]} ${y}`;
  const semanaConcept = `Semana ${weekNum.toString().padStart(2, "0")}`;

  logger.info("generateDuePayments: starting run", {
    now: now.toISOString(),
    monthKey,
    weekKey,
    linksCount: linksSnap.size,
  });

  // ── 3. Per-link processing ────────────────────────────────────────────────
  for (const linkDoc of linksSnap.docs) {
    const link = linkDoc.data() as Record<string, unknown>;
    const trainerId = link.trainerId as string | undefined;
    const athleteId = link.athleteId as string | undefined;

    if (!trainerId || !athleteId) {
      logger.warn("generateDuePayments: link missing trainerId/athleteId", {
        linkId: linkDoc.id,
      });
      continue;
    }

    scanned++;

    // ── 3a. Read athlete_billing ──────────────────────────────────────────
    const billingSnap = await db
      .collection("athlete_billing")
      .doc(`${trainerId}_${athleteId}`)
      .get();

    if (!billingSnap.exists) {
      logger.info("generateDuePayments: no billing config — skipping", {
        trainerId,
        athleteId,
      });
      skipped++;
      continue;
    }

    const billing = billingSnap.data() as Record<string, unknown>;
    const cadence = billing.cadence as string | undefined;
    const amountArs = billing.amountArs as number | undefined;

    // ── 3b. Branch on cadence ─────────────────────────────────────────────
    let periodKey: string;
    let dueAt: Date;
    let concept: string;

    if (cadence === "mensual") {
      periodKey = monthKey;
      dueAt = mensualDueAt;
      concept = mensualConcept;
    } else if (cadence === "semanal") {
      periodKey = weekKey;
      dueAt = semanaDueAt;
      concept = semanaConcept;
    } else {
      // porSesion, suelto, or unknown — skip
      logger.info("generateDuePayments: non-periodic cadence — skipping", {
        trainerId,
        athleteId,
        cadence,
      });
      skipped++;
      continue;
    }

    // ── 3c. Field-based existence check ──────────────────────────────────
    // Catches BOTH deterministic docs from a previous run AND legacy auto-id
    // docs created manually. Checks any status (pending OR paid).
    const existingSnap = await db
      .collection("payments")
      .where("trainerId", "==", trainerId)
      .where("athleteId", "==", athleteId)
      .where("periodKey", "==", periodKey)
      .limit(1)
      .get();

    if (!existingSnap.empty) {
      logger.info("generateDuePayments: doc already exists for period — skipping", {
        trainerId,
        athleteId,
        periodKey,
        existingDocId: existingSnap.docs[0].id,
      });
      skipped++;
      continue;
    }

    // ── 3d. Create deterministic pending doc ──────────────────────────────
    const docId = `${trainerId}_${athleteId}_${periodKey}`;
    const docRef = db.collection("payments").doc(docId);

    try {
      await docRef.create({
        id: docId,
        trainerId,
        athleteId,
        amountArs: amountArs ?? 0,
        concept,
        status: "pending",
        periodKey,
        dueAt: admin.firestore.Timestamp.fromDate(dueAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      created++;
      logger.info("generateDuePayments: created pending payment", {
        docId,
        trainerId,
        athleteId,
        periodKey,
      });
    } catch (err: unknown) {
      // ALREADY_EXISTS: concurrent CF invocation won the race — treat as skip.
      const code = (err as { code?: string | number }).code;
      if (code === "ALREADY_EXISTS" || code === 6) {
        logger.info("generateDuePayments: concurrent race — doc already exists", {
          docId,
        });
        skipped++;
      } else {
        // Unexpected error: log and continue (don't abort the whole run).
        logger.error("generateDuePayments: unexpected error creating doc", {
          docId,
          err,
        });
        skipped++;
      }
    }
  }

  logger.info("generateDuePayments: run complete", {
    scanned,
    created,
    skipped,
  });

  return { created, skipped, scanned };
}

// ---------------------------------------------------------------------------
// onSchedule wrapper
// ---------------------------------------------------------------------------

/**
 * Scheduled Cloud Function — runs daily at 03:00 ART (America/Argentina/Buenos_Aires).
 * Deployed to southamerica-east1 (matches all other TREINO CFs).
 */
export const generateDuePayments = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const result = await generateDuePaymentsHandler(getApp(), new Date());
    logger.info("generateDuePayments: scheduled run done", result);
  },
);
