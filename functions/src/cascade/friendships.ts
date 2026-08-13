/**
 * Social-graph cascade module — sweeps all follow edges of a user.
 *
 * Deletes all `follows/*` docs where the `members` array contains `uid`.
 * Uses batched deletes in chunks of 500 for scale.
 *
 * `follow-model` PR3a (ADR-FOLLOW-002): la colección pasó de `friendships` a
 * `follows`. El grafo dirigido tiene DOS documentos por par —`{A}_{B}` y
 * `{B}_{A}`— así que borrar una cuenta tiene que llevarse tanto a quién seguía
 * como a quién la seguía. `members` contiene los dos uids en las dos
 * direcciones, así que un solo `array-contains` alcanza a ambas y el barrido
 * conserva UNA SOLA query. Ése es el argumento fuerte a favor de mantener el
 * campo `members` (LD-01): sin él esto pasaría a 2 queries + deduplicación, y
 * el borrado de cuenta es justo donde un doc que se escapa es un problema de
 * compliance, no de UX.
 *
 * Idempotent — safe to call when no edges exist.
 * REQ-ACCDEL-CF-005 | ADR-ACCDEL-001 | ADR-FOLLOW-002
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 500;

/**
 * Deletes all follow edges where the given uid appears in `members`.
 * Returns the count of deleted documents.
 */
export async function sweepFollows(
  app: admin.app.App,
  uid: string
): Promise<{ count: number }> {
  const db = admin.firestore(app);

  const snapshot = await db
    .collection("follows")
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
