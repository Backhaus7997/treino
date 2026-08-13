/**
 * maintainReactionCounters — Cloud Function for TREINO.
 *
 * Fires on writes to `posts/{postId}/reactions/{reactorUid}` and keeps the
 * parent post's denormalized `reactionCounts` map authoritative.
 *
 * ## Why this recomputes instead of incrementing (W-SOCIAL-COUNTERS-01)
 *
 * Eventarc delivery is at-least-once. Applying `FieldValue.increment()` for a
 * reaction write would apply the same delta again on redelivery and leave the
 * counter permanently drifted. Recounting the reactions from the source of
 * truth and writing the absolute map is idempotent.
 *
 * Region southamerica-east1 per ADR-PN-005.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

// DEBE espejar `ReactionType` en lib/features/feed/domain/reaction_type.dart y
// la allowlist de `reactionPayloadOk()` en firestore.rules. Los tres se
// mantienen a mano y no hay nada que los sincronice: si agregás o renombrás un
// tipo, actualizá los tres. Un tipo que falte acá NO rompe la función — se
// descarta en silencio y el contador queda en cero, que es un modo de falla
// mudo y difícil de diagnosticar (ya pasó al renombrar `strong` a `like`).
const REACTION_TYPES = ["like", "fire", "clap"] as const;
type ReactionType = (typeof REACTION_TYPES)[number];
type ReactionData = Record<string, unknown>;

export type ReactionCounts = Partial<Record<ReactionType, number>>;

function isReactionType(value: unknown): value is ReactionType {
  return (
    typeof value === "string" &&
    (REACTION_TYPES as readonly string[]).includes(value)
  );
}

/**
 * Pure aggregation logic. Invalid documents are ignored defensively; security
 * rules prevent clients from creating them, but Admin SDK writes bypass rules.
 * Zero-count keys are never emitted.
 */
export function aggregateReactionCounts(
  reactions: readonly ReactionData[],
): ReactionCounts {
  const counts: ReactionCounts = {};

  for (const reaction of reactions) {
    const type = reaction.type;
    if (!isReactionType(type)) continue;
    counts[type] = (counts[type] ?? 0) + 1;
  }

  return counts;
}

/**
 * Recomputes the complete reaction map transactionally and updates only an
 * existing parent post, so a late/redelivered event cannot resurrect a post.
 */
export async function maintainReactionCountersHandler(
  app: admin.app.App,
  postId: string,
): Promise<void> {
  const db = admin.firestore(app);
  const postRef = db.collection("posts").doc(postId);
  const reactionsQuery = postRef.collection("reactions");

  await db.runTransaction(async (tx) => {
    const [postSnap, reactionsSnap] = await Promise.all([
      tx.get(postRef),
      tx.get(reactionsQuery),
    ]);

    if (!postSnap.exists) return;

    const counts = aggregateReactionCounts(
      reactionsSnap.docs.map((doc) => doc.data()),
    );
    tx.update(postRef, { reactionCounts: counts });
  });

  logger.info("maintainReactionCounters: recomputed", { postId });
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const maintainReactionCounters = onDocumentWritten(
  {
    document: "posts/{postId}/reactions/{reactorUid}",
    region: "southamerica-east1",
  },
  async (event) => {
    await maintainReactionCountersHandler(getApp(), event.params.postId);
  },
);
