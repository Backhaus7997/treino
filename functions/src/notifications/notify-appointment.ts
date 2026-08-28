/**
 * notifyOnAppointment — Cloud Function for TREINO.
 *
 * Fires on writes to `appointments/{apptId}`.
 * Sends push notifications on appointment status changes.
 *
 * Design:
 *   - ADR-PN-006.
 *   - Guards: after missing → skip; el write ESCRIBIÓ `reason` =
 *     'athlete-account-deleted', o sea es el cascade de baja de cuenta (ver
 *     `isAthleteAccountDeletedWrite`) → skip; before?.status === after.status →
 *     skip (no-op write).
 *   - Branches:
 *       create + requested → notify trainer, deepLink "/coach?tab=agenda"
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
import { ATHLETE_ACCOUNT_DELETED_REASON } from "../cascade/appointments";
import { enqueueMail } from "../mail/enqueue-mail";
import {
  formatDateAR,
  formatTimeAR,
  resolveDisplayName,
  resolveTrainerName,
} from "../mail/format";
import { COACH_HUB_URL } from "../mail/templates";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type ApptData = Record<string, unknown>;

/**
 * ¿Este write es el cascade cancelando el turno de un atleta que se dio de baja?
 *
 * ─── #846 — el guard tiene que leer algo que el cliente NO pueda escribir ───
 *
 * Esto era `after.reason === 'athlete-account-deleted'` a secas, y esa parte
 * estaba bien: `reason` es una clave que sólo escribe el Admin SDK. Lo que la
 * volvía frágil era el otro lado —la clave estaba FUERA de `hasOnly()` en
 * `firestore.rules`, así que congelaba el turno—, y el primer intento de fix
 * movió el motivo adentro del `cancellationLog`.
 *
 * Eso ROMPÍA el guard, y no por descuido de tipos: las reglas **no iteran
 * listas**, o sea que el contenido de una entrada del log no se valida. Medido
 * de punta a punta: un atleta autenticado cancela SU turno por el Path 1
 * legítimo agregando `{byUid, atMs, reason: 'athlete-account-deleted'}` →
 * ALLOW, y este handler emitía CERO push y CERO mail. El PF nunca se enteraba
 * de que le cancelaron. Simétrico: el PF podía silenciar al atleta.
 *
 * Un guard es CONTROL DE FLUJO. Lo único que puede leer es una señal que el
 * cliente no pueda emitir. `reason` volvió a ser esa señal: `firestore.rules`
 * la pinea en los DOS caminos de update, la exige `null` en el `create` y el
 * `delete` está cerrado, así que ningún cliente la agrega, la cambia ni la
 * borra. El Admin SDK sí, porque saltea las reglas.
 *
 * ─── Y se mira la ESCRITURA, no el estado final ─────────────────────────────
 *
 * `before?.reason !== …` no es cosmético: el motivo queda guardado en el
 * documento para siempre, pero el write que lo puso ocurre UNA vez. Sin esa
 * mitad, cualquier cambio de estado POSTERIOR de un turno que el cascade ya
 * tocó quedaría mudo para siempre.
 */
function isAthleteAccountDeletedWrite(
  before: ApptData | undefined,
  after: ApptData,
): boolean {
  return (
    after.reason === ATHLETE_ACCOUNT_DELETED_REASON &&
    before?.reason !== ATHLETE_ACCOUNT_DELETED_REASON
  );
}

/**
 * Queues the email counterpart of an appointment push, when the branch has one.
 *
 * Email is NOT a mirror of push. Only two branches earn one:
 *   - `confirmed` → the athlete. A commitment with a date and a time, and it is
 *     new information: the athlete knows they asked, not that it was granted.
 *   - `cancelled` → the notified party. Losing a session you planned around.
 *
 * The `requested` branch is push-only. It targets the trainer, who lives in the
 * app all day and has the agenda in front of them.
 *
 * Dedupe scope is the `recurringId` when the occurrence belongs to a series.
 * `createRecurringByTrainer` commits the whole series in one WriteBatch, so a
 * three-month Mon/Wed/Fri booking fires this ~36 times; keyed on the series
 * they all resolve to one queue document and the athlete gets one mail.
 *
 * @param app     - Admin SDK app.
 * @param apptId  - Appointment document ID; the dedupe scope for a one-off.
 * @param after   - Snapshot data after the write.
 * @param status  - Resolved status branch.
 * @param toUids  - Recipients, as already resolved for the push.
 */
