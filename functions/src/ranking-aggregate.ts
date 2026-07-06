/**
 * rankingAggregate — Cloud Functions for TREINO.
 *
 * Server-authoritative recompute of the 4 ranking-metric fields
 * (`lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`) on
 * `userPublicProfiles/{uid}`, closing the forged-metrics vulnerability
 * described in `sdd/rankings-integrity` (audit obs #390): a client capable of
 * bypassing the (then-missing) field checks could set any ranking-metric
 * value directly. From this change forward these 4 fields are written ONLY
 * by this trigger's Admin SDK writes — Phase 2 (firestore.rules hardening)
 * makes them client-immutable.
 *
 * Design `sdd/rankings-integrity/design`:
 *   - AD-1: TWO triggers, cross-collection targets only.
 *       Trigger A (`rankingAggregateOnSession`) on
 *       `users/{uid}/sessions/{sessionId}` — fires on every qualifying
 *       session write (cross-collection target = reviewAggregate's
 *       loop-avoidance property, ADR-RV-001).
 *       Trigger B (`rankingAggregateOnOptIn`) on `userPublicProfiles/{uid}`,
 *       but SHORT-CIRCUITS unless the write is the opt-in ENABLE transition
 *       (`before.rankingOptIn != true && after.rankingOptIn == true`). Its
 *       own metric merge write re-fires itself, but on the re-fire
 *       `before.rankingOptIn == after.rankingOptIn == true`, so the
 *       transition-equality guard returns `false` and the loop terminates
 *       after exactly one metrics write. See [shouldRecomputeOnOptInTransition].
 *   - AD-2: reads the SAME bounded window the Dart client used to read
 *       (`orderBy('startedAt','desc').limit(365)`, filter
 *       `status=='finished' && wasFullyCompleted==true`), sums
 *       `totalVolumeKg`, and computes each main-lift family's max weight from
 *       every matching session's `setLogs` subcollection via the TS port of
 *       `lib/features/gym_rankings/domain/main_lift_family_map.dart`'s
 *       `familyMaxWeight`/`kMainLiftFamilies`. Gated on
 *       `userPublicProfiles/{uid}.rankingOptIn === true` — otherwise writes
 *       `{lifetimeVolumeKg: 0, bestSquatKg: null, bestBenchKg: null,
 *       bestDeadliftKg: null}` so a disabled/never-opted-in athlete's doc
 *       never carries live-looking metrics even if the trigger fires on a
 *       stray session write.
 *   - AD-7: idempotent full-requery (recompute never reads its own previous
 *       output), catch-log-never-rethrow, no-op + warn when the profile doc
 *       is absent (mirrors `review-aggregate.ts`'s REQ-RV-CF-006 shape).
 *
 * Runs in southamerica-east1 (matches reviewAggregate — ADR-RV-003).
 *
 * `sdd/rankings-integrity` Phase 1 (PR#1).
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments).
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Upper bound on how many recent sessions [recomputeMetrics] reads when
 * recomputing ranking metrics. MUST match the Dart client's (now-removed)
 * `SessionRepository.counterRecomputeWindow` — this is the server-side
 * successor to that same bounded window, not an independent choice.
 */
const RECOMPUTE_WINDOW = 365;

/**
 * TS port of `lib/features/gym_rankings/domain/main_lift_family_map.dart`'s
 * `kMainLiftFamilies`. MUST stay in lockstep with the Dart source — a
 * divergence would make server-computed metrics disagree with what the app
 * historically computed for the same athlete.
 */
const K_MAIN_LIFT_FAMILIES = {
  squat: ["squat-barra"],
  bench: ["bench-press-barra"],
  deadlift: ["deadlift-barra", "sumo-deadlift-barra"],
} as const;

type MainLift = keyof typeof K_MAIN_LIFT_FAMILIES;

type SetLogRecord = {
  exerciseId?: string;
  weightKg?: number;
};

/**
 * TS port of `main_lift_family_map.dart`'s `familyMaxWeight`. Returns the max
 * `weightKg` among `logs` whose `exerciseId` belongs to `lift`'s family, or
 * `null` when none match (no PR to report for that lift in this set of logs).
 */
function familyMaxWeight(lift: MainLift, logs: SetLogRecord[]): number | null {
  const familyIds: readonly string[] = K_MAIN_LIFT_FAMILIES[lift];
  let max: number | null = null;
  for (const log of logs) {
    if (!log.exerciseId || !familyIds.includes(log.exerciseId)) continue;
    const weight = log.weightKg ?? 0;
    if (max === null || weight > max) {
      max = weight;
    }
  }
  return max;
}

type RankingMetrics = {
  lifetimeVolumeKg: number;
  bestSquatKg: number | null;
  bestBenchKg: number | null;
  bestDeadliftKg: number | null;
};

const OPTED_OUT_METRICS: RankingMetrics = {
  lifetimeVolumeKg: 0,
  bestSquatKg: null,
  bestBenchKg: null,
  bestDeadliftKg: null,
};

/**
 * Recomputes the 4 ranking-metric fields for `uid` and persists them to
 * `userPublicProfiles/{uid}`.
 *
 * Exported separately to enable direct unit/integration testing without
 * going through the trigger harness. Called by both trigger handlers AND by
 * test suites.
 *
 * Idempotent: always derives the metrics from a full requery of the
 * athlete's own sessions/setLogs — never reads or trusts the previously
 * stored value. This is the core security property of the whole change: a
 * forged stored value is always overwritten by the next recompute,
 * regardless of what was there before.
 */
