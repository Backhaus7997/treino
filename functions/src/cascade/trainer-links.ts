/**
 * Trainer links cascade module — terminates active trainer-athlete links.
 *
 * Queries `trainer_links` where `athleteId == uid` and updates each doc:
 *   - `status`       → 'terminated'
 *   - `reason`       → 'account-deleted'
 *   - `terminatedAt` → server timestamp
 *
 * Only non-terminated links are updated (idempotent — already-terminated
 * links are skipped by the query filter).
 * REQ-ACCDEL-CF-008 | ADR-ACCDEL-006
 */

import * as admin from "firebase-admin";
import { App } from "firebase-admin/app";
import { FieldValue } from "firebase-admin/firestore";

const BATCH_SIZE = 500;

/**
 * Terminates all non-terminated trainer links for the given athlete uid.
 * Returns the count of terminated documents.
 */
export async function terminateTrainerLinks(
  app: App,
  uid: string
): Promise<{ count: number }> {
  const db = admin.firestore(app);

  // Query only non-terminated links — already-terminated ones are left as-is
  const snapshot = await db
    .collection("trainer_links")
    .where("athleteId", "==", uid)
    .where("status", "!=", "terminated")
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  const docs = snapshot.docs;
  let updated = 0;

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const chunk = docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "terminated",
        reason: "account-deleted",
        terminatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    updated += chunk.length;
  }

  return { count: updated };
}
