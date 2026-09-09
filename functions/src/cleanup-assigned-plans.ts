/**
 * cleanupAssignedPlansOnUnlink — Cloud Function for TREINO.
 *
 * Fires on writes to `trainer_links/{linkId}`. When a link becomes
 * `terminated`, ARCHIVES every plan the trainer had ASSIGNED to that athlete,
 * so the plans stop appearing for the athlete once the relationship ends.
 *
 * ARCHIVA, no borra. Hasta 2026-09-09 hacía `batch.delete()`, y eso contradecía
 * la invariante que la propia app declara: `routine_status.dart` dice que una
 * rutina se archiva en vez de borrarse "para mantener referencias históricas de
 * sesiones" (ADR-USR-04). Las sesiones que el alumno ya entrenó apuntan a estos
 * documentos: borrarlos las dejaba huérfanas, y si el vínculo se reactivaba el
 * plan ya no existía.
 *
 * El PF lo describió como el comportamiento que esperaba —"las rutinas pasan a
 * estar archivadas"— cuando el código hacía otra cosa.
 *
 * Archivar SOLO no alcanza para que el alumno deje de verlas: su query
 * (`RoutineRepository.listAssignedTo`) también tiene que filtrar por estado, o
 * el ex-alumno las sigue viendo, ahora marcadas. Las dos mitades van juntas.
 *
 * Why server-side: the Firestore client rule only lets the trainer
 * (`assignedBy`) delete `trainer-assigned` routines — the athlete cannot. Since
 * EITHER party can terminate the link, the cleanup must run with admin
 * privileges so it works regardless of who cut it, without widening the client
 * rule.
 *
 * Scope — archiva SOLO los docs `source == 'trainer-assigned'` del par exacto
 * (trainer, athlete):
 *   - Trainer TEMPLATES (`trainer-template`, `assignedTo: null`) are NEVER
 *     touched — they are separate, reusable documents. A template assigned to a
 *     single athlete still survives the unlink; only the athlete's assigned
 *     COPY is removed.
 *   - The athlete's own routines (`user-created`) are untouched.
 *
 * Guards (mirrors notifyOnLinkChange):
 *   - after missing (delete event) → skip.
 *   - reason === 'account-deleted' → skip (the account-deletion cascade owns
 *     that flow; don't interfere).
 *   - before.status === after.status (no-op write) → skip.
 *   - after.status !== 'terminated' → skip.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

const BATCH_SIZE = 500;

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Archives every `trainer-assigned` routine for the (trainerId, athleteId)
 * pair — flips `status` to `archived`, keeping the document. Pure +
 * emulator-testable. Returns the count of documents actually written.
 *
 * Three equality filters need no composite index (Firestore serves equality-only
 * queries from automatic single-field indexes).
 */
export async function archiveAssignedPlansForPair(
  app: App,
  trainerId: string,
  athleteId: string,
): Promise<{ count: number }> {
  const db = getFirestore(app);

  const snapshot = await db
    .collection("routines")
    .where("assignedBy", "==", trainerId)
    .where("assignedTo", "==", athleteId)
    .where("source", "==", "trainer-assigned")
    .get();

  if (snapshot.empty) {
    return { count: 0 };
  }

  // Las que ya están archivadas no se vuelven a escribir. Este trigger puede
  // correr más de una vez sobre el mismo par —un reintento, o dos writes que
  // dejan el link en `terminated`—, y reescribir el mismo valor cuesta una
  // escritura por documento sin cambiar nada. El contador cuenta trabajo real,
  // que es lo que el log dice.
  const pending = snapshot.docs.filter((doc) => doc.get("status") !== "archived");
  if (pending.length === 0) {
    return { count: 0 };
  }

  let archived = 0;
  for (let i = 0; i < pending.length; i += BATCH_SIZE) {
    const chunk = pending.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, { status: "archived" });
    }
    await batch.commit();
    archived += chunk.length;
  }

  return { count: archived };
}

/**
 * Pure handler extracted for jest testability.
 *
 * @param app    - Admin SDK app.
 * @param before - Snapshot data before the write (undefined for creates).
 * @param after  - Snapshot data after the write (undefined for deletes).
 */
export async function cleanupAssignedPlansOnUnlinkHandler(
  app: App,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<{ count: number }> {
  // Guard: document deleted — nothing to clean from here.
  if (!after) {
    logger.info("cleanupAssignedPlans: after missing (delete event), skipping");
    return { count: 0 };
  }

  const reason = after.reason as string | undefined;
  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: account-deletion cascade owns its own cleanup — don't interfere.
  if (reason === "account-deleted") {
    logger.info("cleanupAssignedPlans: skipping cascade reason=account-deleted");
    return { count: 0 };
  }

  // Guard: no-op write — status unchanged.
  if (beforeStatus !== undefined && beforeStatus === afterStatus) {
    return { count: 0 };
  }

  // Only act when the link becomes terminated.
  if (afterStatus !== "terminated") {
    return { count: 0 };
  }

  if (!trainerId || !athleteId) {
    logger.warn("cleanupAssignedPlans: missing trainerId/athleteId", {
      trainerId,
      athleteId,
    });
    return { count: 0 };
  }

  const result = await archiveAssignedPlansForPair(app, trainerId, athleteId);
  logger.info("cleanupAssignedPlans: archived assigned plans on unlink", {
    trainerId,
    athleteId,
    count: result.count,
  });
  return result;
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1 (matches the other
 * trainer_links triggers).
 */
export const cleanupAssignedPlansOnUnlink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await cleanupAssignedPlansOnUnlinkHandler(ensureApp(), before, after);
  },
);
