/**
 * acceptTrainerLink — callable that promotes a trainer_link pending → active
 * behind the weighted-load gate (paywall Fase 7, PR4, slice 2).
 *
 * Replaces `TrainerLinkRepository.accept()`. The client used to write
 * `status: 'active'` + `acceptedAt` straight to Firestore; the limit was
 * unenforceable there because the client can always lie. From here on the
 * promotion is server-authoritative, and firestore.rules locks the
 * client-side path shut in slice 4.
 *
 * Pattern: pure handler (`runAcceptTrainerLink`) + thin onCall wrapper
 * (`acceptTrainerLink`) — same shape as add-alias.ts / delete-account.ts
 * (ADR-CXP-004), so the handler is unit-testable without the onCall harness.
 *
 * ALL the gate logic lives in `syncTrainerLoad`: the precondition ladder, the
 * projection predicate, the `resource-exhausted` payload the paywall parses,
 * and the `acceptedAt` stamp the old repository method used to write. This
 * file adds nothing but wiring — deliberately.
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

export interface AcceptTrainerLinkResult {
  /** `noop` when the link was already active (idempotent retry). */
  status: "ok" | "noop";
  weightedLoad: number;
  /** `null` = sin limite (plan3). */
  limit: number | null;
}

/**
 * Pure handler. Throws the helper's typed `HttpsError` UNTOUCHED — the
 * `resource-exhausted` payload (`reason`/`tier`/`limit`/loads) is the contract
 * the Flutter client parses to decide which paywall branch to show, so
 * re-wrapping it here would erase `details` and silently break that branch.
 */
export async function runAcceptTrainerLink(
  app: admin.app.App,
  callerUid: string,
  linkId: string,
): Promise<AcceptTrainerLinkResult> {
  if (!linkId) {
    throw new HttpsError("invalid-argument", "linkId is required.");
  }

  const result = await syncTrainerLoad(app, {
    promotion: { linkId, callerUid, expectedFromStatus: "pending" },
  });

  // Adoption metric (M.4): counted against `link-promoted-observed` from the
  // reconciliation trigger. `observed - cf` is exactly the legacy client-side
  // traffic still promoting links directly, which gates the rules deploy.
  if (result.promoted) {
    logger.info("acceptTrainerLink: link promoted", {
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

export const acceptTrainerLink = functions.onCall(
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
  async (request): Promise<AcceptTrainerLinkResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { linkId } = request.data as { linkId?: string };
    if (!linkId) {
      throw new HttpsError("invalid-argument", "linkId is required.");
    }

    return runAcceptTrainerLink(getApp(), request.auth.uid, linkId);
  },
);
