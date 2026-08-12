/**
 * promote-link.ts — syncTrainerLoad(app, input): the single transactional
 * helper that owns every write to a trainer's weighted-load state (paywall
 * Fase 7, PR4, design D-1).
 *
 * Two callers, one helper:
 *   - `acceptTrainerLink` / `resumeTrainerLink` (slices 2-3) pass a
 *     `promotion` intent — the gate path. Projects the target link to
 *     `active`, blocks if that would exceed the trainer's effective limit.
 *   - `linkLoadReconcile` (this slice, 1.9-1.11) passes `promotion: null` —
 *     the reconciliation path. Full recompute from live `trainer_links`,
 *     ALWAYS writes (never blocks — it's a display-only fix-up, not a gate).
 *
 * `syncTrainerLoad` owns its own transaction (does NOT receive a `tx`
 * parameter) — see design D-1 for why `promoteLinkToActive(tx, ...)` was
 * rejected: passing `tx` would force every caller to open its own
 * transaction, duplicating the read-order/retry contract this helper exists
 * to centralize.
 *
 * READS-BEFORE-WRITES (design D-1 order, load-bearing):
 *   1. tx.get(trainer_links/{linkId})           — only when promotion != null
 *   2. validate (exists, trainerId==callerUid, status==expectedFromStatus,
 *      entitlement != 'blocked')
 *   3. Promise.all([tx.get(users/{trainerId}), tx.get(links where trainerId)])
 *   4. project + compare (pure)
 *   ── frontera: writes ──
 *   5. tx.update(link.status = 'active')          — skipped when no-op/reconciling
 *   6. tx.set(users/{trainerId}.weightedLoad, merge) — ALWAYS runs; this
 *      read-write pair on users/{trainerId} IS the serialization point that
 *      makes concurrent promotions safe (REQ-PAYWALL-GATE-005).
 *
 * `weightedLoad` on users/{uid} is NEVER a gate input (REQ-PAYWALL-GATE-006)
 * — the gate always recomputes live from trainer_links inside the same
 * transaction that writes it.
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

import { computeWeightedLoad, WeightedLink } from "./weighted-load";
import { effectiveWeightLimit, SubscriptionState } from "./effective-limit";
import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "./tier-config";

export interface PromotionIntent {
  linkId: string;
  callerUid: string;
  expectedFromStatus: "pending" | "paused";
}

export interface SyncTrainerLoadInput {
  /** Required when `promotion` is null (reconciliation) — the trigger knows
   * the trainerId directly from the written link, no lookup needed. Ignored
   * when `promotion` is set (derived from the link doc instead). */
  trainerId?: string;
  promotion: PromotionIntent | null;
  /** Deterministic clock for `effectiveWeightLimit`'s cancelled-grace math. */
  nowMs?: number;
}

export interface SyncTrainerLoadResult {
  trainerId: string;
  weightedLoad: number;
  limit: number;
  /** True only when this call actually flipped a link to 'active'. */
  promoted: boolean;
}

export type PromotionDenialReason = "plan-limit" | "subscription-inactive";

/**
 * D-2: pure derivation of the paywall's denial reason from the trainer's
 * NOMINAL tier limit vs. their EFFECTIVE (entitlement-adjusted) limit.
 *
 * `subscription-inactive` — the trainer paid for a tier whose limit is
 * higher than what they're currently entitled to (lapsed/pending/paused
 * subscription): a billing-recovery problem, not an upsell.
 * `plan-limit` — the trainer is exactly at their nominal tier's limit
 * (including the Free tier, where nominal == effective by construction):
 * an upsell problem.
 *
 * Any single `tier`-derived enum value would produce a FALSE statement on
 * one of these two branches — see design D-2 for the three rejected
 * alternatives (nominal-only, effective-only, both-pushed-to-client).
 */
export function promotionDenialReason(
  sub: SubscriptionState | null | undefined,
  limit: number,
): PromotionDenialReason {
  const tier: SubscriptionTier = sub?.tier ?? "free";
  const nominalLimit = TIER_WEIGHT_LIMITS[tier];
  return limit < nominalLimit ? "subscription-inactive" : "plan-limit";
}

/**
 * Maps the Firestore `users/{uid}.subscription` map onto the pure
 * `SubscriptionState` shape `effectiveWeightLimit` consumes. The Firestore
 * field is `currentPeriodEnd` (Timestamp); `effectiveWeightLimit` wants
 * `currentPeriodEndMs` (number) so it stays Firestore-independent and
 * unit-testable with a plain clock. `subscription` absent ⇒ null (Free,
 * no backfill — same contract `TrainerSubscription?` uses client-side).
 */
function toSubscriptionState(
  data: admin.firestore.DocumentData | undefined,
): SubscriptionState | null {
  const sub = data?.subscription as
    | {
        tier: SubscriptionState["tier"];
        status: SubscriptionState["status"];
        currentPeriodEnd?: admin.firestore.Timestamp | null;
      }
    | undefined;
  if (!sub) return null;
  return {
    tier: sub.tier,
    status: sub.status,
    currentPeriodEndMs: sub.currentPeriodEnd ? sub.currentPeriodEnd.toMillis() : null,
  };
}

type LinkDoc = WeightedLink & { id: string; status: string };

