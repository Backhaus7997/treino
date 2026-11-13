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
 *   - reason === 'trainer-account-deleted' → skip (#1333). The trainer deleted
 *     their account; the plans they assigned STAY with the athlete and stay
 *     usable (owner decision). Archiving them would hide them from the athlete,
 *     whose list filters by status. Reads are allowed by `assignedTo ==
 *     auth.uid` with no link check.
 *   - reason === 'duplicate-request' → skip (#1812). `acceptTrainerLink` cancela
 *     las demás solicitudes pending del par al aceptar una: el par queda con un
 *     vínculo vivo, y archivarle los planes sería quitárselos a un alumno activo.
 *   - before.status === after.status (no-op write) → skip.
 *   - after.status !== 'terminated' → skip.
 *
 * ── La otra mitad: el plan que se asigna DESPUÉS (#1723) ────────────────────
 *
 * Todo lo de arriba corre UNA vez, en la transición a `terminated`. Un plan que
 * se escribe cuando el vínculo ya terminó (o que nunca existió) no vuelve a
 * pasar por ahí: el ex-alumno lo ve como «DE TU COACH · ACTIVA» y no puede
 * archivarlo ni borrarlo (`firestore.rules`: sólo `assignedBy` puede). La UI ya
 * no los crea (#1708, #1714, #1724, #1725) pero el servidor los sigue aceptando:
 * `trainer-assigned` valida el ROL de quien escribe y no el vínculo, porque
 * `trainer_links` tiene ids autogenerados y una regla no puede buscarlo.
 *
 * `archiveOrphanAssignedPlanOnCreate` cierra el hueco para cualquier cliente: al
 * CREAR el plan, si el par (assignedBy, assignedTo) no tiene un vínculo vivo
 * (`active` | `paused`), lo archiva con el mismo `status: 'archived'` de arriba.
 * Misma excepción: el par con un vínculo `trainer-account-deleted` (#1333)
 * conserva su plan. (`account-deleted` no pide caso aparte: la cascada de
 * `cascade/routines.ts` borra los planes asignados al alumno que se va.) Los
 * planes que YA quedaron huérfanos los barre
 * `scripts/backfill_archive_orphan_assigned_routines.js`.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { DUPLICATE_REQUEST_REASON } from "./subscriptions/cancel-duplicate-pending-links";
import { TRAINER_ACCOUNT_DELETED_REASON } from "./cascade/trainer-data";
import { LIVE_LINK_STATUSES } from "./chat/sync-chat-on-trainer-link";

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

  // Guard: the TRAINER deleted their account — the assigned plans stay (#1333).
  if (reason === TRAINER_ACCOUNT_DELETED_REASON) {
    logger.info(
      `cleanupAssignedPlans: skipping reason=${TRAINER_ACCOUNT_DELETED_REASON}`,
    );
    return { count: 0 };
  }

  // Guard: una solicitud DUPLICADA que `acceptTrainerLink` cancela al aceptar otra
  // del mismo par (#1812). El par tiene un vínculo VIVO: sus planes se quedan.
  if (reason === DUPLICATE_REQUEST_REASON) {
    logger.info(`cleanupAssignedPlans: skipping reason=${DUPLICATE_REQUEST_REASON}`);
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

// ── Plan asignado a un par sin vínculo vivo (#1723) ──────────────────────────

type RoutineData = Record<string, unknown>;

/** Qué hizo el handler; lo devuelve para que los tests no dependan de los logs. */
export type OrphanPlanResult =
  | "skipped" // no es un plan asignado a OTRO: no hay par que mirar
  | "invalid" // `trainer-assigned` sin assignedBy/assignedTo usables
  | "gone" // el doc ya no existe al releerlo
  | "already-archived"
  | "live-link" // el par tiene un vínculo active|paused: el plan es legítimo
  | "trainer-account-deleted" // #1333: el plan se queda con el alumno
  | "archived";

const nonEmptyString = (v: unknown): v is string => typeof v === "string" && v !== "";

/**
 * ¿Hay algo que mirar? Sólo un `trainer-assigned` para un alumno que no es el PF
 * mismo. Barato y sin leer nada: casi toda creación de `routines` (plantillas,
 * rutinas propias) sale acá, antes de tocar el app.
 *
 * `assignedBy === assignedTo` (un PF que se asigna un plan a sí mismo) no es un
 * par PF-alumno y no tiene vínculo posible: se deja como está.
 */
function isAssignmentToAnotherUser(routine: RoutineData | undefined): boolean {
  if (!routine || routine.source !== "trainer-assigned") return false;
  if (routine.status === "archived") return false; // nació archivada: ya está
  return !(nonEmptyString(routine.assignedBy) && routine.assignedBy === routine.assignedTo);
}

/**
 * Archiva el plan recién creado si su par (assignedBy, assignedTo) no tiene un
 * vínculo vivo. Handler puro, extraído para jest (el emulador no dispara los
 * triggers v2 solo).
 *
 * RECONCILIA, NO ESPEJA: el evento sólo decide si hay algo que mirar; lo que se
 * escribe sale del estado ACTUAL, releído en una transacción —el plan y TODOS los
 * vínculos del par—. Así un re-vínculo que cae entre la creación y este handler
 * (el PF acepta y asigna en el mismo minuto) no deja archivado un plan legítimo, y
 * un reintento sobre un plan ya archivado no escribe nada. Los triggers son
 * at-least-once.
 *
 * Una query de igualdad doble, la misma de `archiveAssignedPlansForPair`: no pide
 * índice compuesto. Se leen todos los vínculos del par (son pocos) y no uno por
 * status porque hacen falta dos respuestas: ¿hay uno vivo? y ¿alguno terminó por
 * `trainer-account-deleted`? Con ese motivo el plan se QUEDA aunque sea posterior:
 * "cualquiera" y no "el último" porque la cuenta del PF no vuelve, así que no
 * puede haber un vínculo posterior que cambie la respuesta.
 */
export async function archiveOrphanAssignedPlanHandler(
  app: App,
  routineId: string,
  created: RoutineData | undefined,
): Promise<OrphanPlanResult> {
  if (!isAssignmentToAnotherUser(created)) return "skipped";

  const trainerId = created?.assignedBy;
  const athleteId = created?.assignedTo;
  if (!nonEmptyString(trainerId) || !nonEmptyString(athleteId)) {
    logger.warn("archiveOrphanAssignedPlan: falta assignedBy o assignedTo", { routineId });
    return "invalid";
  }

  const db = getFirestore(app);
  const routineRef = db.collection("routines").doc(routineId);
  const pairLinks = db
    .collection("trainer_links")
    .where("trainerId", "==", trainerId)
    .where("athleteId", "==", athleteId);

  const result = await db.runTransaction(async (tx): Promise<OrphanPlanResult> => {
    // Todas las lecturas antes de la primera escritura.
    const [routineSnap, linksSnap] = await Promise.all([tx.get(routineRef), tx.get(pairLinks)]);
    if (!routineSnap.exists) return "gone";
    if (routineSnap.get("status") === "archived") return "already-archived";

    const links = linksSnap.docs.map((d) => d.data() as LinkData);
    if (links.some((l) => (LIVE_LINK_STATUSES as readonly string[]).includes(l.status as string))) {
      return "live-link";
    }
    if (links.some((l) => l.reason === TRAINER_ACCOUNT_DELETED_REASON)) {
      return "trainer-account-deleted";
    }

    tx.update(routineRef, { status: "archived" });
    return "archived";
  });

  logger.info("archiveOrphanAssignedPlan", { routineId, trainerId, athleteId, resultado: result });
  return result;
}

/**
 * Cloud Function trigger sobre la CREACIÓN de `routines/{routineId}`. Region
 * `southamerica-east1`, la de los demás triggers de Firestore del repo.
 *
 * Sólo `create`: lo que se asigna ya con vínculo y se vuelve huérfano después lo
 * cierra `cleanupAssignedPlansOnUnlink` en la transición. Queda fuera, a
 * propósito, el update de `status` (las reglas dejan al `assignedBy` devolver
 * un plan archivado a `active`, sin mirar el vínculo): no es lo que pide #1723
 * y el barrido del script sí lo agarra.
 *
 * `retry: true`: sin reintento, un fallo transitorio deja el plan ACTIVO para
 * siempre —el bug de este issue—; el handler es idempotente.
 */
export const archiveOrphanAssignedPlanOnCreate = onDocumentCreated(
  { document: "routines/{routineId}", region: "southamerica-east1", retry: true },
  async (event) => {
    const created = event.data?.data() as RoutineData | undefined;
    // Filtro barato ANTES de tocar el app.
    if (!isAssignmentToAnotherUser(created)) return;
    await archiveOrphanAssignedPlanHandler(ensureApp(), event.params.routineId, created);
  },
);
