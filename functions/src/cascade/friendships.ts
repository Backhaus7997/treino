/**
 * Friendships cascade module — sweeps all friendship documents.
 *
 * Deletes all `friendships/*` docs where `members` array contains `uid`.
 * Uses batched deletes in chunks of 500 for scale.
 *
 * Idempotent — safe to call when no friendships exist.
 * REQ-ACCDEL-CF-005 | ADR-ACCDEL-001
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 500;

/**
 * Deletes all friendship documents where the given uid appears in `members`.
 * Returns the count of deleted documents.
 */
export async function sweepFriendships(
  app: admin.app.App,
  uid: string
): Promise<{ count: number }> {
  const db = admin.firestore(app);

  const snapshot = await db
    .collection("friendships")
    .where("members", "array-contains", uid)
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  const docs = snapshot.docs;
  let deleted = 0;

  // Process in chunks of BATCH_SIZE (Firestore batch limit is 500 writes)
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const chunk = docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += chunk.length;
  }

  return { count: deleted };
}
