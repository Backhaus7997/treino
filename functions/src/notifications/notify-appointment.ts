/**
 * notifyOnAppointment — Cloud Function for TREINO.
 *
 * Fires on writes to `appointments/{apptId}`.
 * Sends push notifications on appointment status changes.
 *
 * Design:
 *   - ADR-PN-006.
 *   - Guards: after missing → skip; after.reason === 'athlete-account-deleted' → skip;
 *     before?.status === after.status → skip (no-op write).
 *   - Branches:
 *       create + requested → notify trainer, deepLink "/coach/agenda"
 *       requested → confirmed → notify athlete, deepLink "/coach?tab=agenda"
 *       * → cancelled → use after.cancelledBy if present, else notify both
 *   - All user-facing strings in es-AR.
 *
 * REQ-PN-CF-003. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type ApptData = Record<string, unknown>;

/**
 * Pure handler extracted for jest testability.
 *
 * @param app       - Admin SDK app.
 * @param before    - Snapshot data before the write (undefined for creates).
 * @param after     - Snapshot data after the write (undefined for deletes).
 * @param messaging - Optional messaging instance for test injection.
 */
export async function notifyOnAppointmentHandler(
  app: admin.app.App,
  before: ApptData | undefined,
  after: ApptData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  // Guard: document deleted — no notification.
  if (!after) {
    logger.info("notifyOnAppointment: after missing (delete event), skipping");
    return;
  }

  const reason = after.reason as string | undefined;
  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: cascade delete — athlete account deleted.
  if (reason === "athlete-account-deleted") {
    logger.info("notifyOnAppointment: skipping cascade reason=athlete-account-deleted");
    return;
  }

  // Guard: no-op write — status unchanged.
  if (beforeStatus !== undefined && beforeStatus === afterStatus) {
    logger.info("notifyOnAppointment: status unchanged, skipping", {
      status: afterStatus,
    });
    return;
  }

  if (!trainerId || !athleteId || !afterStatus) {
    logger.warn("notifyOnAppointment: missing required fields", {
      trainerId,
      athleteId,
      afterStatus,
    });
    return;
  }

  let recipientUids: string[];
  let title: string;
  let body: string;
  let deepLink: string;

  if (afterStatus === "requested") {
    // New appointment request → notify trainer.
    recipientUids = [trainerId];
    title = "Nueva solicitud de sesión"; // i18n: Fase 6 Etapa 2
    body = "Un atleta solicitó una sesión contigo."; // i18n: Fase 6 Etapa 2
    deepLink = "/coach/agenda";
  } else if (afterStatus === "confirmed") {
    // Appointment confirmed → notify athlete.
    recipientUids = [athleteId];
    title = "Sesión confirmada"; // i18n: Fase 6 Etapa 2
    body = "Tu entrenador confirmó la sesión."; // i18n: Fase 6 Etapa 2
    deepLink = "/coach?tab=agenda";
  } else if (afterStatus === "cancelled") {
    // Appointment cancelled.
    // TODO(cancelledBy): when `cancelledBy` field lands on the appointments schema,
    // notify only the OTHER party. For now, defaults to both.
    const cancelledBy = after.cancelledBy as string | undefined;
    if (cancelledBy) {
      // Notify the other party only.
      recipientUids = cancelledBy === trainerId ? [athleteId] : [trainerId];
    } else {
      // cancelledBy not yet in appointments schema — defaults to both.
      recipientUids = [athleteId, trainerId];
    }
    title = "Sesión cancelada"; // i18n: Fase 6 Etapa 2
    body = "Una sesión fue cancelada."; // i18n: Fase 6 Etapa 2
    deepLink = "/coach?tab=agenda";
  } else {
    logger.info("notifyOnAppointment: unhandled status transition, skipping", {
      beforeStatus,
      afterStatus,
    });
    return;
  }

  await sendFcm(
    app,
    {
      uids: recipientUids,
      notification: { title, body },
      data: { deepLink },
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-006.
 */
export const notifyOnAppointment = onDocumentWritten(
  { document: "appointments/{apptId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as ApptData | undefined;
    const after = event.data?.after?.data() as ApptData | undefined;
    await notifyOnAppointmentHandler(getApp(), before, after);
  },
);