async function enqueueAppointmentMail(
  app: admin.app.App,
  apptId: string,
  after: ApptData,
  status: string,
  toUids: string[],
): Promise<void> {
  if (status !== "confirmed" && status !== "cancelled") return;

  const trainerId = after.trainerId as string;
  const recurringId = after.recurringId as string | undefined;
  const isSeries = typeof recurringId === "string" && recurringId.length > 0;
  const scope = isSeries ? recurringId : apptId;

  if (status === "confirmed") {
    const trainerName = await resolveTrainerName(app, trainerId);
    await enqueueMail(app, {
      toUid: after.athleteId as string,
      kind: isSeries ? "appointment-series-created" : "appointment-confirmed",
      scope,
      params: {
        trainerName,
        dateLabel: formatDateAR(after.startsAt as never),
        timeLabel: formatTimeAR(after.startsAt as never),
      },
    });
    return;
  }

  // cancelled — name the OTHER party for each recipient.
  const cancelledBy = after.cancelledBy as string | undefined;
  for (const toUid of toUids) {
    // Whoever cancelled is the actor; fall back to the counterpart of the
    // recipient when a legacy doc carries no `cancelledBy`.
    const otherUid =
      cancelledBy ?? (toUid === trainerId ? (after.athleteId as string) : trainerId);
    const otherName = await resolveDisplayName(app, otherUid, "la otra parte");

    await enqueueMail(app, {
      toUid,
      kind: isSeries ? "appointment-series-cancelled" : "appointment-cancelled",
      scope,
      params: {
        otherName,
        dateLabel: formatDateAR(after.startsAt as never),
        timeLabel: formatTimeAR(after.startsAt as never),
        // Mismo criterio que el prefKey: el Coach Hub solo para el PF. Al
        // atleta el dashboard del entrenador no le sirve de nada.
        ...(toUid === trainerId ? { ctaUrl: COACH_HUB_URL } : {}),
      },
      // Only the trainer has a settings screen (Coach Hub → Ajustes →
      // Notificaciones, row `sesion_cancelada`). Gating the ATHLETE's mail on a
      // preference they have no way to see would be an opt-out they cannot
      // reach, so for them this stays transactional.
      prefKey: toUid === trainerId ? "sesion_cancelada" : undefined,
    });
  }
}

/**
 * Pure handler extracted for jest testability.
 *
 * @param app       - Admin SDK app.
 * @param apptId    - Appointment document ID (event.params.apptId). Used as the
 *                    email dedupe scope for non-recurring occurrences.
 * @param before    - Snapshot data before the write (undefined for creates).
 * @param after     - Snapshot data after the write (undefined for deletes).
 * @param messaging - Optional messaging instance for test injection.
 */
export async function notifyOnAppointmentHandler(
  app: admin.app.App,
  apptId: string,
  before: ApptData | undefined,
  after: ApptData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  // Guard: document deleted — no notification.
  if (!after) {
    logger.info("notifyOnAppointment: after missing (delete event), skipping");
    return;
  }

  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: cascade delete — athlete account deleted.
  if (isAthleteAccountDeletedWrite(before, after)) {
    logger.info(
      `notifyOnAppointment: skipping cascade reason=${ATHLETE_ACCOUNT_DELETED_REASON}`,
    );
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
  let actorUid: string | undefined;

  if (afterStatus === "requested") {
    // New appointment request → notify trainer.
    recipientUids = [trainerId];
    actorUid = athleteId;
    title = "Nueva solicitud de sesión"; // i18n: Fase 6 Etapa 2
    body = "Un atleta solicitó una sesión contigo."; // i18n: Fase 6 Etapa 2
    // QA-NOT-002: "/coach/agenda" monta el host de ATLETA (resuelve el vínculo
    // atleta→PF); para el trainer eso mostraba "Necesitás un vínculo activo
    // con un PF". "/coach?tab=agenda" es role-aware (CoachScreen despacha a
    // TrainerCoachView con la tab AGENDA) — igual que confirmed/cancelled.
    deepLink = "/coach?tab=agenda";
  } else if (afterStatus === "confirmed") {
    // Appointment confirmed → notify athlete.
    recipientUids = [athleteId];
    actorUid = trainerId;
    title = "Sesión confirmada"; // i18n: Fase 6 Etapa 2
    body = "Tu entrenador confirmó la sesión."; // i18n: Fase 6 Etapa 2
    deepLink = "/coach?tab=agenda";
  } else if (afterStatus === "cancelled") {
    // Appointment cancelled.
    // `cancelledBy` DOES live on the schema — Appointment (appointment.dart)
    // declares it and AppointmentRepository.cancel / cancelFutureSeries both
    // write it. The both-parties fallback below now only covers documents
    // cancelled before that field shipped.
    const cancelledBy = after.cancelledBy as string | undefined;
    actorUid = cancelledBy;
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
      kind: "appointment",
      notification: { title, body },
      data: { deepLink },
      actorUid,
    },
    messaging,
  );

  // Email is a separate, best-effort effect: a queue failure must never take
  // the push down with it, mirroring how sendFcm isolates history from FCM.
  await enqueueAppointmentMail(app, apptId, after, afterStatus, recipientUids)
    .catch((error: unknown) => {
      logger.warn("notifyOnAppointment: mail enqueue failed", { apptId, error });
    });
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
    await notifyOnAppointmentHandler(getApp(), event.params.apptId, before, after);
  },
);
