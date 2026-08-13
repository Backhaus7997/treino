/**
 * backfill-follow-counters.ts — recompute followersCount / followingCount for
 * every userPublicProfiles doc from the authoritative `follows` collection.
 *
 * ## Why
 *
 * Follow counters used to be maintained best-effort client-side, so they
 * drifted (failed writes, asymmetric unfollow → phantom followers) and were
 * never set at all for users whose friendships predate the counter logic.
 * The `maintainFollowCounters` Cloud Function now keeps them correct going
 * forward; this one-shot script reconciles the EXISTING data.
 *
 * ## Model (post follow-model, design §7.4)
 *
 * `follows` es un doc por arista DIRIGIDA (`follows/{followerUid}_{followeeUid}`).
 * Cada arista ya es direccional — no hay que partir nada por `requesterId`
 * como en el modelo viejo de `friendships`. Sólo cuenta `status == 'accepted'`.
 * Por cada arista aceptada:
 *   - followerUid.followingCount += 1
 *   - followeeUid.followersCount += 1
 *
 * Con follow mutuo (que es como queda TODA relación migrada — dos aristas,
 * `{A}_{B}` y `{B}_{A}`, ambas `accepted`) las dos aristas suman 1 a cada lado
 * de cada usuario: no colapsan en 1. Los contadores SUBEN respecto del split
 * viejo por `requesterId`, que era engañoso — mostraba "siguiendo 1,
 * seguidores 0" para una relación que en los hechos era mutua (ADR-FOLLOW-013).
 *
 * El agregador viejo sobre `friendships` (`tallyFollowCounters`) se conserva
 * para no romper tests existentes, pero el camino que corre `main()` es el
 * nuevo, sobre `follows`.
 *
 * The script recomputes each profile's counters FROM SCRATCH (not increments),
 * so it is idempotent — running it twice yields the same result. It only
 * writes a profile whose stored counters differ from the recomputed truth,
 * to minimize writes.
 *
 * ## Safety
 *
 * - Dry-run by default: prints the diff, writes nothing.
 * - Pass `--apply` to actually write the corrections.
 * - Only touches `followersCount` / `followingCount`; no other fields.
 * - Skips edges missing `followerUid` / `followeeUid`.
 *
 * Run with admin credentials, from the functions/ directory:
 *   # dry run (no writes):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/backfill-follow-counters.ts
 *   # apply:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/backfill-follow-counters.ts --apply
 */

import * as admin from "firebase-admin";

interface Tally {
  followers: number;
  following: number;
}

/**
 * Pure aggregator — folds accepted friendships into a per-uid tally.
 * Exported for unit testing without Firestore.
 *
 * @param friendships array of { requesterId, members, status }
 */
export function tallyFollowCounters(
  friendships: Array<{
    requesterId?: string;
    members?: string[];
    status?: string;
  }>,
): Map<string, Tally> {
  const tallies = new Map<string, Tally>();
  const bump = (uid: string, key: keyof Tally) => {
    const t = tallies.get(uid) ?? { followers: 0, following: 0 };
    t[key] += 1;
    tallies.set(uid, t);
  };

  for (const f of friendships) {
    if (f.status !== "accepted") continue;
    const requester = f.requesterId;
    const members = f.members ?? [];
    if (!requester || members.length !== 2) continue;
    // The requester must be one of the two members — otherwise the doc is
    // corrupt and we cannot trust which direction the follow points.
    if (!members.includes(requester)) continue;
    const other = members.find((m) => m !== requester);
    if (!other) continue;

    bump(requester, "following"); // requester follows other
    bump(other, "followers"); // other is followed by requester
  }

  return tallies;
}

/**
 * Pure aggregator — folds accepted `follows` edges into a per-uid tally.
 * Exported for unit testing without Firestore.
 *
 * A diferencia de `tallyFollowCounters`, acá NO hay split en memoria: cada
 * arista ya es direccional (design §7.4), así que dos aristas del mismo par
 * (`{A}_{B}` y `{B}_{A}`, follow mutuo) suman 1 a cada lado de cada usuario,
 * no colapsan en 1.
 *
 * @param edges array de { followerUid, followeeUid, status }
 */
export function tallyFollowCountersFromEdges(
  edges: Array<{
    followerUid?: string;
    followeeUid?: string;
    status?: string;
  }>,
): Map<string, Tally> {
  const tallies = new Map<string, Tally>();
  const bump = (uid: string, key: keyof Tally) => {
    const t = tallies.get(uid) ?? { followers: 0, following: 0 };
    t[key] += 1;
    tallies.set(uid, t);
  };

  for (const e of edges) {
    if (e.status !== "accepted") continue;
    if (!e.followerUid || !e.followeeUid) continue;

    bump(e.followerUid, "following"); // followerUid sigue a followeeUid
    bump(e.followeeUid, "followers"); // followeeUid es seguido por followerUid
  }

  return tallies;
}

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  admin.initializeApp();
  const db = admin.firestore();

  console.log(
    `\n=== backfill-follow-counters (${apply ? "APPLY" : "DRY RUN"}) ===\n`,
  );

  // 1. Read every accepted follow edge and tally the truth.
  const followsSnap = await db
    .collection("follows")
    .where("status", "==", "accepted")
    .get();

  const truth = tallyFollowCountersFromEdges(
    followsSnap.docs.map((d) => d.data() as Record<string, unknown>),
  );
  console.log(
    `Read ${followsSnap.size} accepted follow edges → ` +
      `${truth.size} users with non-zero counters.\n`,
  );

  // 2. Read every public profile so we can also zero-out stale non-zero
  //    counters for users who no longer have any accepted follows.
  const profilesSnap = await db.collection("userPublicProfiles").get();

  let diffs = 0;
  let writes = 0;
  const batchSize = 400;
  let batch = db.batch();
  let batchOps = 0;

  for (const doc of profilesSnap.docs) {
    const data = doc.data();
    const storedFollowers = (data.followersCount as number | undefined) ?? 0;
    const storedFollowing = (data.followingCount as number | undefined) ?? 0;
    const t = truth.get(doc.id) ?? { followers: 0, following: 0 };

    if (storedFollowers === t.followers && storedFollowing === t.following) {
      continue; // already correct
    }

    diffs++;
    console.log(
      `${doc.id}: followers ${storedFollowers} → ${t.followers}, ` +
        `following ${storedFollowing} → ${t.following}`,
    );

    if (apply) {
      batch.update(doc.ref, {
        followersCount: t.followers,
        followingCount: t.following,
      });
      batchOps++;
      writes++;
      if (batchOps >= batchSize) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }
  }

  if (apply && batchOps > 0) {
    await batch.commit();
  }

  console.log(
    `\n${diffs} profile(s) out of sync.` +
      (apply
        ? ` Wrote ${writes} correction(s).`
        : " Re-run with --apply to fix."),
  );

  // Note: users with accepted follows but NO userPublicProfiles doc are not
  // created here (same policy as the CF — do not resurrect missing profiles).
  const missing = [...truth.keys()].filter(
    (uid) => !profilesSnap.docs.some((d) => d.id === uid),
  );
  if (missing.length > 0) {
    console.log(
      `\n⚠️  ${missing.length} user(s) have accepted follows but no ` +
        `userPublicProfiles doc — skipped (not created): ${missing.join(", ")}`,
    );
  }
}

// Only run when invoked directly (ts-node scripts/...), NOT when imported by
// a test that just wants the pure `tallyFollowCounters` aggregator.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
