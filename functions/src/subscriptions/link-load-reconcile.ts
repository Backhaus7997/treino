/**
 * linkLoadReconcile — Cloud Function for TREINO (paywall Fase 7, PR4,
 * REQ-PAYWALL-GATE-009).
 *
 * Fires on every write to `trainer_links/{linkId}` and keeps the
 * denormalized `users/{trainerId}.weightedLoad` accurate for DISPLAY only —
 * the paywall gate (`syncTrainerLoad` with a `promotion` intent) never
 * trusts this field and always recomputes live from `trainer_links`
 * (REQ-PAYWALL-GATE-006). This trigger exists so client-side transitions
 * that don't go through the gate (pause, terminate, decline, cancel — all
 * still client-writable, design D-4) keep the displayed N/limit correct
 * without a round-trip.
 *
 * Design (mirrors link-aggregate.ts, same trigger surface):
 *   - Runs in southamerica-east1 (matches the other trainer_links triggers).
 *   - Idempotent: `syncTrainerLoad({promotion: null})` full-recomputes from
 *     the live link set on every event — no increments, no drift on retry.
 *   - Error-safe: catches ALL exceptions (including a missing
 *     users/{trainerId} profile, surfaced by syncTrainerLoad as a thrown
 *     not-found), logs, and NEVER rethrows — prevents Eventarc retry storms.
 *   - Never blocks: reconciliation is not a gate, so it always writes
 *     regardless of whether the recomputed load exceeds the trainer's
 *     current limit (syncTrainerLoad's `promotion: null` path never throws
 *     resource-exhausted).
 *   - Logs `{event: 'link-promoted-observed'}` when a write transitions a
 *     link INTO 'active' — the adoption metric M.4 compares this against
 *     the CFs' own `{event: 'link-promoted-cf'}` log line to measure legacy
 *     client-side accept()/resume() traffic after the CF migration ships.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

import { syncTrainerLoad } from "./promote-link";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Recomputes and persists a trainer's weightedLoad. Exported separately for
 * direct unit/integration testability (mirrors recomputeAthleteCount).
 * Catches everything — a missing trainer profile, a transient Firestore
 * error, anything — logs a warning, and returns without throwing.
 */
export async function linkLoadReconcileHandler(
  app: admin.app.App,
  trainerId: string,
): Promise<void> {
  try {
    const result = await syncTrainerLoad(app, { trainerId, promotion: null });
    logger.info("linkLoadReconcile: recomputed weightedLoad", {
      trainerId,
      weightedLoad: result.weightedLoad,
    });
  } catch (err) {
    logger.warn(`linkLoadReconcile: error recomputing for trainerId=${trainerId}`, {
      trainerId,
      err,
    });
  }
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1, matching the other
 * `trainer_links` triggers (linkAggregate, notifyOnLinkChange,
 * cleanupAssignedPlansOnUnlink, syncSessionShare).
 */
export const linkLoadReconcile = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();

    const trainerId =
      (after?.trainerId as string | undefined) ?? (before?.trainerId as string | undefined);

    if (!trainerId) {
      logger.warn("linkLoadReconcile: trainerId not found in document", {
        linkId: event.params.linkId,
      });
      return;
    }

    // Adoption metric (M.4) — a legacy client-side write can still promote a
    // link to 'active' until the CFs ship and firestore.rules locks it down
    // (slice 4). No new instrumentation beyond this one log line, reused by
    // acceptTrainerLink/resumeTrainerLink's own `link-promoted-cf` line.
    const beforeStatus = before?.status as string | undefined;
    const afterStatus = after?.status as string | undefined;
    if (beforeStatus !== "active" && afterStatus === "active") {
      logger.info("linkLoadReconcile: link promoted", {
        event: "link-promoted-observed",
        linkId: event.params.linkId,
        trainerId,
      });
    }

    await linkLoadReconcileHandler(getApp(), trainerId);
  },
);
