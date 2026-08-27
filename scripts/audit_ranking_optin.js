/**
 * audit_ranking_optin.js
 *
 * #642 — Read-only audit of `rankingOptIn` adoption across `userPublicProfiles`.
 *
 * Why: issue #642 argues the RANKINGS tab's share of the Feed pill is not
 * backed by research (3 of 5 interviewees rejected rankings as a motivator),
 * and blocks itself on real adoption data before choosing between reducing its
 * prominence, gating the tab on opt-in, or moving it out of the Feed entirely.
 * That number did not exist anywhere: no script queried the flag, and the app
 * has no navigation analytics at all (lib/core/analytics/analytics_service.dart
 * defines seven events, none of them navigational; Feed page 0 and page 1 are
 * the same go_router route, so even Firebase's auto-collected `screen_view`
 * cannot tell them apart). This closes the half of the question that IS
 * answerable from data already in Firestore.
 *
 * ⚠️  WHICH PROJECT YOU POINT THIS AT DECIDES WHETHER THE NUMBER MEANS ANYTHING.
 * Since #840 the `.firebaserc` default is `demo-treino` (offline emulator id) and
 * the real project sits behind the `prod` alias — but this script never reads
 * `.firebaserc`: it resolves the project from the service account in
 * `$TREINO_SA_KEY` (#834 — the key lives OUTSIDE the repo now; the frontier in
 * `lib/credenciales.js` rejects any path inside a git tree), or pins
 * `treino-dev` when `FIRESTORE_EMULATOR_HOST` is set. Run against the emulator
 * and you are measuring seed and test accounts — `seed_emulator_full.js` writes
 * `userPublicProfiles` docs directly, so the ratio is whatever the seed author
 * happened to pick. Only a project with real athletes answers #642.
 *
 * ⚠️  A GLOBAL PERCENTAGE CAN LIE HERE. Rankings are scoped per gym
 * (`UserPublicProfileRepository.watchLeaderboard` filters `gymId` +
 * `rankingOptIn`), so an athlete in a gym where nobody opted in sees an empty
 * board no matter what the global number says. The per-gym breakdown below is
 * the figure that actually bears on the product decision; treat the global
 * percentage as a headline, not as the answer.
 *
 * WHAT IT READS (and it only ever reads — this script issues zero writes):
 *   1. Total `userPublicProfiles` docs.
 *   2. How many have `rankingOptIn == true`, and the share.
 *   3. Per-gym breakdown: opted-in / total / share, sorted by gym size.
 *   4. Among the opted-in, how many still have no metrics at all — opted in
 *      but never produced a session that fed the leaderboards. A high count
 *      means adoption is softer than the headline percentage suggests.
 *
 * Counting uses Admin SDK `.count()` aggregation where a plain tally is
 * enough, so the common case is a handful of aggregation queries rather than
 * a full collection download. The per-gym pass does stream the documents,
 * because grouping by an arbitrary `gymId` needs the values themselves.
 * No new composite index is required: the global
 * `where('rankingOptIn','==',true)` count rides the single-field auto-index,
 * and firestore.indexes.json:250-294 already covers the gym-scoped variants.
 *
 * Usage:
 *   # Contra un proyecto real (necesita $TREINO_SA_KEY — ver scripts/README.md):
 *   cd scripts && node audit_ranking_optin.js
 *
 *   # Against the emulator (no credentials):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/audit_ranking_optin.js
 *
 *   # Machine-readable, for pasting into the issue:
 *   cd scripts && node audit_ranking_optin.js --json
 */

'use strict';

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

const asJson = process.argv.includes('--json');

/** Sentinel gymId for "no gym" — mirrors kNoGymId in lib/features/gyms/domain/gym.dart. */
const K_NO_GYM_ID = 'no-gym';

/** The four server-computed fields gated by rankingOptIn (user_public_profile.dart:81-96). */
const METRIC_FIELDS = [
  'lifetimeVolumeKg',
  'bestSquatKg',
  'bestBenchKg',
  'bestDeadliftKg',
];

/** True when the profile has no ranking metric worth showing on a board. */
function hasNoMetrics(data) {
  return METRIC_FIELDS.every((f) => {
    const v = data[f];
    return v === undefined || v === null || v === 0;
  });
}

/** Normalises the gym bucket: null / '' / the no-gym sentinel all collapse. */
function gymBucket(data) {
  const raw = data.gymId;
  if (raw === undefined || raw === null || raw === '' || raw === K_NO_GYM_ID) {
    return null;
  }
  return raw;
}

