/**
 * resumeTrainerLink — callable that promotes a trainer_link paused → active
 * behind the weighted-load gate (paywall Fase 7, PR4, slice 3).
 *
 * WHY this exists at all: gating `accept` alone does NOT enforce the limit.
 * Pausing drops an athlete from 1.0 to 0.5, so a trainer at plan1 (limit 7)
 * can sit at 7.0, pause two (6.0), accept a new one (7.0 — passes the gate),
 * then resume both and land at 8.0. No gate ever sees that last step. `resume`
 * is the second and last transition that raises weight; with both behind the
 * server, the limit actually holds.
 *
 * Replaces `TrainerLinkRepository.resume()`. Like accept, this is a thin
 * wrapper: `syncTrainerLoad` owns the gate arithmetic AND the transition
 * fields — for `paused` it clears `pausedAt` and PRESERVES `acceptedAt`,
 * matching what the repository method did (a resumed link is not a new one).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { syncTrainerLoad } from "./promote-link";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

export interface ResumeTrainerLinkResult {
  /** `noop` when the link was already active (idempotent retry). */
  status: "ok" | "noop";
  weightedLoad: number;
  /** `null` = sin limite (plan3). */
  limit: number | null;
}

/**
 * Pure handler. Throws the helper's typed `HttpsError` UNTOUCHED — the
 * `resource-exhausted` payload is the contract the Flutter client parses to
 * pick the paywall branch.
 */
export async function runResumeTrainerLink(
  app: admin.app.App,
  callerUid: string,
  linkId: string,
): Promise<ResumeTrainerLinkResult> {
  if (!linkId) {
    throw new HttpsError("invalid-argument", "linkId is required.");
  }

  const result = await syncTrainerLoad(app, {
    promotion: { linkId, callerUid, expectedFromStatus: "paused" },
  });

  // Adoption metric (M.4), same event name as acceptTrainerLink: both are
  // counted against `link-promoted-observed` from the reconciliation trigger.
  if (result.promoted) {
    logger.info("resumeTrainerLink: link promoted", {
      event: "link-promoted-cf",
      linkId,
      trainerId: result.trainerId,
    });
  }

  return {
    status: result.promoted ? "ok" : "noop",
    weightedLoad: result.weightedLoad,
    limit: result.limit,
  };
}

export const resumeTrainerLink = functions.onCall(
  // SIN enforceAppCheck a proposito. El Coach Hub web NO activa App Check:
  // main.dart lo saltea explicitamente en web (`if (!kIsWeb)`) y
  // main_coach_hub.dart no lo activa nunca. Con el flag puesto, cada accept
  // desde la web —que es donde el PF realmente trabaja— seria rechazado.
  //
  // Precedente que lo confirma: `addAlias` SI tiene el flag y se llama desde
  // el Coach Hub web (coach_hub_plan_preview_screen.dart), con el error
  // TRAGADO en un debugPrint. Falla siempre y nadie se entero.
  //
  // Esto no baja la guardia: la funcion valida request.auth, que el caller
  // sea el trainer del vinculo, y el estado de origen. App Check es defensa
  // en profundidad, no la cerradura. Se vuelve a poner —aca y en addAlias—
  // cuando se active App Check en web (ReCaptcha + site key en consola).
  { region: "southamerica-east1" },
  async (request): Promise<ResumeTrainerLinkResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { linkId } = request.data as { linkId?: string };
    if (!linkId) {
      throw new HttpsError("invalid-argument", "linkId is required.");
    }

    return runResumeTrainerLink(getApp(), request.auth.uid, linkId);
  },
);
