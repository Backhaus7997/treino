/**
 * cleanupAssignedPlansOnUnlink — Cloud Function for TREINO.
 *
 * Fires on writes to `trainer_links/{linkId}`. When a link becomes
 * `terminated`, hard-deletes every plan the trainer had ASSIGNED to that
 * athlete, so the plans don't linger on the athlete after the relationship
 * ends.
 *
 * Why server-side: the Firestore client rule only lets the trainer
 * (`assignedBy`) delete `trainer-assigned` routines — the athlete cannot. Since
 * EITHER party can terminate the link, the cleanup must run with admin
 * privileges so it works regardless of who cut it, without widening the client
 * rule.
 *
 * Scope — deletes ONLY `source == 'trainer-assigned'` docs for the exact
 * (trainer, athlete) pair:
 *   - Trainer TEMPLATES (`trainer-template`, `assignedTo: null`) are NEVER
 *     touched — they are separate, reusable documents. A template assigned to a
 *     single athlete still survives the unlink; only the athlete's assigned
 *     COPY is removed.
 *   - The athlete's own routines (`user-created`) are untouched.
 *
 * Guards (mirrors notifyOnLinkChange):
 *   - after missing (delete event) → skip.
 *   - reason === 'account-deleted' → skip (the account-deletion cascade owns
 *     that flow; don't interfere).
 *   - before.status === after.status (no-op write) → skip.
 *   - after.status !== 'terminated' → skip.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

const BATCH_SIZE = 500;

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Hard-deletes every `trainer-assigned` routine for the (trainerId, athleteId)
 * pair. Pure + emulator-testable. Returns the count of deleted documents.
 *
 * Three equality filters need no composite index (Firestore serves equality-only
 * queries from automatic single-field indexes).
 */
export async function deleteAssignedPlansForPair(
  app: admin.app.App,
  trainerId: string,
  athleteId: string,
): Promise<{ count: number }> {
  const db = admin.firestore(app);

  const snapshot = await db
    .collection("routines")
    .where("assignedBy", "==", trainerId)
    .where("assignedTo", "==", athleteId)
    .where("source", "==", "trainer-assigned")
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  let deleted = 0;
  for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
    const chunk = snapshot.docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += chunk.length;
  }

  return { count: deleted };
}

/**
 * Pure handler extracted for jest testability.
 *
 * @param app    - Admin SDK app.
 * @param before - Snapshot data before the write (undefined for creates).
 * @param after  - Snapshot data after the write (undefined for deletes).
 */
export async function cleanupAssignedPlansOnUnlinkHandler(
  app: admin.app.App,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<{ count: number }> {
  // Guard: document deleted — nothing to clean from here.
  if (!after) {
    logger.info("cleanupAssignedPlans: after missing (delete event), skipping");
    return { count: 0 };
  }

  const reason = after.reason as string | undefined;
  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: account-deletion cascade owns its own cleanup — don't interfere.
  if (reason === "account-deleted") {
    logger.info("cleanupAssignedPlans: skipping cascade reason=account-deleted");
    return { count: 0 };
  }

  // Guard: no-op write — status unchanged.
  if (beforeStatus !== undefined && beforeStatus === afterStatus) {
    return { count: 0 };
  }

  // Only act when the link becomes terminated.
  if (afterStatus !== "terminated") {
    return { count: 0 };
  }

  if (!trainerId || !athleteId) {
    logger.warn("cleanupAssignedPlans: missing trainerId/athleteId", {
      trainerId,
      athleteId,
    });
    return { count: 0 };
  }

  const result = await deleteAssignedPlansForPair(app, trainerId, athleteId);
  logger.info("cleanupAssignedPlans: deleted assigned plans on unlink", {
    trainerId,
    athleteId,
    count: result.count,
  });
  return result;
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1 (matches the other
 * trainer_links triggers).
 */
export const cleanupAssignedPlansOnUnlink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await cleanupAssignedPlansOnUnlinkHandler(getApp(), before, after);
  },
);
