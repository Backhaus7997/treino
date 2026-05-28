/**
 * Posts cascade module — anonymizes post author information.
 *
 * For each post where `authorUid == uid`, sets:
 *   - `authorDisplayName` → 'Usuario eliminado'
 *   - `authorAvatarUrl`   → null
 *
 * The `authorUid` field is intentionally preserved for referential integrity.
 * Per ADR-ACCDEL-004: anonymize display fields, keep uid for data lineage.
 *
 * Uses batched updates in chunks of 400 (conservative below 500 limit).
 * Idempotent — running twice yields the same anonymized state.
 * REQ-ACCDEL-CF-006 | ADR-ACCDEL-004
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 400;

/**
 * Anonymizes all posts authored by the given uid.
 * Returns the count of anonymized documents.
 */
export async function anonymizePosts(
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
  let updated = 0;

  // Process in chunks of BATCH_SIZE
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const chunk = docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        authorDisplayName: "Usuario eliminado",
        authorAvatarUrl: null,
        // authorUid intentionally NOT modified — referential integrity (ADR-ACCDEL-004)
      });
    }
    await batch.commit();
    updated += chunk.length;
  }

  return { count: updated };
}
