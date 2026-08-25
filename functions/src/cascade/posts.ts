/**
 * Posts cascade module — deletes posts authored by the given uid.
 *
 * For each post where `authorUid == uid`, the document **and every
 * sub-collection under it** are permanently deleted via `recursiveDelete`.
 *
 * QA-CMP-005b / QA-CMP-004b — this header used to claim that "posts are flat
 * documents with no subcollections and no Storage-backed media fields, so
 * deleting the document is sufficient". That was true when it was written and
 * BOTH halves are false today. The stale comment is what let two deletion
 * holes through review, so it is spelled out here:
 *
 *  - `posts` DOES have a sub-collection: `posts/{postId}/reactions/{reactorUid}`
 *    (firestore.rules:693). In Firestore, deleting a document does NOT delete
 *    its sub-collections — so the previous `batch.delete(doc.ref)` left every
 *    reaction that OTHER people had left on this user's posts as an orphan
 *    document whose doc id is a third party's uid. Nobody noticed because the
 *    orphans are unreadable from the client (`reactionPostReadable()` does a
 *    `get()` on the now-missing post and the rule evaluation fails → deny),
 *    but unreadable is not deleted: the personal data stayed in the database
 *    with no deletion path that would ever reach it.
 *
 *  - `posts` DOES have a Storage-backed media field: `photoUrl`
 *    (firestore.rules:638 and :675) points at `postPhotos/{uid}/{postId}.{ext}`
 *    (`post_photo_upload_service.dart`). Deleting the document does not touch
 *    the object. That half is fixed in `cascade/storage.ts` →
 *    `deleteAthleteStorage`, which now sweeps the `postPhotos/{uid}/` prefix.
 *
 * `recursiveDelete` replaces the manual 400-doc batching: the Admin SDK
 * BulkWriter batches and rate-limits internally, and one writer is shared
 * across every post so the whole cascade still goes out as batched writes.
 *
 * Behavior change: this step previously anonymized display fields
 * (authorDisplayName/authorAvatarUrl) instead of deleting the post. Per
 * updated product decision, posts are now deleted entirely.
 * Idempotent — running twice when no posts remain returns count 0.
 * REQ-ACCDEL-CF-006 | supersedes ADR-ACCDEL-004 (which anonymized posts;
 * product decision 2026-07-16 changed this to full deletion).
 */

import * as admin from "firebase-admin";

/**
 * Deletes all posts authored by the given uid, together with their
 * `reactions` sub-collection.
 *
 * Returns the count of deleted post documents (descendants are not counted —
 * the contract of this step is "the user's posts are gone").
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

  // One BulkWriter shared by every recursiveDelete call. `recursiveDelete`
  // flushes the writer it is given but never closes it, so closing here once
  // all posts are queued is what guarantees the deletes landed.
  const bulkWriter = db.bulkWriter();
  await Promise.all(
    snapshot.docs.map((doc) => db.recursiveDelete(doc.ref, bulkWriter))
  );
  await bulkWriter.close();

  return { count: snapshot.size };
}
