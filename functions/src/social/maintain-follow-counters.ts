/**
 * maintainFollowCounters — Cloud Function for TREINO.
 *
 * Fires on writes to `friendships/{friendshipId}` and keeps the denormalized
 * follow counters on `userPublicProfiles/{uid}` correct and consistent:
 *   - `followingCount` on the REQUESTER (the person who follows)
 *   - `followersCount` on the OTHER party (the person being followed)
 *
 * ## Why this exists (bug W-SOCIAL-COUNTERS-01)
 *
 * Counters were previously maintained CLIENT-SIDE in
 * `FriendshipRepository` (best-effort `FieldValue.increment`). That approach
 * had three defects this CF fixes:
 *   1. Best-effort → any failed/aborted client write leaves the counter
 *      permanently drifted, with no reconciliation.
 *   2. The `delete()` path decremented only `followingCount` (requester),
 *      never `followersCount` (other) — leaving "phantom followers".
 *   3. A malicious client could write arbitrary counter values.
 *
 * Moving this to a CF makes the counters authoritative and symmetric: both
 * sides always move together, server-side, driven by the friendship doc.
 *
 * ## Follow model (asymmetric)
 *
 * A friendship doc is a directed follow: `requesterId` follows the OTHER
 * member. Counters only move when the follow is EFFECTIVE (status accepted):
 *
 *   before → after           requester.followingCount  other.followersCount
 *   ─────────────────────    ────────────────────────  ────────────────────
 *   ∅ → accepted (auto)              +1                        +1
 *   pending → accepted               +1                        +1
 *   accepted → ∅ (unfollow)          −1                        −1
 *   ∅ → pending                       0                         0   (not yet following)
 *   pending → ∅ (cancel req)          0                         0   (was never counted)
 *   accepted → accepted (no-op)       0                         0
 *
 * The +1/−1 pair is written in a single Firestore transaction so the two
 * profiles never disagree.
 *
 * Region southamerica-east1 per ADR-PN-005.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type FriendshipData = Record<string, unknown>;

/** The counter mutation a write resolves to (or a no-op). */
export type CounterDelta =
  | { kind: "apply"; requesterUid: string; otherUid: string; delta: 1 | -1 }
  | { kind: "noop"; reason: string };

/** True only for the accepted status. */
function isAccepted(status: unknown): boolean {
  return status === "accepted";
}

/**
 * Extracts (requesterUid, otherUid) from a friendship doc. Returns null when
 * the doc is malformed (missing requesterId or a members[] without exactly
 * two distinct entries).
 */
function partiesOf(
  data: FriendshipData,
): { requesterUid: string; otherUid: string } | null {
  const requesterUid = data.requesterId as string | undefined;
  const members = (data.members as string[] | undefined) ?? [];
  if (!requesterUid || members.length !== 2) return null;
  const otherUid = members.find((m) => m !== requesterUid);
  if (!otherUid) return null;
  return { requesterUid, otherUid };
}

/**
 * Pure resolver — decides the counter delta for a before/after pair.
 * Side-effect free so every branch is unit-testable without Firestore.
 *
 * A follow becomes effective when the doc reaches `accepted`, and stops
 * being effective when an `accepted` doc is deleted. Everything else is a
 * no-op for counters.
 */
export function resolveCounterDelta(
  before: FriendshipData | undefined,
  after: FriendshipData | undefined,
): CounterDelta {
  const beforeAccepted = before ? isAccepted(before.status) : false;
  const afterAccepted = after ? isAccepted(after.status) : false;

  // No change in "effective follow" state → nothing to do.
  if (beforeAccepted === afterAccepted) {
    return { kind: "noop", reason: "accepted-state unchanged" };
  }

  // Became effective (∅/pending → accepted): +1. Parties come from `after`.
  if (!beforeAccepted && afterAccepted) {
    const parties = partiesOf(after as FriendshipData);
    if (!parties) return { kind: "noop", reason: "after: malformed parties" };
    return { kind: "apply", ...parties, delta: 1 };
  }

  // Stopped being effective (accepted → deleted/…): −1. Parties come from
  // `before` because `after` may be undefined (delete) or partial.
  const parties = partiesOf(before as FriendshipData);
  if (!parties) return { kind: "noop", reason: "before: malformed parties" };
  return { kind: "apply", ...parties, delta: -1 };
}

/**
 * Pure handler extracted for jest testability. Applies the resolved delta to
 * both userPublicProfiles docs in a single transaction. Missing profile docs
 * are skipped (the counter is re-established by backfill / next write) rather
 * than created here, to avoid resurrecting a deleted user's public profile.
 */
export async function maintainFollowCountersHandler(
  app: admin.app.App,
  before: FriendshipData | undefined,
  after: FriendshipData | undefined,
): Promise<void> {
  const outcome = resolveCounterDelta(before, after);
  if (outcome.kind === "noop") {
    logger.info("maintainFollowCounters: noop", { reason: outcome.reason });
    return;
  }

  const db = admin.firestore(app);
  const { requesterUid, otherUid, delta } = outcome;
  const requesterRef = db.collection("userPublicProfiles").doc(requesterUid);
  const otherRef = db.collection("userPublicProfiles").doc(otherUid);

  await db.runTransaction(async (tx) => {
    const [requesterSnap, otherSnap] = await Promise.all([
      tx.get(requesterRef),
      tx.get(otherRef),
    ]);

    // followingCount lives on the requester; followersCount on the other.
    // Only touch docs that exist — a follow against a deleted account should
    // not recreate that account's public profile.
    if (requesterSnap.exists) {
      tx.update(requesterRef, {
        followingCount: FieldValue.increment(delta),
      });
    }
    if (otherSnap.exists) {
      tx.update(otherRef, {
        followersCount: FieldValue.increment(delta),
      });
    }
  });

  logger.info("maintainFollowCounters: applied", {
    requesterUid,
    otherUid,
    delta,
  });
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005.
 */
export const maintainFollowCounters = onDocumentWritten(
  {
    document: "friendships/{friendshipId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before?.data() as FriendshipData | undefined;
    const after = event.data?.after?.data() as FriendshipData | undefined;
    await maintainFollowCountersHandler(getApp(), before, after);
  },
);
