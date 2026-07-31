/**
 * notifyOnReaction — Cloud Function for TREINO.
 *
 * Fires on writes to `posts/{postId}/reactions/{reactorUid}`, but sends a push
 * only for a real reaction create. Updates (changing emoji) and deletes are
 * intentionally silent.
 *
 * Notification grouping (for example, "N personas reaccionaron") is the next
 * step when the user base grows. It is intentionally omitted today to avoid
 * over-designing before that scale requires it.
 *
 * Reaction notifications deep-link to the individual post. The Flutter route
 * handles deleted and no-longer-readable posts as an unavailable state.
 *
 * All user-facing strings are in es-AR, matching the existing notification
 * functions.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type DocumentData = Record<string, unknown>;

export type ReactionNotification =
  | {
      kind: "notify";
      recipientUid: string;
      actorUid: string;
      title: string;
      body: string;
      deepLink: string;
      postId: string;
    }
  | { kind: "skip"; reason: string };

export interface ResolveReactionNotificationInput {
  before: DocumentData | undefined;
  after: DocumentData | undefined;
  post: DocumentData | undefined;
  postId: string;
  reactorUid: string;
  actorDisplayName?: string;
}

/**
 * Pure resolver for the complete reaction notification truth table.
 */
export function resolveReactionNotification({
  before,
  after,
  post,
  postId,
  reactorUid,
  actorDisplayName,
}: ResolveReactionNotificationInput): ReactionNotification {
  if (!after) {
    return { kind: "skip", reason: "after missing (delete)" };
  }

  if (before !== undefined) {
    return { kind: "skip", reason: "existing reaction updated" };
  }

  const authorUid = post?.authorUid as string | undefined;
  if (!authorUid) {
    return { kind: "skip", reason: "post missing or authorUid missing" };
  }

  if (reactorUid === authorUid) {
    return { kind: "skip", reason: "author reacted to own post" };
  }

  const displayName = actorDisplayName?.trim() || "Alguien";
  return {
    kind: "notify",
    recipientUid: authorUid,
    actorUid: reactorUid,
    title: "TREINO", // i18n: server-side notification copy is currently hardcoded
    body: `${displayName} reaccionó a tu publicación`, // i18n: es-AR
    deepLink: `/feed/post/${postId}`,
    postId,
  };
}

/**
 * Async handler extracted for emulator-backed integration tests.
 */
export async function notifyOnReactionHandler(
  app: admin.app.App,
  postId: string,
  reactorUid: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  // Updates and deletes cannot notify and do not need any Firestore reads.
  if (!after || before !== undefined) {
    const skipped = resolveReactionNotification({
      before,
      after,
      post: undefined,
      postId,
      reactorUid,
    });
    if (skipped.kind === "skip") {
      logger.info("notifyOnReaction: skip", { reason: skipped.reason, postId });
    }
    return;
  }

  const db = admin.firestore(app);
  const postRef = db.collection("posts").doc(postId);
  const postSnap = await postRef.get();
  const post = postSnap.exists ? postSnap.data() : undefined;

  const initialResolution = resolveReactionNotification({
    before,
    after,
    post,
    postId,
    reactorUid,
  });
  if (initialResolution.kind === "skip") {
    logger.info("notifyOnReaction: skip", {
      reason: initialResolution.reason,
      postId,
      reactorUid,
    });
    return;
  }

  // Same source and fallback as notifyOnFriendship.
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(reactorUid)
    .get();
  const actorDisplayName = profileSnap.data()?.displayName as string | undefined;

  const notification = resolveReactionNotification({
    before,
    after,
    post,
    postId,
    reactorUid,
    actorDisplayName,
  });
  if (notification.kind === "skip") return;

  await sendFcm(
    app,
    {
      uids: [notification.recipientUid],
      kind: "reaction",
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        deepLink: notification.deepLink,
        postId: notification.postId,
        actorUid: notification.actorUid,
      },
      actorUid: notification.actorUid,
    },
    messaging,
  );
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const notifyOnReaction = onDocumentWritten(
  {
    document: "posts/{postId}/reactions/{reactorUid}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before.exists
      ? (event.data.before.data() as DocumentData)
      : undefined;
    const after = event.data?.after.exists
      ? (event.data.after.data() as DocumentData)
      : undefined;

    await notifyOnReactionHandler(
      getApp(),
      event.params.postId,
      event.params.reactorUid,
      before,
      after,
    );
  },
);
