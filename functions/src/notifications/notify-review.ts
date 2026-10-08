/**
 * notifyOnReview — Cloud Function for TREINO.
 *
 * Fires on new documents in `reviews/{reviewId}`.
 * Notifies the trainer when an athlete leaves a review.
 *
 * Design:
 *   - ADR-PN-008: onDocumentCreated only — avoids re-notifying on edits.
 *   - Body: "${athleteName} dejó una reseña de ${rating}⭐".
 *   - deepLink: "/coach/trainer/${trainerId}".
 *   - All user-facing strings in es-AR.
 *
 * REQ-PN-CF-005. Fase 6 Etapa 2.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Messaging } from "firebase-admin/messaging";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

type ReviewData = Record<string, unknown>;

/**
 * Pure handler extracted for jest testability.
 *
 * @param app        - Admin SDK app.
 * @param reviewData - Raw review document data.
 * @param messaging  - Optional messaging instance for test injection.
 */
export async function notifyOnReviewHandler(
  app: App,
  reviewData: ReviewData,
  messaging?: Messaging,
): Promise<void> {
  const db = getFirestore(app);

  const trainerId = reviewData.trainerId as string | undefined;
  const athleteId = reviewData.athleteId as string | undefined;
  const rating = reviewData.rating as number | undefined;

  if (!trainerId || !athleteId || rating === undefined) {
    logger.warn("notifyOnReview: missing required fields", {
      trainerId,
      athleteId,
      rating,
    });
    return;
  }

  // Read athlete display name from userPublicProfiles.
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(athleteId)
    .get();
  const athleteName: string =
    (profileSnap.data()?.displayName as string | undefined) ?? "Un atleta"; // i18n: Fase 6 Etapa 2

  const body = `${athleteName} dejó una reseña de ${rating}⭐`; // i18n: Fase 6 Etapa 2
  const deepLink = `/coach/trainer/${trainerId}`;

  await sendFcm(
    app,
    {
      uids: [trainerId],
      kind: "review",
      notification: {
        title: "Nueva reseña", // i18n: Fase 6 Etapa 2
        body,
      },
      data: { deepLink },
      actorUid: athleteId,
      prefKey: "resena_nueva",
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-008.
 */
export const notifyOnReview = onDocumentCreated(
  { document: "reviews/{reviewId}", region: "southamerica-east1" },
  async (event) => {
    const reviewData = event.data?.data() as ReviewData | undefined;
    if (!reviewData) {
      logger.warn("notifyOnReview: no review data");
      return;
    }

    await notifyOnReviewHandler(ensureApp(), reviewData);
  },
);
