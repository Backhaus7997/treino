/**
 * notifyOverduePayments — Cloud Function for TREINO.
 *
 * Runs on a daily cron schedule at 10:00 ART. For every active
 * trainer↔athlete link, queries overdue pending payments
 * (dueAt <= now, status == 'pending') and sends an FCM push notification
 * to the athlete if the anti-spam threshold has elapsed (7 days since
 * lastOverdueNotifiedAt).
 *
 * Why 10:00 ART:
 *   - generateDuePayments runs at 03:00 ART, so new overdue docs are
 *     already available by 10:00.
 *   - 10:00 is within respectful hours for a push notification.
 *
 * Algorithm — Approach B (per-link):
 *   1. Fetch active trainer_links.
 *   2. Per link, query payments where trainerId=X && athleteId=Y &&
 *      status=pending && dueAt<=now — REQUIRES the composite index
 *      (trainerId, athleteId, status, dueAt) in firestore.indexes.json
 *      (3 equality + 1 range; the Firestore emulator does NOT enforce it,
 *      so jest passing does NOT prove the index exists).
 *   3. For each overdue payment, apply anti-spam check.
 *   4. If notifying: resolve trainer displayName, call sendFcm, update
 *      lastOverdueNotifiedAt via Admin SDK (bypasses Firestore rules).
 *
 * Deployed to southamerica-east1 (matches all other TREINO CFs).
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { sendFcm } from "../notifications/send-fcm";

// ---------------------------------------------------------------------------
// Lazy app singleton (project convention — mirrors generate-due-payments.ts)
// ---------------------------------------------------------------------------

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Anti-spam threshold: 7 days in milliseconds. */
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

export interface NotifyOverdueResult {
  notified: number;
  skipped: number;
  scanned: number;
}

// ---------------------------------------------------------------------------
// Pure handler — emulator-testable, `now` and `messaging` injected
// ---------------------------------------------------------------------------

/**
 * Sends FCM reminders for overdue pending payments.
 *
 * @param app       - Admin SDK app instance.
 * @param now       - The reference timestamp (injected for testability;
 *                    production passes `new Date()`).
 * @param messaging - Optional messaging instance; injected in tests to avoid
 *                    real FCM calls (same pattern as sendFcm supports).
 * @returns Counts of notified, skipped, and scanned payment docs.
 */
export async function notifyOverduePaymentsHandler(
  app: admin.app.App,
  now: Date,
  messaging?: admin.messaging.Messaging,
): Promise<NotifyOverdueResult> {
  const db = admin.firestore(app);

  let notified = 0;
  let skipped = 0;
  let scanned = 0;

  const antiSpamCutoff = new Date(now.getTime() - SEVEN_DAYS_MS);

  // ── 1. Fetch all active trainer links ──────────────────────────────────────
  const linksSnap = await db
    .collection("trainer_links")
    .where("status", "==", "active")
    .get();

  if (linksSnap.empty) {
    logger.info("notifyOverduePayments: no active links found");
    return { notified, skipped, scanned };
  }

  logger.info("notifyOverduePayments: starting run", {
    now: now.toISOString(),
    linksCount: linksSnap.size,
  });

  // ── 2. Per-link processing ─────────────────────────────────────────────────
  for (const linkDoc of linksSnap.docs) {
    const link = linkDoc.data() as Record<string, unknown>;
    const trainerId = link.trainerId as string | undefined;
    const athleteId = link.athleteId as string | undefined;

    if (!trainerId || !athleteId) {
      logger.warn("notifyOverduePayments: link missing trainerId/athleteId", {
        linkId: linkDoc.id,
      });
      continue;
    }

    // ── 2a. Query overdue pending payments for this link ──────────────────
    // Requires composite index (trainerId, athleteId, status, dueAt) — firestore.indexes.json.
    const overdueSnap = await db
      .collection("payments")
      .where("trainerId", "==", trainerId)
      .where("athleteId", "==", athleteId)
      .where("status", "==", "pending")
      .where("dueAt", "<=", admin.firestore.Timestamp.fromDate(now))
      .get();

    if (overdueSnap.empty) {
      continue;
    }

    // ── 2b. Resolve trainer display name (one read per link, not per payment) ─
    const profileSnap = await db
      .collection("userPublicProfiles")
      .doc(trainerId)
      .get();
    const trainerName: string =
      (profileSnap.data()?.displayName as string | undefined) ??
      "tu entrenador";

    // ── 2c. Per-payment anti-spam check and notification ───────────────────
    for (const paymentDoc of overdueSnap.docs) {
      scanned++;

      const payment = paymentDoc.data() as Record<string, unknown>;

      // Guard: skip legacy payments without dueAt (Firestore excludes them
      // from the query already, but be explicit for type safety).
      if (!payment.dueAt) {
        logger.info("notifyOverduePayments: legacy payment without dueAt — skipping", {
          paymentId: paymentDoc.id,
        });
        skipped++;
        continue;
      }

      // Anti-spam: skip if notified within the last 7 days.
      const lastNotified = payment.lastOverdueNotifiedAt as
        | admin.firestore.Timestamp
        | null
        | undefined;

      if (lastNotified != null) {
        const lastNotifiedDate = lastNotified.toDate();
        if (lastNotifiedDate >= antiSpamCutoff) {
          logger.info(
            "notifyOverduePayments: anti-spam threshold not elapsed — skipping",
            {
              paymentId: paymentDoc.id,
              lastNotifiedDate: lastNotifiedDate.toISOString(),
            },
          );
          skipped++;
          continue;
        }
      }

      // ── Send FCM push to athlete ─────────────────────────────────────────
      await sendFcm(
        app,
        {
          uids: [athleteId],
          notification: {
            title: "Pago pendiente",
            body: `Tenés un pago vencido con ${trainerName}. Regularizalo cuando puedas.`,
          },
          data: {
            deepLink: "/coach?tab=pagos",
            trainerId,
            paymentId: paymentDoc.id,
          },
        },
        messaging,
      );

      // ── Write lastOverdueNotifiedAt via Admin SDK (bypasses Firestore rules) ─
      await paymentDoc.ref.update({
        lastOverdueNotifiedAt: admin.firestore.Timestamp.fromDate(now),
      });

      notified++;
      logger.info("notifyOverduePayments: notified athlete for payment", {
        paymentId: paymentDoc.id,
        trainerId,
        athleteId,
      });
    }
  }

  logger.info("notifyOverduePayments: run complete", {
    scanned,
    notified,
    skipped,
  });

  return { notified, skipped, scanned };
}

// ---------------------------------------------------------------------------
// onSchedule wrapper
// ---------------------------------------------------------------------------

/**
 * Scheduled Cloud Function — runs daily at 10:00 ART (America/Argentina/Buenos_Aires).
 * Deployed to southamerica-east1 (matches all other TREINO CFs).
 */
export const notifyOverduePayments = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const result = await notifyOverduePaymentsHandler(getApp(), new Date());
    logger.info("notifyOverduePayments: scheduled run done", result);
  },
);
