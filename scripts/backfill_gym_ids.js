'use strict';

/**
 * backfill_gym_ids.js
 *
 * gyms-foundation Phase 4 (backfill 1 of 2 — RUN THIS FIRST).
 *
 * Legacy `gymId` remap: three ids used to be hardcoded strings understood
 * only by the retired `gymNameFromId` map (`smart-fit-palermo`,
 * `sportclub-belgrano`, `megatlon-recoleta`). After the Phase 1 seed rewrite
 * (`scripts/seed_gyms.js`) all three now exist as REAL `gyms/{id}` docs with
 * the SAME id (1:1 identity remap) — `megatlon-recoleta` was reused as-is,
 * `smart-fit-palermo`/`sportclub-belgrano` were added as new real sucursal
 * docs under their brands. So for these three there is nothing to rewrite;
 * this script's job is to VERIFY every user's `gymId` resolves to a real
 * `gyms/` doc, and to CORRECT any other stale/unknown id it finds by mapping
 * it to `kNoGymId` (safe fallback — never guesses a replacement doc).
 *
 * Idempotent: re-running is a no-op for users whose `gymId` already resolves
 * (or is already `null`/`kNoGymId`). Dual-writes `users/{uid}` +
 * `userPublicProfiles/{uid}` only when a change is actually needed.
 *
 * MUST run BEFORE `backfill_gym_names.js` (name backfill resolves against
 * the ids this script corrects).
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE
 * ────────────────────────────────────────────────────────────────────────────
 *   cd scripts && npm install   # once, if not already done
 *
 *   # Dry run (default-safe) — reports what WOULD change, writes nothing:
 *   node scripts/backfill_gym_ids.js --dry-run
 *
 *   # Real run against treino-dev (sa-key.json's project):
 *   node scripts/backfill_gym_ids.js
 *
 *   # Only if you explicitly intend to run against a non-dev project
 *   # (e.g. treino-prod), after dev verification + maintainer sign-off:
 *   node scripts/backfill_gym_ids.js --allow-prod
 *
 * Requires `sa-key.json` (Firebase service account, gitignored) in scripts/
 * — see scripts/README.md / backfill_user_public_profiles.js for setup.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SAFETY
 * ────────────────────────────────────────────────────────────────────────────
 * - Refuses to run against any Firebase project whose id doesn't contain
 *   "dev" (case-insensitive), unless `--allow-prod` is passed explicitly.
 * - Prints the target project_id before doing anything.
 * - `--dry-run` performs zero writes; every action is logged as "WOULD".
 * - Prints a final VERIFIED COUNT: how many users/profiles have a `gymId`
 *   that now resolves to a real `gyms/` doc (or are `null`/`kNoGymId`).
 */

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');

const PROJECT_ID = serviceAccount.project_id;

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Legacy ids that are now known to exist as real `gyms/` docs with the SAME
// id (1:1 identity — Phase 1 seed rewrite created/kept them). Kept explicit
// here (rather than assumed) so the script documents intent and still
// VERIFIES each one actually resolves before treating it as fine.
const KNOWN_LEGACY_IDS = [
  'smart-fit-palermo',
  'sportclub-belgrano',
  'megatlon-recoleta',
];

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    dryRun: args.includes('--dry-run'),
    allowProd: args.includes('--allow-prod'),
  };
}

function assertDevProject(allowProd) {
  console.log(`Target Firebase project: ${PROJECT_ID}`);
  const looksLikeDev = /dev/i.test(PROJECT_ID);
  if (!looksLikeDev && !allowProd) {
    console.error(
      `\nREFUSING TO RUN: project_id "${PROJECT_ID}" does not look like a ` +
        'dev project. This script is dev-first. If you really intend to run ' +
        'against this project (e.g. treino-prod, after dev verification and ' +
        'maintainer sign-off), re-run with --allow-prod.',
    );
    process.exit(1);
  }
  if (!looksLikeDev && allowProd) {
    console.warn(`\n⚠ --allow-prod passed. Proceeding against "${PROJECT_ID}".\n`);
  }
}

