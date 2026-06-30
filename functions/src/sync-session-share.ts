/**
 * syncSessionShareOnTrainerLink — Cloud Function for TREINO.
 *
 * Fires on writes to `trainer_links/{linkId}`. Keeps `session_shares/{athleteId}`
 * automatically in sync with the trainer link status — no manual toggle needed.
 *
 * Behaviour:
 *   - `after` exists AND `status === 'active'`
 *     → set `session_shares/{athleteId}` to `{ trainerId, updatedAt }`.
 *   - `after` absent (delete) OR `status !== 'active'`
 *     → read `session_shares/{athleteId}`; if it exists AND its trainerId matches
 *       the one from this link → delete it.
 *       If it points to a DIFFERENT trainer (e.g. a new link already wrote it),
 *       leave it untouched.
 *
 * Uses Admin SDK (bypasses Firestore security rules).
 *
 * Deployed to southamerica-east1 per ADR-PN-005.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Pure handler extracted for jest testability.
 *
 * @param app    - Admin SDK app.
 * @param before - Snapshot data before the write (undefined for creates).
 * @param after  - Snapshot data after the write (undefined for deletes).
 */
export async function syncSessionShareHandler(
  app: admin.app.App,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<void> {
  const db = admin.firestore(app);

  // Derive identity from whichever snapshot is present.
  const source = after ?? before;
  if (!source) {
    logger.warn("syncSessionShare: both before and after are missing — skipping");
    return;
  }

  const trainerId = source.trainerId as string | undefined;
  const athleteId = source.athleteId as string | undefined;
  const status = (after?.status as string | undefined) ?? "";

  if (!trainerId || !athleteId) {
    logger.warn("syncSessionShare: missing trainerId or athleteId", {
      trainerId,
      athleteId,
    });
    return;
  }

  const shareRef = db.collection("session_shares").doc(athleteId);

  if (after && status === "active") {
    // Link is (or became) active → ensure the share doc points to this trainer.
    await shareRef.set({
      trainerId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info("syncSessionShare: share granted", { trainerId, athleteId });
    return;
  }

  // Link deleted or no longer active → conditionally remove the share.
  const shareSnap = await shareRef.get();
  if (!shareSnap.exists) {
    // Nothing to clean up.
    return;
  }

  const existingTrainerId = shareSnap.data()?.trainerId as string | undefined;
  if (existingTrainerId !== trainerId) {
    // The share points to a different trainer (e.g. athlete re-linked to someone
    // else and that CF already wrote). Do NOT remove it.
    logger.info(
      "syncSessionShare: share belongs to a different trainer — skipping delete",
      { trainerId, athleteId, existingTrainerId },
    );
    return;
  }

  await shareRef.delete();
  logger.info("syncSessionShare: share revoked", { trainerId, athleteId });
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const syncSessionShareOnTrainerLink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await syncSessionShareHandler(getApp(), before, after);
  },
);
