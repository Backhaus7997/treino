/**
 * notifyOnFollow — Cloud Function for TREINO.
 *
 * Fires on writes to `follows/{followId}`.
 * Sends push notifications on follow lifecycle transitions.
 *
 * `follow-model` PR3a (design §4.2): las 3 ramas y TODO el copy quedan
 * INTACTOS. Lo único que cambió es de dónde sale la dirección — antes
 * `requesterId` + búsqueda dentro de `members`, ahora `followerUid`/
 * `followeeUid`, explícitos en la arista. El copy del backend ya estaba
 * escrito en clave "seguidor", así que es la única pieza del sistema que no
 * necesitó adaptarse a este cambio de modelo: ya estaba escrita para él.
 *
 * Design (Instagram-style — mirror of `PublicProfileFollowButton` flow):
 *
 *   Three notif branches, all target the "other" party (never the actor —
 *   the actor already knows because they took the action):
 *
 *     1. create + status='pending'
 *        → private followee received a follow request
 *        → notify the followee with copy
 *          "{displayName} te envió una solicitud de seguidor"
 *
 *     2. create + status='accepted'  (auto-accept path, PR #273)
 *        → follower followed a public followee directly
 *        → notify the followee with copy
 *          "{displayName} empezó a seguirte"
 *
 *     3. update  pending → accepted   (manual accept)
 *        → followee approved a pending request
 *        → notify the follower with copy
 *          "{displayName} aceptó tu solicitud"
 *
 *   Guards mirror `notify-link-change`:
 *     - after missing → skip (delete event, e.g. unfollow)
 *     - no-op write (status unchanged) → skip
 *     - followerUid/followeeUid missing or reflexive → warn + skip
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
import type { NotificationKind } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type FollowData = Record<string, unknown>;

/**
 * The three notif shapes this CF can dispatch. Exported as a discriminated
 * union so the tests can assert exact branch resolution.
 */
export type FollowNotif =
  | { kind: "request-received"; recipientUid: string; actorUid: string }
  | { kind: "auto-followed"; recipientUid: string; actorUid: string }
  | { kind: "request-accepted"; recipientUid: string; actorUid: string }
  | { kind: "skip"; reason: string };

/**
 * Pure resolver — decides which notif branch (or skip) fires for a given
 * before/after pair. Kept side-effect-free so the branching logic is 100%
 * covered by unit tests without Firestore or Messaging mocks.
 */
export function resolveFollowNotif(
  before: FollowData | undefined,
  after: FollowData | undefined,
): FollowNotif {
  if (!after) {
    return { kind: "skip", reason: "after missing (delete or unfollow)" };
  }

  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  // La dirección se LEE de la arista. No se infiere: `members` existe para el
  // barrido del borrado de cuenta (LD-01), no para deducir quién sigue a quién.
  const followerUid = after.followerUid as string | undefined;
  const followeeUid = after.followeeUid as string | undefined;

  if (!afterStatus || !followerUid || !followeeUid) {
    return { kind: "skip", reason: "missing required fields" };
  }

  // Las rules prohíben la arista reflexiva, pero el Admin SDK las saltea.
  if (followerUid === followeeUid) {
    return { kind: "skip", reason: "reflexive edge" };
  }

  // ── Branch 3: manual accept (update path) ────────────────────────────────
  if (beforeStatus === "pending" && afterStatus === "accepted") {
    // El followee aceptó → se le avisa al follower.
    return {
      kind: "request-accepted",
      recipientUid: followerUid,
      actorUid: followeeUid,
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
      recipientUid: followeeUid,
      actorUid: followerUid,
    };
  }

  // ── Branch 2: auto-accept (public profile) ───────────────────────────────
  if (afterStatus === "accepted") {
    return {
      kind: "auto-followed",
      recipientUid: followeeUid,
      actorUid: followerUid,
    };
  }

  return { kind: "skip", reason: `unknown status "${afterStatus}"` };
}

/**
 * Copy generator — pure. Falls back to 'Alguien' when the actor's public
 * profile is missing or has no displayName, matching notify-chat-message.
 */
export function buildFollowCopy(
  kind: FollowNotif["kind"] & Exclude<FollowNotif["kind"], "skip">,
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
export async function notifyOnFollowHandler(
  app: admin.app.App,
  before: FollowData | undefined,
  after: FollowData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  const notif = resolveFollowNotif(before, after);

  if (notif.kind === "skip") {
    logger.info("notifyOnFollow: skip", { reason: notif.reason });
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

  const body = buildFollowCopy(notif.kind, displayName);
  // Nested under /feed — matches the router's ShellRoute for the public
  // profile screen (`/feed/profile/:uid`). A bare `/profile/:uid` would
  // 404 and fall back to the general router fallback (`/coach`).
  const deepLink = `/feed/profile/${notif.actorUid}`;
  const historyKind: NotificationKind =
    notif.kind === "request-received"
      ? "friend-request"
      : notif.kind === "auto-followed"
        ? "friend-follow"
        : "friend-accepted";

  await sendFcm(
    app,
    {
      uids: [notif.recipientUid],
      kind: historyKind,
      notification: {
        title: "TREINO", // i18n: Fase W3
        body,
      },
      data: {
        deepLink,
        actorUid: notif.actorUid,
      },
      actorUid: notif.actorUid,
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const notifyOnFollow = onDocumentWritten(
  {
    document: "follows/{followId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before?.data() as FollowData | undefined;
    const after = event.data?.after?.data() as FollowData | undefined;
    await notifyOnFollowHandler(getApp(), before, after);
  },
);
