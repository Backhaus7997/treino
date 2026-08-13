/**
 * linkAggregate — Cloud Function for TREINO.
 *
 * Listens to writes on `trainer_links/{linkId}` (create / update / delete) and
 * recomputes the denormalized `athleteCount` on the corresponding
 * `trainerPublicProfiles/{trainerId}` document (#388).
 *
 * Why denormalized: firestore.rules restrict `trainer_links` reads to the
 * link's members, so an athlete browsing coach discovery can NEVER query or
 * count another trainer's links client-side. The public profile stats row
 * therefore reads `athleteCount` straight from `trainerPublicProfiles`, which
 * any authenticated user can read — same rationale as the reviewAggregate
 * `averageRating`/`reviewCount` pair (ADR-RV-004).
 *
 * Design (mirrors review-aggregate.ts):
 *   - Runs in southamerica-east1 (matches the other trainer_links triggers).
 *   - Idempotent: re-queries all links on every event and recomputes from
 *     scratch — no increments, no drift.
 *   - Error-safe: catches all exceptions, logs, never rethrows (prevents
 *     infinite retry storms on bad data).
 *   - No-op + warning when the trainerPublicProfiles doc is absent.
 *   - CF-write-only field: firestore.rules pin `athleteCount` on
 *     trainerPublicProfiles create/update, and the field MUST NOT appear in
 *     UserRepository._trainerPublicFields (same contract as ADR-RV-005).
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
 * Computes a trainer's public student count from raw trainer_links rows:
 * DISTINCT athletes whose link status is exactly `active`.
 *
 * Deduped by athleteId defensively (one person = one student) — the product
 * invariant is at most one non-terminated link per trainer-athlete pair, but
 * a malformed/duplicated doc must never inflate the discovery sales surface.
 * `docId` is the fallback dedup key for any legacy doc missing `athleteId`,
 * so a genuinely active link is never dropped.
 *
 * Pure (no Firestore access) so it is unit-testable without the emulator.
 */
export function athleteCountFromLinks(
  links: {
    docId: string;
    athleteId?: string;
    status?: string;
  }[],
): number {
  const activeAthletes = new Set<string>();
  for (const link of links) {
    if (link.status !== "active") continue;
    activeAthletes.add(link.athleteId ?? link.docId);
  }
  return activeAthletes.size;
}

/**
 * Recomputes `athleteCount` for a trainer and persists it.
 *
 * Exported separately to enable direct unit/integration testing without
 * going through the trigger harness. Called by the trigger handler AND
 * by test suites.
 */
export async function recomputeAthleteCount(
  app: admin.app.App,
  trainerId: string,
): Promise<void> {
  const db = admin.firestore(app);

  try {
    // 1. Query ALL links for this trainer; the pure helper filters `active`.
    //    (Single equality filter — no composite index required.)
    const snap = await db
      .collection("trainer_links")
      .where("trainerId", "==", trainerId)
      .get();

    const athleteCount = athleteCountFromLinks(
      snap.docs.map((doc) => ({
        docId: doc.id,
        athleteId: doc.data().athleteId as string | undefined,
        status: doc.data().status as string | undefined,
      })),
    );

    // 2. Check profile exists before writing (mirrors REQ-RV-CF-006).
    const profileRef = db.collection("trainerPublicProfiles").doc(trainerId);
    const profileSnap = await profileRef.get();

    if (!profileSnap.exists) {
      logger.warn(
        `linkAggregate: trainerPublicProfiles/${trainerId} not found — skipping update`,
        { trainerId },
      );
      return;
    }

    // 3. Merge the aggregate field — never overwrite identity fields.
    await profileRef.set({ athleteCount }, { merge: true });

    logger.info(`linkAggregate: updated trainerPublicProfiles/${trainerId}`, {
      trainerId,
      athleteCount,
    });
  } catch (err) {
    // Catch all → log + no rethrow (mirrors reviewAggregate).
    logger.error(
      `linkAggregate: error recomputing for trainerId=${trainerId}`,
      { trainerId, err },
    );
  }
}

/**
 * Cloud Function trigger.
 *
 * Deployed to southamerica-east1, matching the other `trainer_links` triggers
 * (notifyOnLinkChange, cleanupAssignedPlansOnUnlink, syncSessionShare).
 * Fires on any write (create / update / delete) to `trainer_links/{linkId}`.
 */
export const linkAggregate = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();

    // Extract trainerId from after (create/update) or before (delete).
    const trainerId =
      (after?.trainerId as string | undefined) ??
      (before?.trainerId as string | undefined);

    if (!trainerId) {
      logger.warn("linkAggregate: trainerId not found in document", {
        linkId: event.params.linkId,
      });
      return;
    }

    await recomputeAthleteCount(getApp(), trainerId);
  },
);
