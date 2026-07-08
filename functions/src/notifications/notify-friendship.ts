/**
 * notifyOnFriendship — Cloud Function for TREINO.
 *
 * Fires on writes to `friendships/{friendshipId}`.
 * Sends push notifications on friendship lifecycle transitions.
 *
 * Design (Instagram-style — mirror of `PublicProfileFollowButton` flow):
 *
 *   Three notif branches, all target the "other" party (never the actor —
 *   the actor already knows because they took the action):
 *
 *     1. create + status='pending'
 *        → private target received a follow request
 *        → notify the non-requester (target) with copy
 *          "{displayName} te envió una solicitud de seguidor"
 *
 *     2. create + status='accepted'  (auto-accept path, PR #273)
 *        → requester followed a public target directly
 *        → notify the non-requester (target) with copy
 *          "{displayName} empezó a seguirte"
 *
 *     3. update  pending → accepted   (manual accept)
 *        → target approved a pending request
 *        → notify the requester with copy
 *          "{displayName} aceptó tu solicitud"
 *
 *   Guards mirror `notify-link-change`:
 *     - after missing → skip (delete event, e.g. unfollow)
 *     - no-op write (status unchanged) → skip
 *     - requesterId or members[] missing → warn + skip
 *
 *   Sender name is read from `userPublicProfiles/{actorId}.displayName` with
 *   fallback 'Alguien', matching the notify-chat-message pattern.
 *
 *   Deep link points to the actor's public profile so the recipient can tap
 *   the push and land on the natural next surface (accept / view profile).
 *
 *   All user-facing strings in es-AR.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type FriendshipData = Record<string, unknown>;

/**
 * The three notif shapes this CF can dispatch. Exported as a discriminated
 * union so the tests can assert exact branch resolution.
 */
export type FriendshipNotif =
  | { kind: "request-received"; recipientUid: string; actorUid: string }
  | { kind: "auto-followed"; recipientUid: string; actorUid: string }
  | { kind: "request-accepted"; recipientUid: string; actorUid: string }
  | { kind: "skip"; reason: string };

/**
 * Pure resolver — decides which notif branch (or skip) fires for a given
 * before/after pair. Kept side-effect-free so the branching logic is 100%
 * covered by unit tests without Firestore or Messaging mocks.
 */
export function resolveFriendshipNotif(
  before: FriendshipData | undefined,
  after: FriendshipData | undefined,
): FriendshipNotif {
  if (!after) {
    return { kind: "skip", reason: "after missing (delete or unfollow)" };
  }

  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const requesterId = after.requesterId as string | undefined;
  const members = (after.members as string[] | undefined) ?? [];

  if (!afterStatus || !requesterId || members.length !== 2) {
    return { kind: "skip", reason: "missing required fields" };
  }

  // The "other" party is whoever in members[] isn't the requester.
  const otherUid = members.find((m) => m !== requesterId);
  if (!otherUid) {
    return { kind: "skip", reason: "cannot infer other party from members" };
  }

  // ── Branch 3: manual accept (update path) ────────────────────────────────
  if (beforeStatus === "pending" && afterStatus === "accepted") {
    // The target (non-requester) accepted → notify the requester.
    return {
      kind: "request-accepted",
      recipientUid: requesterId,
      actorUid: otherUid,
    };
  }

  // From here down, `before` must be undefined (create path).
  if (before !== undefined) {
    return { kind: "skip", reason: "update without pending→accepted transition" };
  }

  // ── Branch 1: pending request received ───────────────────────────────────
  if (afterStatus === "pending") {
    return {
      kind: "request-received",
      recipientUid: otherUid,
      actorUid: requesterId,
    };
  }

  // ── Branch 2: auto-accept (public profile) ───────────────────────────────
  if (afterStatus === "accepted") {
    return {
      kind: "auto-followed",
      recipientUid: otherUid,
      actorUid: requesterId,
    };
  }

  return { kind: "skip", reason: `unknown status "${afterStatus}"` };
}

/**
 * Copy generator — pure. Falls back to 'Alguien' when the actor's public
 * profile is missing or has no displayName, matching notify-chat-message.
 */
export function buildFriendshipCopy(
  kind: FriendshipNotif["kind"] & Exclude<FriendshipNotif["kind"], "skip">,
  displayName: string,
): string {
  switch (kind) {
    case "request-received":
      return `${displayName} te envió una solicitud de seguidor`; // i18n: Fase W3
    case "auto-followed":
      return `${displayName} empezó a seguirte`; // i18n: Fase W3
    case "request-accepted":
      return `${displayName} aceptó tu solicitud`; // i18n: Fase W3
  }
}

/**
 * Pure handler extracted for jest testability.
 */
export async function notifyOnFriendshipHandler(
  app: admin.app.App,
  before: FriendshipData | undefined,
  after: FriendshipData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  const notif = resolveFriendshipNotif(before, after);

  if (notif.kind === "skip") {
    logger.info("notifyOnFriendship: skip", { reason: notif.reason });
    return;
  }

  const db = admin.firestore(app);

  // Read the actor's display name for the push body.
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(notif.actorUid)
    .get();
  const displayName: string =
    (profileSnap.data()?.displayName as string | undefined) ?? "Alguien"; // i18n: Fase W3

  const body = buildFriendshipCopy(notif.kind, displayName);
  // Nested under /feed — matches the router's ShellRoute for the public
  // profile screen (`/feed/profile/:uid`). A bare `/profile/:uid` would
  // 404 and fall back to the general router fallback (`/coach`).
  const deepLink = `/feed/profile/${notif.actorUid}`;

  await sendFcm(
    app,
    {
      uids: [notif.recipientUid],
      notification: {
        title: "TREINO", // i18n: Fase W3
        body,
      },
      data: {
        deepLink,
        kind: notif.kind,
        actorUid: notif.actorUid,
      },
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const notifyOnFriendship = onDocumentWritten(
  {
    document: "friendships/{friendshipId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before?.data() as FriendshipData | undefined;
    const after = event.data?.after?.data() as FriendshipData | undefined;
    await notifyOnFriendshipHandler(getApp(), before, after);
  },
);
