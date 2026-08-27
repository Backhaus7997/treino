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
 *   - `reason` → 'athlete-account-deleted'   (señal CF→CF, ver abajo)
 *   - `cancelledBy` → el uid del atleta
 *   - `cancellationLog` → += una entrada con el motivo (rastro de auditoría)
 *
 * Past appointments are never touched — historical integrity preserved.
 * REQ-ACCDEL-CF-009 | ADR-ACCDEL-007
 *
 * ─── #846 — el turno que esta CF congelaba, y por qué se cerró en las REGLAS ─
 *
 * Acá se escribía `reason: 'athlete-account-deleted'`, y `reason` no estaba en
 * las claves de `hasOnly()` de `appointmentShapeOk()` /
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
 * ⚠️ La primera versión de este fix MOVÍA el motivo adentro del
 * `cancellationLog` y sacaba la clave suelta. Se revirtió, y las dos razones
 * están medidas:
 *
 *  1. **El guard se volvía forjable.** `notify-appointment.ts` lee el motivo
 *     como CONTROL DE FLUJO. Las reglas no iteran listas —está escrito en
 *     `firestore.rules`, sobre el Path 1: *«ese sigue siendo forjable porque
 *     las reglas no iteran listas»*—, así que el contenido de una entrada del
 *     log NO se valida. Medido de punta a punta: un atleta autenticado cancela
 *     SU turno por el Path 1 legítimo agregando
 *     `{byUid, atMs, reason: 'athlete-account-deleted'}` → ALLOW, y el handler
 *     real emite CERO push y CERO mail. El PF nunca se entera de que le
 *     cancelaron, y es simétrico: el PF puede silenciar al atleta. Con la clave
 *     suelta eso era IMPOSIBLE, justamente porque no estaba en `hasOnly()`.
 *
 *  2. **Pedía una migración contra producción para destrabar lo ya escrito.**
 *     `treino-dev` ES producción (#826) y es el único proyecto que hay.
 *
 * La salida es la contraria: `reason` ENTRA a las dos allowlists de
 * `firestore.rules` y queda **pineada en los DOS caminos de cliente**
 * (`request.resource.data.get('reason', null) == resource.data.get(...)`),
 * más `== null` en el `create` y `delete: if false`. O sea que el cliente no
 * la puede agregar, cambiar ni borrar por ninguna puerta, y el Admin SDK la
 * escribe porque saltea las reglas. Los documentos que ya están en producción
 * se destraban SOLOS con el deploy de las reglas, sin correr nada.
 *
 * ⚠️ Y queda dicho porque el commit anterior decía lo contrario: meter `reason`
 * en la allowlist **NO** la vuelve «una clave nueva escribible por el cliente».
 * Con el pin en los dos caminos es exactamente lo opuesto — es la única clave
 * del documento que el cliente NO puede tocar, y por eso sirve de señal CF→CF.
 *
 * ─── `reason` SÍ se lee, y como control de flujo ────────────────────────────
 *
 * La primera versión de este header, del commit de #846 y de `docs/security.md`
 * decían que `reason` era «un dato que nadie lee». Se verificó el cliente Dart
 * y ahí es cierto. **En `functions/src/` no**: `notify-appointment.ts` lo lee
 * como GUARD —si el motivo es el del cascade, no manda la notificación— y está
 * documentado como ADR-PN-006 / REQ-PN-CF-003. Es un contrato CF→CF
 * deliberado, igual que el par intacto `cascade/trainer-links.ts` (escribe
 * `reason: 'account-deleted'`) ↔ `notify-link-change.ts` (lo lee).
 *
 * Por eso el motivo se exporta acá como `ATHLETE_ACCOUNT_DELETED_REASON` —un
 * solo símbolo para productor y consumidor, en vez de dos literales que se
 * desincronizan en silencio—, y por eso el cascade escribe además
 * `cancelledBy` y la entrada del `cancellationLog`.
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 500;

/**
 * Motivo del cascade. Va en la clave `reason` de primer nivel.
 *
 * CONTRATO CF→CF: `notifications/notify-appointment.ts` importa esta constante
 * y la usa de guard para NO notificar la cancelación (ADR-PN-006 /
 * REQ-PN-CF-003). No es un string decorativo: si cambia el valor, cambia el
 * comportamiento del consumidor. Vive acá —en el productor— y se importa, para
 * que renombrarlo no pueda romper el guard en silencio.
 *
 * Y va en `reason` y NO en el `cancellationLog` porque el guard necesita una
 * señal que el cliente no pueda emitir: `firestore.rules` pinea `reason` en
 * los dos caminos de cliente, y en cambio NO puede validar el contenido de una
 * entrada del log —las reglas no iteran listas—. Un motivo escrito adentro del
 * log lo forja cualquier miembro del turno. (#846)
 */
export const ATHLETE_ACCOUNT_DELETED_REASON = "athlete-account-deleted";

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

  // #846 — la entrada del `cancellationLog` acompaña al `reason`, no lo
  // reemplaza. La forma es la de `CancellationEntry` (`byUid` / `atMs` /
  // `reason`), o sea la MISMA que escriben `AppointmentRepository.cancel()` y
  // `cancelFutureSeries()`, para que `Appointment.fromJson` la deserialice
  // igual que cualquier otra y el motivo se vea en la app.
  // `byUid` es el atleta cuya baja de cuenta disparó el cascade.
  const atMs = Date.now();

  for (let i = 0; i < activeDocs.length; i += BATCH_SIZE) {
    const chunk = activeDocs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "cancelled",
        // La SEÑAL. Es la única clave del documento que el cliente no puede
        // escribir —`firestore.rules` la pinea en los dos caminos de update y
        // la exige `null` en el `create`—, así que cuando aparece, la escribió
        // el Admin SDK. Eso es lo que hace confiable el guard de
        // `notify-appointment.ts`. (#846)
        reason: ATHLETE_ACCOUNT_DELETED_REASON,
        // `cancelledBy` es quién canceló, y acá el actor es el atleta que dio
        // de baja la cuenta. Faltaba, y no es cosmético: `notify-appointment`
        // elige el destinatario con este campo y sin él cae en
        // `[athleteId, trainerId]` —o sea le escribe también al fantasma—.
        // Con el guard sano no se llega a esa rama; esto es el segundo cierre,
        // y de paso deja el documento con la MISMA forma que escribe
        // `AppointmentRepository.cancel()`.
        cancelledBy: uid,
        // El RASTRO. Es lo que la app deserializa y muestra
        // (`CancellationEntry.reason`, `appointment.dart:25`). No es la señal:
        // el contenido de una entrada del log lo puede forjar cualquier
        // miembro del turno, porque las reglas no iteran listas.
        cancellationLog: admin.firestore.FieldValue.arrayUnion({
          byUid: uid,
          atMs,
          reason: ATHLETE_ACCOUNT_DELETED_REASON,
        }),
      });
    }
    await batch.commit();
    updated += chunk.length;
  }

  return { count: updated };
}
