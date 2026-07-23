/**
 * Athlete-owned data cascade — hard-deletes the top-level collections that
 * belong to (or are about) the athlete being deleted. Complements
 * cascade/users.ts, which only recursiveDeletes users/{uid} and its
 * subcollections. QA-CMP-003.
 *
 * Disposition (product decision, 2026-07-17):
 *   measurements, performance_tests        — athlete health data      → DELETE
 *   profile_shares, session_shares          — the athlete's own grants → DELETE
 *   athlete_billing                         — athlete↔trainer config   → DELETE
 *   athlete_notes, follow_up_entries,
 *   nutrition_plans                         — trainer-authored records
 *                                             ABOUT the athlete (no legal
 *                                             retention)               → DELETE
 *
 * NOT handled here (deliberately retained; identity de-references once
 * userPublicProfiles/{uid} is deleted by cascade/users.ts — none of these carry
 * denormalized athlete names):
 *   payments  — RETAINED for fiscal/accounting (only a bare athleteId).
 *   reviews   — rating RETAINED for the trainer's aggregate.
 *   chats/messages — thread RETAINED for the other participant.
 *
 * TRUST BOUNDARY: Admin SDK bypasses firestore.rules (including the
 * `delete: if false` on some of these). Server-side (Cloud Function) only.
 * ADR-ACCDEL-013.
 */

import * as admin from "firebase-admin";

const CHUNK = 400;

/** Collections with an `athleteId` field pointing at the athlete. */
const ATHLETE_FIELD_COLLECTIONS = [
  "measurements",
  "performance_tests",
  "athlete_billing",
  "athlete_notes",
  // QA-507: faltaba. `cascade/storage.ts` borra el objeto físico del archivo,
  // pero sin esto el doc de metadatos sobrevivía al borrado de cuenta con un
  // `downloadUrl` roto y el PF lo seguía viendo listado. Mismo patrón que
  // athlete_notes (no es retención legal) y tiene campo `athleteId`.
  "athlete_files",
  "follow_up_entries",
  "nutrition_plans",
];

/** Collections whose document id IS the athlete uid. */
const ATHLETE_DOC_ID_COLLECTIONS = ["profile_shares", "session_shares"];

async function deleteAllMatching(
  db: admin.firestore.Firestore,
  query: admin.firestore.Query
): Promise<number> {
  const snap = await query.get();
  if (snap.empty) return 0;
  let deleted = 0;
  for (let i = 0; i < snap.docs.length; i += CHUNK) {
    const chunk = snap.docs.slice(i, i + CHUNK);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += chunk.length;
  }
  return deleted;
}

/**
 * Deletes every athlete-owned document for [uid]. Returns the total count.
 */
export async function deleteAthleteOwnedData(
  app: admin.app.App,
  uid: string
): Promise<{ deleted: number }> {
  const db = admin.firestore(app);
  let deleted = 0;

  for (const collection of ATHLETE_FIELD_COLLECTIONS) {
    deleted += await deleteAllMatching(
      db,
      db.collection(collection).where("athleteId", "==", uid)
    );
  }

  for (const collection of ATHLETE_DOC_ID_COLLECTIONS) {
    const ref = db.collection(collection).doc(uid);
    if ((await ref.get()).exists) {
      await ref.delete();
      deleted += 1;
    }
  }

  return { deleted };
}
