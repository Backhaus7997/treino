/**
 * reviewAggregate — Cloud Function for TREINO.
 *
 * Listens to writes on `reviews/{reviewId}` (create / update / delete) and
 * recomputes `averageRating + reviewCount` on the corresponding
 * `trainerPublicProfiles/{trainerId}` document.
 *
 * Design:
 *   - Runs in southamerica-east1 (matches deleteAccount — ADR-RV-003).
 *   - Idempotent: re-queries all reviews on every event (ADR-RV-001).
 *   - Error-safe: catches all exceptions, logs, never rethrows (prevents
 *     infinite retry storms on bad data — ADR-RV-001).
 *   - No-op + warning when trainerPublicProfiles doc is absent (ADR-RV-006).
 *
 * REQ-RV-CF-001..006. Fase 6 Etapa 7.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments).
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Recomputes aggregate stats for a trainer and persists them.
 *
 * Exported separately to enable direct unit/integration testing without
 * going through the trigger harness. Called by the trigger handler AND
 * by test suites.
 */
export async function recomputeAggregate(
  app: admin.app.App,
  trainerId: string,
): Promise<void> {
  const db = admin.firestore(app);

  try {
    // 1. Query all reviews for this trainer.
    const snap = await db
      .collection("reviews")
      .where("trainerId", "==", trainerId)
      .get();

    const count = snap.size;
    let update: { averageRating: number | null; reviewCount: number };

    if (count === 0) {
      // REQ-RV-CF-004: last review deleted → null + 0
      update = { averageRating: null, reviewCount: 0 };
    } else {
      const sumRatings = snap.docs.reduce((acc, doc) => {
        const rating = (doc.data().rating as number) ?? 0;
        return acc + rating;
      }, 0);
      update = {
        averageRating: sumRatings / count,
        reviewCount: count,
      };
    }

    // 2. Check profile exists before writing (REQ-RV-CF-006).
    const profileRef = db.collection("trainerPublicProfiles").doc(trainerId);
    const profileSnap = await profileRef.get();

    if (!profileSnap.exists) {
      logger.warn(
        `reviewAggregate: trainerPublicProfiles/${trainerId} not found — skipping update`,
        { trainerId },
      );
      return;
    }

    // 3. Merge aggregate fields — never overwrite identity fields.
    await profileRef.set(update, { merge: true });

    logger.info(
      `reviewAggregate: updated trainerPublicProfiles/${trainerId}`,
      { trainerId, ...update },
    );
  } catch (err) {
    // REQ-RV-CF-006: catch all → log + no rethrow
    logger.error(
      `reviewAggregate: error recomputing for trainerId=${trainerId}`,
      { trainerId, err },
    );
  }
}

/**
 * Cloud Function trigger.
 *
 * Deployed to southamerica-east1 per ADR-RV-003.
 * Fires on any write (create / update / delete) to `reviews/{reviewId}`.
 */
export const reviewAggregate = onDocumentWritten(
  { document: "reviews/{reviewId}", region: "southamerica-east1" },
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();

    // Extract trainerId from after (create/update) or before (delete).
    const trainerId =
      (after?.trainerId as string | undefined) ??
      (before?.trainerId as string | undefined);

    if (!trainerId) {
      logger.warn("reviewAggregate: trainerId not found in document", {
        reviewId: event.params.reviewId,
      });
      return;
    }

    await recomputeAggregate(getApp(), trainerId);
  },
);