function pct(part, whole) {
  if (whole === 0) return '—';
  return `${((part / whole) * 100).toFixed(1)}%`;
}

(async () => {
  const projectId =
    process.env.FIRESTORE_EMULATOR_HOST
      ? 'treino-dev (EMULATOR)'
      : admin.app().options.credential.projectId ?? 'unknown';

  const col = db.collection('userPublicProfiles');

  // ── Headline counts, via aggregation (no document download) ──────────────
  const [totalAgg, optedInAgg] = await Promise.all([
    col.count().get(),
    col.where('rankingOptIn', '==', true).count().get(),
  ]);
  const total = totalAgg.data().count;
  const optedIn = optedInAgg.data().count;

  // ── Per-gym breakdown + metric-less opted-in tally ────────────────────────
  // Grouping by an arbitrary gymId needs the values, so this pass streams the
  // documents. Still read-only.
  const perGym = new Map(); // gymId -> { total, optedIn }
  let noGymTotal = 0;
  let noGymOptedIn = 0;
  let optedInWithoutMetrics = 0;

  const snap = await col.get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const isIn = data.rankingOptIn === true;
    const gym = gymBucket(data);

    if (gym === null) {
      noGymTotal++;
      if (isIn) noGymOptedIn++;
    } else {
      const row = perGym.get(gym) ?? { total: 0, optedIn: 0 };
      row.total++;
      if (isIn) row.optedIn++;
      perGym.set(gym, row);
    }

    if (isIn && hasNoMetrics(data)) optedInWithoutMetrics++;
  }

  const gyms = [...perGym.entries()]
    .map(([gymId, row]) => ({ gymId, ...row }))
    .sort((a, b) => b.total - a.total || b.optedIn - a.optedIn);

  const gymsWithNobody = gyms.filter((g) => g.optedIn === 0).length;

  if (asJson) {
    console.log(JSON.stringify({
      projectId,
      total,
      optedIn,
      optedInShare: total === 0 ? null : optedIn / total,
      optedInWithoutMetrics,
      noGym: { total: noGymTotal, optedIn: noGymOptedIn },
      gymsWithNobodyOptedIn: gymsWithNobody,
      gyms,
    }, null, 2));
    return;
  }

  console.log('');
  console.log('rankingOptIn adoption — issue #642');
  console.log(`project: ${projectId}`);
  console.log('');
  console.log(`  userPublicProfiles docs .............. ${total}`);
  console.log(`  rankingOptIn == true ................. ${optedIn}  (${pct(optedIn, total)})`);
  console.log(`  ...of those, with no metrics yet ..... ${optedInWithoutMetrics}` +
    (optedIn > 0 ? `  (${pct(optedInWithoutMetrics, optedIn)} of opted-in)` : ''));
  console.log('');
  console.log(`  profiles with no gym ................. ${noGymTotal}` +
    `  (${noGymOptedIn} opted in — they see the no-gym state, not a board)`);
  console.log('');

  if (gyms.length === 0) {
    console.log('  No gym-scoped profiles found.');
  } else {
    console.log(`  Per gym (${gyms.length} gyms; ${gymsWithNobody} with nobody opted in):`);
    console.log('');
    console.log('    gymId                                opted-in / total   share');
    console.log('    ' + '-'.repeat(66));
    for (const g of gyms) {
      const id = g.gymId.length > 34 ? `${g.gymId.slice(0, 31)}...` : g.gymId.padEnd(34);
      const ratio = `${String(g.optedIn).padStart(3)} / ${String(g.total).padEnd(5)}`;
      console.log(`    ${id}   ${ratio}       ${pct(g.optedIn, g.total)}`);
    }
  }

  console.log('');
  console.log('  Reading this for #642:');
  console.log('    - The per-gym column is the one that matters. Rankings are gym-scoped,');
  console.log('      so a gym with nobody opted in shows an empty board regardless of the');
  console.log('      global share.');
  console.log('    - "no metrics yet" counts athletes who opted in but never fed a board.');
  console.log('      A high share there means adoption is softer than the headline.');
  console.log('    - This answers adoption ONLY. Tab traffic (Feed page 0 vs page 1) is');
  console.log('      not measurable today: no navigation analytics exist, and both pages');
  console.log('      share the /feed route.');
  console.log('');
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
