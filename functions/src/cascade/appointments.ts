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
 *   - `cancellationLog` → += una entrada con el motivo
 *
 * Past appointments are never touched — historical integrity preserved.
 * REQ-ACCDEL-CF-009 | ADR-ACCDEL-007
 *
 * ─── #846 — el motivo va DENTRO del log, no como campo de primer nivel ──────
 *
 * Acá se escribía `reason: 'athlete-account-deleted'` como clave suelta del
 * documento. `reason` NO existe en `Appointment.toJson()` —sólo existe adentro
 * de `CancellationEntry`, que es un elemento del `cancellationLog`— ni está en
 * las 14 claves de `hasOnly()` de `appointmentShapeOk()` /
 * `appointmentUpdateShapeOk()` en `firestore.rules`.
 *
 * El Admin SDK saltea las reglas, así que la escritura pasaba. El daño es lo
 * que quedaba después: `hasOnly()` corre sobre `request.resource.data`, que es
 * el documento **MERGEADO**, así que cualquier update PARCIAL posterior del
 * cliente arrastraba el `reason` guardado y la allowlist lo rechazaba. Medido
 * contra el emulador: el PF anotando ese turno → DENY, el atleta cancelándolo
 * → DENY, y `allow delete: if false`. O sea nuestro propio backend fabricaba
 * turnos imborrables — la familia de #781, sembrada desde adentro.
 *
 * El motivo se mueve al `cancellationLog`, que ES el rastro de auditoría de la
 * colección, SÍ está en la allowlist, y ya tiene el campo `reason` en el
 * modelo (`CancellationEntry.reason`, `appointment.dart:25`). No agrega
 * superficie: la otra salida —meter `reason` en las dos allowlists— pedía
 * cota, pin en los DOS caminos y un campo nuevo en el modelo que nadie lee.
 *
 * ⚠️ Este fix evita turnos NUEVOS congelados; NO destraba los que ya se
 * escribieron en producción, porque la clave sigue guardada en esos documentos
 * y `hasOnly()` mira el merge. Para eso está
 * `scripts/migrations/strip_appointment_reason.mjs`, que NO se corrió.
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

  // #846 — el motivo viaja como entrada del `cancellationLog`, que es una de
  // las 14 claves de la allowlist de las reglas. La forma es la de
  // `CancellationEntry` (`byUid` / `atMs` / `reason`), o sea la MISMA que
  // escriben `AppointmentRepository.cancel()` y `cancelFutureSeries()`, para
  // que `Appointment.fromJson` la deserialice igual que cualquier otra.
  // `byUid` es el atleta cuya baja de cuenta disparó el cascade.
  const atMs = Date.now();

  for (let i = 0; i < activeDocs.length; i += BATCH_SIZE) {
    const chunk = activeDocs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "cancelled",
        cancellationLog: admin.firestore.FieldValue.arrayUnion({
          byUid: uid,
          atMs,
          reason: "athlete-account-deleted",
        }),
      });
    }
    await batch.commit();
    updated += chunk.length;
  }

  return { count: updated };
}
