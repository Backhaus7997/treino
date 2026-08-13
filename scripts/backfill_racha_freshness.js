/**
 * backfill_racha_freshness.js
 *
 * #552 — Recomputes the denormalized `racha` on every `userPublicProfiles`
 * doc that has one, and stamps `rachaUpdatedAt` (the freshness field the
 * streak leaderboard's read-time decay relies on).
 *
 * Why: `racha` was a snapshot written at the athlete's last finish() and
 * never decayed — an inactive athlete kept their last streak on the RANKINGS
 * board forever while their own PERFIL (live computeStreak) said 0. The app
 * now decays the stored value at read using `rachaUpdatedAt`, but docs
 * written before the fix have no stamp and pass through undecayed until this
 * script runs (or until the athlete's next finish, which stamps it).
 *
 * For each profile doc with a `racha` field:
 *   1. Reads the athlete's newest sessions (bounded to the same 365-doc
 *      window `SessionRepository.finish` / functions/src/ranking-aggregate.ts
 *      use — RECOMPUTE_WINDOW lockstep).
 *   2. Recomputes the CURRENT streak with the JS port of
 *      lib/core/utils/streak_calculator.dart (ART calendar frame, UTC-3
 *      fixed, no DST).
 *   3. Writes `racha` (healed value) + `rachaUpdatedAt` = the newest
 *      completed session's `startedAt` (the instant the streak was last
 *      earned — NOT "now", so the read-time decay judges freshness by the
 *      real last workout, mirroring what a finish()-time stamp would hold).
 *      Athletes with no completed sessions get racha 0 stamped at epoch.
 *
 * ⚠️  DEPLOY ORDER: run this ONLY AFTER the #552 firestore.rules are
 * deployed. The rules' `hasOnly` field allowlist rejects any client update
 * whose post-merge doc carries an unknown key — stamping docs under the OLD
 * rules would brick every subsequent client-side profile update for those
 * users. (This script itself bypasses rules via Admin SDK; the hazard is for
 * the app writes that come after.)
 *
 * Idempotent: docs whose stored racha already matches the recomputed value
 * AND already have a stamp are skipped. Re-runs write nothing new.
 *
 * Usage:
 *   # Production (needs scripts/sa-key.json, gitignored):
 *   cd scripts && node backfill_racha_freshness.js           # writes
 *   cd scripts && node backfill_racha_freshness.js --dry-run # logs only
 *
 *   # Emulator (no credentials — same pattern as backfill_athlete_counts.js):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_racha_freshness.js
 */

'use strict';

const admin = require('firebase-admin');

if (process.env.FIRESTORE_EMULATOR_HOST) {
  // Admin SDK with emulator — no service account needed.
  admin.initializeApp({ projectId: 'treino-dev' });
} else {
  let serviceAccount;
  try {
    serviceAccount = require('./sa-key.json');
  } catch (err) {
    if (err.code !== 'MODULE_NOT_FOUND') throw err;
    console.error(
      '\nERROR: scripts/sa-key.json not found — required to run against production.\n' +
      'Download a service-account key from the Firebase console and save it as\n' +
      'scripts/sa-key.json (gitignored), or target the local emulator instead:\n\n' +
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_racha_freshness.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const dryRun = process.argv.includes('--dry-run');

/** Same bounded window as SessionRepository.counterRecomputeWindow and
 * ranking-aggregate.ts RECOMPUTE_WINDOW — MUST stay in lockstep. */
const RECOMPUTE_WINDOW = 365;

/** Argentina fixed offset (UTC-3, no DST since 2009) — port of
 * lib/core/utils/argentina_time.dart. */
const ART_OFFSET_MS = 3 * 60 * 60 * 1000;

/** ART calendar day of a JS Date, as an epoch-days integer (UTC-frame math on
 * the shifted instant — same trick as toArgentina + DateTime.utc(y,m,d)). */
function artDay(date) {
  return Math.floor((date.getTime() - ART_OFFSET_MS) / 86400000);
}

/**
 * Port of computeStreak (lib/core/utils/streak_calculator.dart): unique ART
 * calendar days with a completed session; count back from today, or from
 * yesterday when today has no workout.
 *
 * @param {Date[]} startedAts startedAt of completed sessions
 * @param {Date} now real instant
 * @returns {number} current streak in days
 */
function computeStreak(startedAts, now) {
  const trained = new Set(startedAts.map(artDay));
  const today = artDay(now);

  let streak = 0;
  let cursor = today;
  while (trained.has(cursor)) {
    streak++;
    cursor--;
  }
  if (streak === 0) {
    cursor = today - 1;
    while (trained.has(cursor)) {
      streak++;
      cursor--;
    }
  }
  return streak;
}

(async () => {
  const profiles = await db.collection('userPublicProfiles').get();
  console.log(`Found ${profiles.size} userPublicProfiles doc(s).`);
  if (dryRun) console.log('(dry-run: no writes will be issued)');
  console.log('');

  const now = new Date();
  let updated = 0;
  let alreadyOk = 0;
  let skippedNoRacha = 0;

  for (const doc of profiles.docs) {
    const data = doc.data();
    if (data.racha === undefined || data.racha === null) {
      // Never trained / counters never written — nothing to heal or stamp.
      skippedNoRacha++;
      continue;
    }

    const sessionsSnap = await db
      .collection('users')
      .doc(doc.id)
      .collection('sessions')
      .orderBy('startedAt', 'desc')
      .limit(RECOMPUTE_WINDOW)
      .get();

    // Same filter as SessionRepository.listRecentCompletedByUid: finished
    // AND fully completed (abandoned sessions never count toward a streak).
    const completedStarts = [];
    for (const s of sessionsSnap.docs) {
      const sd = s.data();
      if (sd.status !== 'finished' || sd.wasFullyCompleted !== true) continue;
      if (!sd.startedAt || typeof sd.startedAt.toDate !== 'function') continue;
      completedStarts.push(sd.startedAt.toDate());
    }

    const racha = computeStreak(completedStarts, now);
    // Newest completed startedAt = the instant the streak was last earned.
    const lastTrained = completedStarts.length
      ? completedStarts.reduce((a, b) => (a > b ? a : b))
      : new Date(0);

    if (data.racha === racha && data.rachaUpdatedAt !== undefined) {
      alreadyOk++;
      continue;
    }

    console.log(
      `${doc.id}: racha ${data.racha} -> ${racha}, ` +
      `rachaUpdatedAt -> ${lastTrained.toISOString()}` +
      (dryRun ? ' (dry-run)' : ''),
    );

    if (!dryRun) {
      await doc.ref.set(
        {
          racha,
          rachaUpdatedAt: admin.firestore.Timestamp.fromDate(lastTrained),
        },
        { merge: true },
      );
    }
    updated++;
  }

  console.log('');
  console.log(
    `Done. ${updated} updated, ${alreadyOk} already ok, ` +
    `${skippedNoRacha} without racha (skipped).`,
  );
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
