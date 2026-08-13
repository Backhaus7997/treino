/**
 * maintainFollowCounters — Cloud Function for TREINO.
 *
 * Fires on writes to `follows/{followId}` and keeps the denormalized
 * follow counters on `userPublicProfiles/{uid}` correct and consistent:
 *   - `followingCount` on the FOLLOWER (the person who follows)
 *   - `followersCount` on the FOLLOWEE (the person being followed)
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
 * sides always move together, server-side, driven by the edge doc.
 *
 * ## Follow model (asymmetric)
 *
 * `follow-model` PR3a: la fuente de verdad pasó de `friendships` (un doc por
 * par, id ordenado) a `follows` (un doc por ARISTA DIRIGIDA,
 * `{followerUid}_{followeeUid}`). La dirección ya no se infiere de
 * `requesterId` + `members`: viene explícita en el documento.
 *
 * Counters only move when the follow is EFFECTIVE (status accepted):
 *
 *   before → after           follower.followingCount   followee.followersCount
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

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type FollowData = Record<string, unknown>;

/** The counter mutation a write resolves to (or a no-op). */
export type CounterDelta =
  | { kind: "apply"; requesterUid: string; otherUid: string; delta: 1 | -1 }
  | { kind: "noop"; reason: string };

/** True only for the accepted status. */
function isAccepted(status: unknown): boolean {
  return status === "accepted";
}

/**
 * Extrae (follower, followee) de una arista. Devuelve null si el doc está
 * malformado (le falta alguno de los dos uids, o es reflexivo).
 *
 * `follow-model` PR3a: acá ya no se INFIERE nada. El modelo dirigido lleva la
 * dirección explícita en el propio documento, así que se lee — antes había que
 * tomar `requesterId` y buscar dentro de `members` cuál de los dos era "el
 * otro". `members` sigue existiendo, pero SÓLO para que el barrido del borrado
 * de cuenta use una única query (LD-01); usarlo acá volvería a atar la
 * dirección a un campo que no la define.
 *
 * La rama "malformed" se conserva como defensa contra documentos escritos por
 * Admin SDK, que saltea las rules: sin ella, un doc torcido movería contadores.
 *
 * Los nombres del retorno (`requesterUid`/`otherUid`) se mantienen para no
 * tocar `CounterDelta` ni sus consumidores; semánticamente son follower y
 * followee.
 */
function partiesOf(
  data: FollowData,
): { requesterUid: string; otherUid: string } | null {
  const follower = data.followerUid as string | undefined;
  const followee = data.followeeUid as string | undefined;
  if (!follower || !followee || follower === followee) return null;
  return { requesterUid: follower, otherUid: followee };
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
  before: FollowData | undefined,
  after: FollowData | undefined,
): CounterDelta {
  const beforeAccepted = before ? isAccepted(before.status) : false;
  const afterAccepted = after ? isAccepted(after.status) : false;

  // No change in "effective follow" state → nothing to do.
  if (beforeAccepted === afterAccepted) {
    return { kind: "noop", reason: "accepted-state unchanged" };
  }

  // Became effective (∅/pending → accepted): +1. Parties come from `after`.
  if (!beforeAccepted && afterAccepted) {
    const parties = partiesOf(after as FollowData);
    if (!parties) return { kind: "noop", reason: "after: malformed parties" };
    return { kind: "apply", ...parties, delta: 1 };
  }

  // Stopped being effective (accepted → deleted/…): −1. Parties come from
  // `before` because `after` may be undefined (delete) or partial.
  const parties = partiesOf(before as FollowData);
  if (!parties) return { kind: "noop", reason: "before: malformed parties" };
  return { kind: "apply", ...parties, delta: -1 };
}

/**
 * Pure handler extracted for jest testability. QA-507: recomputa los contadores
 * desde los vínculos aceptados (idempotente ante reentrega) y los escribe en
 * both userPublicProfiles docs in a single transaction. Missing profile docs
 * are skipped (the counter is re-established by backfill / next write) rather
 * than created here, to avoid resurrecting a deleted user's public profile.
 */
/**
 * QA-507: cuenta las aristas ACEPTADAS de [uid] desde la fuente de verdad.
 *
 * `follow-model` PR3a: DOS queries direccionales en vez de una con split en
 * memoria. No es una preferencia de estilo — en `follows` no existe
 * `requesterId`, así que un único `array-contains` devuelve las aristas de las
 * dos direcciones mezcladas y sin ningún campo que permita separarlas por
 * documento. El sentido lo da el CAMPO por el que se consulta.
 *
 * Costo: 4 queries por evento (2 uids × 2 direcciones) en vez de 2.
 * Justificado en ADR-FOLLOW-007.
 */
async function countAcceptedFor(
  tx: admin.firestore.Transaction,
  db: admin.firestore.Firestore,
  uid: string,
): Promise<{ followingCount: number; followersCount: number }> {
  const [followingSnap, followersSnap] = await Promise.all([
    tx.get(
      db
        .collection("follows")
        .where("followerUid", "==", uid)
        .where("status", "==", "accepted"),
    ),
    tx.get(
      db
        .collection("follows")
        .where("followeeUid", "==", uid)
        .where("status", "==", "accepted"),
    ),
  ]);

  return {
    followingCount: followingSnap.size,
    followersCount: followersSnap.size,
  };
}

export async function maintainFollowCountersHandler(
  app: admin.app.App,
  before: FollowData | undefined,
  after: FollowData | undefined,
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

    // QA-507 (idempotencia): recomputamos desde cero en vez de
    // FieldValue.increment(delta). Eventarc entrega at-least-once: una
    // reentrega del MISMO evento sumaba +1 dos veces y dejaba
    // following/followersCount inflados de forma permanente. Contar los
    // vínculos aceptados es idempotente — mismo criterio que las otras 3
    // aggregates (link / review / ranking), que ya recomputan.
    const [requesterCounts, otherCounts] = await Promise.all([
      countAcceptedFor(tx, db, requesterUid),
      countAcceptedFor(tx, db, otherUid),
    ]);

    // Only touch docs that exist — a follow against a deleted account should
    // not recreate that account's public profile.
    if (requesterSnap.exists) {
      tx.update(requesterRef, requesterCounts);
    }
    if (otherSnap.exists) {
      tx.update(otherRef, otherCounts);
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
    document: "follows/{followId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before?.data() as FollowData | undefined;
    const after = event.data?.after?.data() as FollowData | undefined;
    await maintainFollowCountersHandler(getApp(), before, after);
  },
);
