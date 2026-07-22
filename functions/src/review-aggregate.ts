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
 * Milliseconds for an `updatedAt`-style field that may be a Firestore
 * Timestamp, a raw number, or missing. Used only to pick the most recent
 * review per athlete when deduping (QA-REV-002).
 */
function toMillis(value: unknown): number {
  if (
    value &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  if (typeof value === "number") return value;
  return 0;
}

/**
 * QA-REV-002: compute a trainer's public review aggregate from raw review rows,
 * deduped to one review per athlete (the most recent by `updatedAt`).
 *
 * The review doc id is `${linkId}_${athleteId}`, so an athlete who ends a link
 * and re-links produces a SECOND review doc — without deduping, both would
 * count toward averageRating/reviewCount, letting a single person inflate a
 * trainer's rating just by relinking. `docId` is the fallback dedup key for any
 * legacy/malformed doc missing `athleteId`, so a review is never dropped.
 *
 * Pure (no Firestore access) so it is unit-testable without the emulator.
 */
export function aggregateFromReviews(
  reviews: {
    docId: string;
    athleteId?: string;
    rating?: number;
    updatedAt?: unknown;
  }[],
): { averageRating: number | null; reviewCount: number } {
  const latestByAthlete = new Map<
    string,
    { rating: number; updatedAtMs: number }
  >();
  for (const review of reviews) {
    const key = review.athleteId ?? review.docId;
    const updatedAtMs = toMillis(review.updatedAt);
    const existing = latestByAthlete.get(key);
    if (!existing || updatedAtMs >= existing.updatedAtMs) {
      latestByAthlete.set(key, { rating: review.rating ?? 0, updatedAtMs });
    }
  }

  const ratings = [...latestByAthlete.values()].map((v) => v.rating);
  if (ratings.length === 0) {
    // REQ-RV-CF-004: no reviews → null + 0.
    return { averageRating: null, reviewCount: 0 };
  }
  const sum = ratings.reduce((acc, r) => acc + r, 0);
  return { averageRating: sum / ratings.length, reviewCount: ratings.length };
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

    // QA-REV-002: dedupe by athleteId — "una persona = una opinión". A relink
    // mints a new `${linkId}_${athleteId}` doc that would otherwise inflate the
    // aggregate; aggregateFromReviews collapses to the latest review per athlete.
    const update = aggregateFromReviews(
      snap.docs.map((doc) => ({
        docId: doc.id,
        athleteId: doc.data().athleteId as string | undefined,
        rating: doc.data().rating as number | undefined,
        updatedAt: doc.data().updatedAt,
      })),
    );

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
