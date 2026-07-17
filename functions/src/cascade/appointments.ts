/**
 * Appointments cascade module — cancels future appointments for a deleted athlete.
 *
 * Queries `appointments` where:
 *   - `athleteId == uid`
 *   - `startsAt > now()`
 *   - `status != 'cancelled'`   (already-cancelled are left as-is)
 *
 * Updates each matching doc:
 *   - `status` → 'cancelled'
 *   - `reason` → 'athlete-account-deleted'
 *
 * Past appointments are never touched — historical integrity preserved.
 * REQ-ACCDEL-CF-009 | ADR-ACCDEL-007
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 500;

/**
 * Cancels all future, non-cancelled appointments for the given athlete uid.
 * Returns the count of cancelled documents.
 */
export async function cancelFutureAppointments(
  app: admin.app.App,
  uid: string
): Promise<{ count: number }> {
  const db = admin.firestore(app);
  const now = admin.firestore.Timestamp.now();

  // Query future appointments for this athlete that are not already cancelled.
  // QA-API-001: the field is `startsAt` (what appointment_repository writes and
  // the freezed Appointment model declares) — NOT `scheduledAt`, which no client
  // code ever writes. Querying the non-existent field returned an empty snapshot,
  // so the athlete's future appointments were never cancelled and kept their PII.
  const snapshot = await db
    .collection("appointments")
    .where("athleteId", "==", uid)
    .where("startsAt", ">", now)
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  // Filter out already-cancelled in memory (Firestore doesn't support != with > in single query
  // without a composite index that may not exist)
  const activeDocs = snapshot.docs.filter(
    (d) => d.data().status !== "cancelled" && d.data().status !== "completed"
  );

  if (activeDocs.length === 0) {
    return { count: 0 };
  }

  let updated = 0;

  for (let i = 0; i < activeDocs.length; i += BATCH_SIZE) {
    const chunk = activeDocs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "cancelled",
        reason: "athlete-account-deleted",
      });
    }
    await batch.commit();
    updated += chunk.length;
  }

  return { count: updated };
}
