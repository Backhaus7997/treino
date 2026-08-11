/**
 * notifyOnExerciseFeedback — Cloud Function for TREINO. Issue #628.
 *
 * Fires on new athlete-authored feedback in
 * `users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}`.
 *
 * Notifies the linked trainer ONLY for `kind: "discomfort"`. A plain comment
 * must not buzz the trainer's phone a dozen times per session — that is the
 * whole reason the two kinds exist as separate values.
 *
 * Why this matters enough to push: the athlete is mid-session. A joint issue
 * reported now, while there are still sets to go, is an injury the trainer can
 * help avoid. The same report read three days later is a post-mortem.
 *
 * Design:
 *   - Recipient is the trainer named in `session_shares/{uid}`. That doc is the
 *     same grant the Firestore rules use to let the trainer read the feedback,
 *     so if it is absent there is nobody who can read it and nobody to notify.
 *   - Athlete name from userPublicProfiles/{uid}.displayName ?? 'Tu alumno'.
 *   - Body: "${athleteName} — ${exerciseName}: ${text}" (text truncated at 100).
 *   - deepLink: "/coach/alumno/${uid}" (the trainer's athlete detail screen).
 *   - All user-facing strings in es-AR.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/** Truncates text to maxLen chars, appending '…' if truncated. */
function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return text.slice(0, maxLen) + "…";
}

/**
 * Pure handler extracted for jest testability (mirrors notifyOnChatMessage).
 *
 * @param app          - Admin SDK app.
 * @param athleteUid   - Owner of the session the feedback belongs to.
 * @param feedbackData - Raw feedback document data.
 * @param messaging    - Optional messaging instance for test injection.
 */
export async function notifyOnExerciseFeedbackHandler(
  app: admin.app.App,
  athleteUid: string,
  feedbackData: Record<string, unknown>,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  const db = admin.firestore(app);

  const kind = feedbackData.kind as string | undefined;

  // Comments are read when the trainer opens the session; only pain pushes.
  if (kind !== "discomfort") {
    logger.info("notifyOnExerciseFeedback: not a discomfort report, skipping", {
      athleteUid,
      kind,
    });
    return;
  }

  const exerciseName =
    (feedbackData.exerciseName as string | undefined) ?? "un ejercicio"; // i18n: es-AR
  const text = (feedbackData.text as string | undefined) ?? "";
  const setNumber = feedbackData.setNumber as number | undefined;

  // 1. Resolve the recipient from the privacy grant. No grant ⇒ the trainer
  //    cannot read the doc anyway (rules), so there is nobody to notify.
  const shareSnap = await db.collection("session_shares").doc(athleteUid).get();
  const trainerId = shareSnap.data()?.trainerId as string | undefined;

  if (!trainerId) {
    logger.info("notifyOnExerciseFeedback: no session_shares grant, skipping", {
      athleteUid,
    });
    return;
  }

  // 2. Athlete display name.
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(athleteUid)
    .get();
  const athleteName =
    (profileSnap.data()?.displayName as string | undefined) ?? "Tu alumno"; // i18n: es-AR

  // 3. Build the body. The exercise — and the set when there is one — is the
  //    part the chat could never carry, so it goes in the push itself.
  const where =
    typeof setNumber === "number"
      ? `${exerciseName} (serie ${setNumber})` // i18n: es-AR
      : exerciseName;
  const detail = text.length > 0 ? `: ${truncate(text, 100)}` : "";
  const body = `${athleteName} reportó una molestia en ${where}${detail}`; // i18n: es-AR

  // 4. Dispatch.
  await sendFcm(
    app,
    {
      uids: [trainerId],
      kind: "exercise-discomfort",
      notification: {
        title: "TREINO", // i18n: es-AR
        body,
      },
      data: { deepLink: `/coach/alumno/${athleteUid}`, athleteUid },
      actorUid: athleteUid,
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1, same region as the other notifications.
 */
export const notifyOnExerciseFeedback = onDocumentCreated(
  {
    document: "users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const feedbackData = event.data?.data() as
      | Record<string, unknown>
      | undefined;
    if (!feedbackData) {
      logger.warn("notifyOnExerciseFeedback: no feedback data");
      return;
    }

    const { uid } = event.params;
    await notifyOnExerciseFeedbackHandler(getApp(), uid, feedbackData);
  },
);