export async function syncTrainerLoad(
  app: admin.app.App,
  input: SyncTrainerLoadInput,
): Promise<SyncTrainerLoadResult> {
  const db = admin.firestore(app);
  const nowMs = input.nowMs ?? Date.now();
  const promotion = input.promotion;

  return db.runTransaction(async (tx) => {
    let trainerId = input.trainerId;
    let linkRef: admin.firestore.DocumentReference | null = null;
    let alreadyActive = false;

    // ── 1-2. Read + validate the promoted link FIRST (design D-1 step 1-2) ──
    if (promotion) {
      if (!promotion.linkId || !promotion.callerUid) {
        throw new HttpsError("invalid-argument", "linkId and callerUid are required.");
      }

      linkRef = db.collection("trainer_links").doc(promotion.linkId);
      const linkSnap = await tx.get(linkRef);
      if (!linkSnap.exists) {
        throw new HttpsError("not-found", "Link not found.");
      }

      const linkData = linkSnap.data() as admin.firestore.DocumentData;
      trainerId = linkData.trainerId as string;

      if (promotion.callerUid !== trainerId) {
        throw new HttpsError("permission-denied", "Caller must be the link's trainer.");
      }

      if (linkData.status === "active") {
        // Success no-op (design D-1): covers a retry after a commit that
        // already landed (client timeout) — never double-promotes.
        alreadyActive = true;
      } else if (linkData.status !== promotion.expectedFromStatus) {
        throw new HttpsError("failed-precondition", "wrong-status");
      } else if (linkData.entitlement === "blocked") {
        throw new HttpsError("failed-precondition", "link-blocked");
      }
    }

    if (!trainerId) {
      throw new HttpsError("invalid-argument", "trainerId is required.");
    }

    // ── 3. Reads-before-writes: subscription + full live link set, parallel ──
    const [trainerSnap, linksSnap] = await Promise.all([
      tx.get(db.collection("users").doc(trainerId)),
      tx.get(db.collection("trainer_links").where("trainerId", "==", trainerId)),
    ]);

    if (!trainerSnap.exists) {
      // Anomalous (the caller authenticated as this trainer, or the trigger
      // fired for a trainerId whose profile is gone) — the trigger's own
      // catch-and-log wrapper (mirrors link-aggregate.ts) turns this into a
      // warning instead of a retry storm; see link-load-reconcile.ts.
      throw new HttpsError("not-found", "Trainer profile not found.");
    }

    const sub = toSubscriptionState(trainerSnap.data());
    const limit = effectiveWeightLimit(sub, nowMs);

    const currentLinks: LinkDoc[] = linksSnap.docs.map((doc) => {
      const data = doc.data() as admin.firestore.DocumentData;
      return {
        id: doc.id,
        athleteId: data.athleteId as string,
        status: data.status as LinkDoc["status"],
        entitlement: data.entitlement as WeightedLink["entitlement"],
      };
    });
    const currentLoad = computeWeightedLoad(currentLinks as unknown as WeightedLink[]);

    // ── 4. Project (pure) — force the target link to 'active' unless it's
    //      already active (no-op) or this is a reconciliation (no target). ──
    const targetId = linkRef?.id;
    const projectedLinks: LinkDoc[] =
      promotion && targetId && !alreadyActive
        ? currentLinks.map((l) =>
          l.id === targetId ? { ...l, status: "active" } : l,
        )
        : currentLinks;
    const projectedLoad = computeWeightedLoad(projectedLinks as unknown as WeightedLink[]);

    if (promotion && !alreadyActive && projectedLoad > limit) {
      const reason = promotionDenialReason(sub, limit);
      throw new HttpsError(
        "resource-exhausted",
        "Weighted-load limit reached.",
        {
          reason,
          tier: sub?.tier ?? "free",
          limit,
          currentLoad,
          projectedLoad,
        },
      );
    }

    // ── frontera: writes ──────────────────────────────────────────────────
    if (promotion && linkRef && !alreadyActive) {
      // The gate REPLACES TrainerLinkRepository.accept()/resume() (slices
      // 2-3), so it must write every field those methods wrote. `status`
      // alone is a SILENT data regression: trainer_coach_view.dart renders
      // `acceptedAt ?? requestedAt`, so a missing stamp degrades to the
      // request date instead of failing. Keyed off `expectedFromStatus` so
      // the per-transition semantics live here, in the single writer, rather
      // than in each callable.
      tx.update(linkRef, {
        status: "active",
        ...(promotion.expectedFromStatus === "pending"
          // accept: stamp the start of the relationship.
          ? { acceptedAt: admin.firestore.Timestamp.fromMillis(nowMs) }
          // resume: clear the pause marker; acceptedAt is PRESERVED — a
          // resumed link is not a new one.
          : { pausedAt: admin.firestore.FieldValue.delete() }),
      });
    }
    // Step 6 ALWAYS runs (design D-1) — this read-write pair on
    // users/{trainerId} is the transaction's serialization point.
    tx.set(db.collection("users").doc(trainerId), { weightedLoad: projectedLoad }, { merge: true });

    return {
      trainerId,
      weightedLoad: projectedLoad,
      limit,
      promoted: Boolean(promotion) && !alreadyActive,
    };
  });
}
