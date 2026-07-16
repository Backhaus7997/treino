/**
 * Posts cascade module — deletes posts authored by the given uid.
 *
 * For each post where `authorUid == uid`, the document is permanently
 * deleted. Posts are flat documents with no subcollections and no
 * Storage-backed media fields, so deleting the document is sufficient —
 * there are no orphaned resources to chase.
 *
 * Behavior change: this step previously anonymized display fields
 * (authorDisplayName/authorAvatarUrl) instead of deleting the post. Per
 * updated product decision, posts are now deleted entirely.
 * Uses batched deletes in chunks of 400 (conservative below 500 limit).
 * Idempotent — running twice when no posts remain returns count 0.
 * REQ-ACCDEL-CF-006 | supersedes ADR-ACCDEL-004 (which anonymized posts;
 * product decision 2026-07-16 changed this to full deletion).
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 400;

/**
 * Deletes all posts authored by the given uid.
 * Returns the count of deleted documents.
 */
export async function deletePosts(
  app: admin.app.App,
  uid: string
): Promise<{ count: number }> {
  const db = admin.firestore(app);

  const snapshot = await db
    .collection("posts")
    .where("authorUid", "==", uid)
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  const docs = snapshot.docs;
  let deleted = 0;

  // Process in chunks of BATCH_SIZE
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