/** Fetches the set of valid gym doc ids currently in `gyms/`. */
async function fetchValidGymIds() {
  const snap = await db.collection('gyms').select().get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * Decides the corrected `gymId` for a user/profile doc.
 * Returns `null` if no change is needed.
 */
function resolveCorrectedGymId(currentGymId, validGymIds) {
  if (currentGymId === undefined) return null; // field absent — leave untouched
  if (currentGymId === null || currentGymId === 'no-gym') return null; // already sentinel/no-gym
  if (validGymIds.has(currentGymId)) return null; // resolves to a real doc already

  // Unknown/stale id that isn't one of the three known-remapped legacy ids
  // (those are expected to resolve via validGymIds above; if they DON'T,
  // something upstream broke the seed and this falls through here too).
  // Safe fallback: map to kNoGymId rather than guessing a replacement.
  return 'no-gym';
}

async function processCollection(collectionName, validGymIds, dryRun) {
  const snap = await db.collection(collectionName).get();
  let verified = 0;
  let corrected = 0;
  let untouched = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const currentGymId = Object.prototype.hasOwnProperty.call(data, 'gymId')
      ? data.gymId
      : undefined;

    if (currentGymId === undefined) {
      untouched++;
      continue;
    }

    const corrected_ = resolveCorrectedGymId(currentGymId, validGymIds);

    if (corrected_ === null) {
      verified++;
      continue;
    }

    corrected++;
    if (dryRun) {
      console.log(
        `  [DRY-RUN] WOULD update ${collectionName}/${doc.id}: gymId "${currentGymId}" -> "${corrected_}"`,
      );
    } else {
      await doc.ref.set({ gymId: corrected_ }, { merge: true });
      console.log(
        `  ✓ ${collectionName}/${doc.id}: gymId "${currentGymId}" -> "${corrected_}"`,
      );
    }
  }

  return { verified, corrected, untouched, total: snap.size };
}

async function run() {
  const { dryRun, allowProd } = parseArgs();
  assertDevProject(allowProd);

  if (dryRun) {
    console.log('Running in --dry-run mode. No writes will be performed.\n');
  }

  console.log('Fetching valid gym ids from `gyms/`...');
  const validGymIds = await fetchValidGymIds();
  console.log(`  ${validGymIds.size} valid gym docs found.`);

  for (const legacyId of KNOWN_LEGACY_IDS) {
    const ok = validGymIds.has(legacyId);
    console.log(`  Legacy id check: "${legacyId}" ${ok ? 'OK (resolves to real doc)' : 'MISSING — unexpected, investigate seed'}`);
  }

  console.log('\nProcessing users/{uid}...');
  const usersResult = await processCollection('users', validGymIds, dryRun);

  console.log('\nProcessing userPublicProfiles/{uid}...');
  const profilesResult = await processCollection('userPublicProfiles', validGymIds, dryRun);

  const verifiedCount = usersResult.verified + profilesResult.verified;
  const correctedCount = usersResult.corrected + profilesResult.corrected;

  console.log('\n──────────────────────────────────────────────');
  console.log(`${dryRun ? 'DRY-RUN SUMMARY' : 'SUMMARY'}`);
  console.log('──────────────────────────────────────────────');
  console.log(
    `users:               total=${usersResult.total} verified=${usersResult.verified} ${dryRun ? 'would-correct' : 'corrected'}=${usersResult.corrected} untouched(no gymId field)=${usersResult.untouched}`,
  );
  console.log(
    `userPublicProfiles:  total=${profilesResult.total} verified=${profilesResult.verified} ${dryRun ? 'would-correct' : 'corrected'}=${profilesResult.corrected} untouched(no gymId field)=${profilesResult.untouched}`,
  );
  console.log(`\nVERIFIED COUNT: ${verifiedCount} docs already resolve to a real gym doc or a safe sentinel.`);
  console.log(`${dryRun ? 'WOULD CORRECT' : 'CORRECTED'} COUNT: ${correctedCount} docs.`);
  console.log(
    dryRun
      ? '\nDry run complete. Re-run without --dry-run to apply.'
      : '\nBackfill complete. Safe to re-run at any time (idempotent).',
  );
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err);
    process.exit(1);
  });
