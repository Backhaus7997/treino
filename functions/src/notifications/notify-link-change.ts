/**
 * notifyOnLinkChange — Cloud Function for TREINO.
 *
 * Fires on writes to `trainer_links/{linkId}`.
 * Sends push notifications on trainer_link status changes.
 *
 * Design:
 *   - ADR-PN-007.
 *   - Guards: after missing → skip; after.reason === 'account-deleted' → skip;
 *     before?.status === after.status → skip (no-op write).
 *   - Branches:
 *       create + pending → notify trainer, deepLink "/coach"
 *       pending → active → notify athlete (aceptada), deepLink "/coach"
 *       active → paused → notify athlete (pausada), deepLink "/coach"
 *       paused → active → notify athlete (reanudada), deepLink "/coach"
 *       * → terminated → notify BOTH, deepLink "/coach"
 *   - All user-facing strings in es-AR.
 *
 * REQ-PN-CF-004. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";
import { enqueueMail } from "../mail/enqueue-mail";
import { resolveAthleteName, resolveTrainerName } from "../mail/format";
import { trainerEntry } from "../mail/templates";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Queues the email counterpart of a link push, when the branch has one.
 *
 * Only the two branches where somebody stands to LOSE something get a mail:
 *   - `pending` → the trainer. An unseen request is a lost athlete.
 *   - `pending` → `active` → the athlete. Their request was granted.
 *
 * `paused` → `active` is a resume, not an acceptance, and gets no mail. Neither
 * do `paused` and `terminated`: nothing is waiting on the recipient.
 *
 * Scope is the link id, so a pair that terminates and links again later still
 * receives a fresh mail rather than colliding with the first one.
 *
 * @param app          - Admin SDK app.
 * @param linkId       - trainer_links document ID; the dedupe scope.
 * @param after        - Snapshot data after the write.
 * @param afterStatus  - Resolved status branch.
 * @param beforeStatus - Previous status, to tell accept apart from resume.
 */
async function enqueueLinkMail(
  app: admin.app.App,
  linkId: string,
  after: LinkData,
  afterStatus: string,
  beforeStatus: string | undefined,
): Promise<void> {
  const trainerId = after.trainerId as string;
  const athleteId = after.athleteId as string;

  if (afterStatus === "pending") {
    const athleteName = await resolveAthleteName(app, athleteId);
    await enqueueMail(app, {
      toUid: trainerId,
      kind: "link-requested",
      scope: linkId,
      // El destinatario es el PF, asi que el CTA va al Coach Hub. El default
      // (la landing) es para los mails que reciben ATLETAS.
      //
      // `to: "solicitudes"`: no hay una pantalla propia en mobile (las
      // pendientes viven en un bottom sheet, #393) asi que ahi cae en
      // `/coach` a secas, pero en el Hub web SI hay `/invitaciones`.
      params: { athleteName, ctaUrl: trainerEntry({ to: "solicitudes" }) },
      // The recipient is always the trainer, who HAS a settings screen for
      // this row (kNotifTypes `nueva_solicitud`). Honour their toggle.
      prefKey: "nueva_solicitud",
    });
    return;
  }

  // Acceptance only — a resume (paused → active) is not news worth a mail.
  if (afterStatus === "active" && beforeStatus !== "paused") {
    const trainerName = await resolveTrainerName(app, trainerId);
    await enqueueMail(app, {
      toUid: athleteId,
      kind: "link-accepted",
      scope: linkId,
      params: { trainerName },
    });
  }
}

/**
 * Pure handler extracted for jest testability.
 *
 * @param app       - Admin SDK app.
 * @param linkId    - trainer_links document ID (event.params.linkId). Used as
 *                    the email dedupe scope.
 * @param before    - Snapshot data before the write (undefined for creates).
 * @param after     - Snapshot data after the write (undefined for deletes).
 * @param messaging - Optional messaging instance for test injection.
 */
export async function notifyOnLinkChangeHandler(
  app: admin.app.App,
  linkId: string,
  before: LinkData | undefined,
  after: LinkData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  // Guard: document deleted — no notification.
  if (!after) {
    logger.info("notifyOnLinkChange: after missing (delete event), skipping");
    return;
  }

  const reason = after.reason as string | undefined;
  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: cascade delete — account deleted.
  if (reason === "account-deleted") {
    logger.info("notifyOnLinkChange: skipping cascade reason=account-deleted");
    return;
  }

  // Guard: no-op write — status unchanged.
  if (beforeStatus !== undefined && beforeStatus === afterStatus) {
    logger.info("notifyOnLinkChange: status unchanged, skipping", {
      status: afterStatus,
    });
    return;
  }

  if (!trainerId || !athleteId || !afterStatus) {
    logger.warn("notifyOnLinkChange: missing required fields", {
      trainerId,
      athleteId,
      afterStatus,
    });
    return;
  }

  const deepLink = "/coach"; // i18n: Fase 6 Etapa 2 (deepLink is not user-facing copy)
  let recipientUids: string[];
  let title: string;
  let body: string;
  let actorUid: string | undefined;

  if (afterStatus === "pending") {
    // New link request → notify trainer.
    recipientUids = [trainerId];
    actorUid = athleteId;
    title = "Nueva solicitud de vinculación"; // i18n: Fase 6 Etapa 2
    body = "Un atleta quiere vincularse contigo."; // i18n: Fase 6 Etapa 2
  } else if (afterStatus === "active") {
    // pending → active = accept; paused → active = resume.
    recipientUids = [athleteId];
    actorUid = trainerId;
    if (beforeStatus === "paused") {
      title = "Vinculación reanudada"; // i18n: Fase 6 Etapa 3
      body = "Tu PF reanudó el vínculo."; // i18n: Fase 6 Etapa 3
    } else {
      title = "¡Vinculación aceptada!"; // i18n: Fase 6 Etapa 2
      body = "Tu entrenador aceptó la vinculación."; // i18n: Fase 6 Etapa 2
    }
  } else if (afterStatus === "paused") {
    // active → paused → notify athlete.
    recipientUids = [athleteId];
    actorUid = trainerId;
    title = "Vinculación pausada"; // i18n: Fase 6 Etapa 3
    body = "Tu PF pausó el vínculo."; // i18n: Fase 6 Etapa 3
  } else if (afterStatus === "terminated") {
    // Link terminated → notify BOTH (ADR-PN-007, locked decision #2).
    recipientUids = [athleteId, trainerId];
    title = "Vinculación finalizada"; // i18n: Fase 6 Etapa 2
    body = "La vinculación entre atleta y entrenador fue finalizada."; // i18n: Fase 6 Etapa 2
  } else {
    logger.info("notifyOnLinkChange: unhandled status transition, skipping", {
      beforeStatus,
      afterStatus,
    });
    return;
  }

  await sendFcm(
    app,
    {
      uids: recipientUids,
      kind: "link-change",
      notification: { title, body },
      data: { deepLink },
      actorUid,
    },
    messaging,
  );

  // Best-effort: a queue failure must never take the push down with it.
  await enqueueLinkMail(app, linkId, after, afterStatus, beforeStatus)
    .catch((error: unknown) => {
      logger.warn("notifyOnLinkChange: mail enqueue failed", { linkId, error });
    });
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-007.
 */
export const notifyOnLinkChange = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await notifyOnLinkChangeHandler(getApp(), event.params.linkId, before, after);
  },
);
