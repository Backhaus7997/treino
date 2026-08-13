/**
 * templateRatingAggregate — Cloud Function for TREINO.
 *
 * Listens to writes on `routines/{routineId}/ratings/{userId}` (create /
 * update / delete) and recomputes `ratingAvg + ratingsCount` on the parent
 * `routines/{routineId}` document. Fase W3 (template publishing).
 *
 * Design (mirrors reviewAggregate — ADR-RV-001..006 lineage):
 *   - Runs in southamerica-east1 (matches every other TREINO CF).
 *   - Idempotent: re-queries ALL ratings on every event, never trusts the
 *     previous aggregate value.
 *   - Error-safe: catches everything, logs, never rethrows (prevents retry
 *     storms on bad data).
 *   - Existence check + update() instead of set(merge) — a rating event
 *     racing a routine deletion must NOT resurrect the routine as a stub
 *     doc (same reasoning as rankingAggregate, QA-507).
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
 * Computes the aggregate from raw rating rows.
 *
 * Doc ids are rater uids, so one doc per user is guaranteed by construction
 * — no dedup needed (unlike aggregateFromReviews). Rows whose `rating` is
 * not a 1..5 number are skipped defensively: the rules make them impossible
 * from the client, but Admin SDK or legacy writes could still produce
 * garbage, and one bad doc must not poison the whole aggregate.
 *
 * Pure (no Firestore access) so it is unit-testable without the emulator.
 */
export function aggregateFromRatings(ratings: { rating?: unknown }[]): {
  ratingAvg: number | null;
  ratingsCount: number;
} {
  const valid = ratings
    .map((r) => r.rating)
    .filter((r): r is number => typeof r === "number" && r >= 1 && r <= 5);
  if (valid.length === 0) {
    // No ratings → null + 0, mirroring reviewAggregate's empty shape.
    return { ratingAvg: null, ratingsCount: 0 };
  }
  const sum = valid.reduce((acc, r) => acc + r, 0);
  return { ratingAvg: sum / valid.length, ratingsCount: valid.length };
}

/**
 * Recomputes the rating aggregate for one routine and persists it.
 *
 * Exported separately to enable direct integration testing against the
 * emulator without going through the CloudEvent trigger harness. Called by
 * the trigger handler AND by test suites.
 */
export async function recomputeTemplateRating(
  app: admin.app.App,
  routineId: string,
): Promise<void> {
  const db = admin.firestore(app);

  try {
    // 1. Query all ratings for this routine.
    const snap = await db
      .collection("routines")
      .doc(routineId)
      .collection("ratings")
      .get();

    const update = aggregateFromRatings(
      snap.docs.map((doc) => ({ rating: doc.data().rating })),
    );

    // 2. Check the routine still exists before writing. Ratings survive a
    // routine deletion as orphaned subcollection docs (Firestore never
    // cascades), and a late event for one of them must be a no-op.
    const routineRef = db.collection("routines").doc(routineId);
    const routineSnap = await routineRef.get();

    if (!routineSnap.exists) {
      logger.warn(
        `templateRatingAggregate: routines/${routineId} not found — skipping update`,
        { routineId },
      );
      return;
    }

    // 3. update() — NOT set(merge) — so the existence check above cannot be
    // raced into resurrecting a just-deleted routine as a stub (QA-507).
    await routineRef.update(update);

    logger.info(`templateRatingAggregate: updated routines/${routineId}`, {
      routineId,
      ...update,
    });
  } catch (err) {
    // Catch all → log + no rethrow.
    logger.error(
      `templateRatingAggregate: error recomputing for routineId=${routineId}`,
      { routineId, err },
    );
  }
}

/**
 * Cloud Function trigger.
 *
 * Deployed to southamerica-east1. Fires on any write (create / update /
 * delete) to `routines/{routineId}/ratings/{userId}`.
 */
export const templateRatingAggregate = onDocumentWritten(
  {
    document: "routines/{routineId}/ratings/{userId}",
    region: "southamerica-east1",
  },
  async (event) => {
    await recomputeTemplateRating(getApp(), event.params.routineId);
  },
);
