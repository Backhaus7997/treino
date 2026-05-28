/**
 * Users cascade module — deletes user documents and public profiles.
 *
 * Handles:
 *   - `users/{uid}` with all sub-collections (recursiveDelete)
 *   - `userPublicProfiles/{uid}` (hard delete)
 *   - `trainerPublicProfiles/{uid}` (defensive no-op if absent)
 *
 * Admin SDK bypasses Firestore security rules — no rules change needed.
 * REQ-ACCDEL-CF-004 | ADR-ACCDEL-001
 */

import * as admin from "firebase-admin";

/**
 * Deletes all Firestore documents owned by the given user.
 * Idempotent — safe to call when docs are already absent.
 */
export async function deleteUserDocs(
  app: admin.app.App,
  uid: string
): Promise<void> {
  const db = admin.firestore(app);

  // Step 1: Recursively delete users/{uid} including all sub-collections
  // (sessions, sessions/*/setLogs, checkIns, etc.)
  // Admin SDK BulkWriter handles batching internally.
  await db.recursiveDelete(db.collection("users").doc(uid));

  // Step 2: Delete userPublicProfiles/{uid}
  // Firestore delete on a non-existent doc is a no-op — no error thrown.
  await db.collection("userPublicProfiles").doc(uid).delete();

  // Step 3: Delete trainerPublicProfiles/{uid} if present (defensive)
  // Athletes normally have no trainer profile; this handles edge cases.
  await db.collection("trainerPublicProfiles").doc(uid).delete();
}