export async function recomputeMetrics(
  app: admin.app.App,
  uid: string,
): Promise<void> {
  const db = admin.firestore(app);

  try {
    const profileRef = db.collection("userPublicProfiles").doc(uid);
    const profileSnap = await profileRef.get();

    if (!profileSnap.exists) {
      logger.warn(
        `rankingAggregate: userPublicProfiles/${uid} not found — skipping update`,
        { uid },
      );
      return;
    }

    const rankingOptIn = profileSnap.data()?.rankingOptIn === true;

    if (!rankingOptIn) {
      await profileRef.set(OPTED_OUT_METRICS, { merge: true });
      logger.info(
        `rankingAggregate: rankingOptIn is false for ${uid} — wrote default metrics`,
        { uid },
      );
      return;
    }

    // 1. Query the SAME bounded window the Dart client used to read.
    const sessionsSnap = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .orderBy("startedAt", "desc")
      .limit(RECOMPUTE_WINDOW)
      .get();

    const qualifyingDocs = sessionsSnap.docs.filter((doc) => {
      const data = doc.data();
      return data.status === "finished" && data.wasFullyCompleted === true;
    });

    // 2. Sum totalVolumeKg across qualifying sessions.
    const lifetimeVolumeKg = qualifyingDocs.reduce((sum, doc) => {
      const volume = (doc.data().totalVolumeKg as number) ?? 0;
      return sum + volume;
    }, 0);

    // 3. Read setLogs per qualifying session (bounded to the SAME window) to
    // compute each main-lift family's max weight.
    const allLogs: SetLogRecord[] = [];
    for (const doc of qualifyingDocs) {
      const logsSnap = await doc.ref.collection("setLogs").get();
      for (const logDoc of logsSnap.docs) {
        allLogs.push(logDoc.data() as SetLogRecord);
      }
    }

    const update: RankingMetrics = {
      lifetimeVolumeKg,
      bestSquatKg: familyMaxWeight("squat", allLogs),
      bestBenchKg: familyMaxWeight("bench", allLogs),
      bestDeadliftKg: familyMaxWeight("deadlift", allLogs),
    };

    // 4. Merge aggregate fields — never overwrite identity fields.
    await profileRef.set(update, { merge: true });

    logger.info(`rankingAggregate: updated userPublicProfiles/${uid}`, {
      uid,
      ...update,
    });
  } catch (err) {
    // Catch all → log + no rethrow (mirrors reviewAggregate's
    // catch-log-never-rethrow, ADR-RV-001).
    logger.error(`rankingAggregate: error recomputing for uid=${uid}`, {
      uid,
      err,
    });
  }
}

/**
 * Cloud Function trigger — Trigger A (AD-1).
 *
 * Fires on any write (create / update / delete) to
 * `users/{uid}/sessions/{sessionId}`. Cross-collection target
 * (`userPublicProfiles`, a DIFFERENT collection from the trigger's own
 * document) means this trigger's own write never re-fires itself — the same
 * loop-avoidance property `reviewAggregate` relies on.
 *
 * Deployed to southamerica-east1 per ADR-RV-003.
 */
export const rankingAggregateOnSession = onDocumentWritten(
  { document: "users/{uid}/sessions/{sessionId}", region: "southamerica-east1" },
  async (event) => {
    const uid = event.params.uid;
    if (!uid) {
      logger.warn("rankingAggregateOnSession: uid not found in event params", {
        params: event.params,
      });
      return;
    }
    await recomputeMetrics(getApp(), uid);
  },
);

/**
 * Pure guard function for Trigger B (AD-1) — the single check that makes the
 * loop terminate. Returns `true` ONLY on the opt-in ENABLE transition
 * (`before.rankingOptIn` is not `true` AND `after.rankingOptIn === true`).
 *
 * Exported separately from the trigger handler so the loop-termination
 * property can be unit-tested directly and exhaustively without needing to
 * construct a full CloudEvent — this is the load-bearing safety assertion
 * for the whole change (design AD-1: "Loop proof for Trigger B").
 *
 * On the re-fire caused by [recomputeMetrics]'s own merge write,
 * `before.rankingOptIn === after.rankingOptIn === true`, so this returns
 * `false` and the trigger returns immediately with ZERO writes. This is a
 * hard idempotency stop by TRANSITION-equality, not value-equality.
 */
export function shouldRecomputeOnOptInTransition(
  before: { rankingOptIn?: unknown } | undefined,
  after: { rankingOptIn?: unknown } | undefined,
): boolean {
  const beforeOptIn = before?.rankingOptIn === true;
  const afterOptIn = after?.rankingOptIn === true;
  return !beforeOptIn && afterOptIn;
}

/**
 * Cloud Function trigger — Trigger B (AD-1).
 *
 * Fires on any write to `userPublicProfiles/{uid}`, but short-circuits with
 * ZERO writes unless [shouldRecomputeOnOptInTransition] returns `true` for
 * the event's before/after data (the opt-in ENABLE transition). This is what
 * makes a just-opted-in athlete with real training history get their
 * metrics populated without requiring a new session write.
 *
 * Deployed to southamerica-east1 per ADR-RV-003.
 */
export const rankingAggregateOnOptIn = onDocumentWritten(
  { document: "userPublicProfiles/{uid}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!shouldRecomputeOnOptInTransition(before, after)) {
      return;
    }

    const uid = event.params.uid;
    if (!uid) {
      logger.warn("rankingAggregateOnOptIn: uid not found in event params", {
        params: event.params,
      });
      return;
    }
    await recomputeMetrics(getApp(), uid);
  },
);
