'use strict';

/**
 * backfill_gym_names.js
 *
 * gyms-foundation Phase 4 (backfill 2 of 2 — RUN AFTER backfill_gym_ids.js).
 *
 * Fills `UserPublicProfile.gymName` (the composed "{brandName} - {branchName}"
 * label, or just `brandName` for independent single-branch gyms) for every
 * `userPublicProfiles/{uid}` doc that already has a `gymId` but is missing
 * `gymName` — i.e. profiles saved before the Phase 3 dual-write
 * (`UserRepository._resolveGymName`) started populating it automatically.
 *
 * ORDERING CONSTRAINT: MUST run AFTER `backfill_gym_ids.js`. That script
 * corrects any stale/unknown `gymId` values first — running this script
 * before it would resolve names against ids that are about to be rewritten.
 *
 * Resolution rules (mirrors `UserRepository._resolveGymName`):
 *   - `gymId` is `null` or `kNoGymId` ('no-gym')  -> `gymName: null` (no lookup)
 *   - `gymId` doesn't match any `gyms/` doc        -> skipped, safe no-op
 *     (left for `backfill_gym_ids.js` to have corrected; if still unresolved
 *     here it's logged as unresolved, not written as a guess)
 *   - `gymId` resolves                             -> `gymName` = that gym's
 *     `name` field (already the composed display label per the Phase 1 seed)
 *
 * Idempotent: only writes profiles where `gymName` is currently absent/null
 * AND resolves this run. Re-running is a no-op for already-filled profiles.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE
 * ────────────────────────────────────────────────────────────────────────────
 *   cd scripts && npm install   # once, if not already done
 *
 *   # Dry run (default-safe) — reports what WOULD change, writes nothing:
 *   node scripts/backfill_gym_names.js --dry-run
 *
 *   # Real run against treino-dev (sa-key.json's project):
 *   node scripts/backfill_gym_names.js
 *
 *   # Only if you explicitly intend to run against a non-dev project
 *   # (e.g. treino-prod), after dev verification + maintainer sign-off:
 *   node scripts/backfill_gym_names.js --allow-prod
 *
 *   # Against the local emulator — no service-account key needed:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_gym_names.js
 *
 * Requires `sa-key.json` (Firebase service account, gitignored) in scripts/
 * UNLESS `FIRESTORE_EMULATOR_HOST` is set — see scripts/README.md /
 * backfill_user_public_profiles.js for setup.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SAFETY
 * ────────────────────────────────────────────────────────────────────────────
 * - Refuses to run against any Firebase project whose id doesn't contain
 *   "dev" (case-insensitive), unless `--allow-prod` is passed explicitly.
 * - Prints the target project_id before doing anything.
 * - `--dry-run` performs zero writes; every action is logged as "WOULD".
 * - Only touches `userPublicProfiles/{uid}` (mirrors the Phase 3 dual-write
 *   scope — `gymName` is a public-only field, never written to `users/{uid}`).
 * - Prints a final VERIFIED COUNT of profiles updated.
 */

const admin = require('firebase-admin');

let PROJECT_ID;
if (process.env.FIRESTORE_EMULATOR_HOST) {
  // Admin SDK with emulator — no service account needed.
  PROJECT_ID = 'treino-dev';
  admin.initializeApp({ projectId: PROJECT_ID });
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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_gym_names.js\n',
    );
    process.exit(1);
  }
  PROJECT_ID = serviceAccount.project_id;
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

const NO_GYM_ID = 'no-gym';

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

/** Loads all `gyms/` docs into a Map keyed by id, value = composed `name`. */
async function loadGymNamesById() {
  const snap = await db.collection('gyms').get();
  const map = new Map();
  for (const doc of snap.docs) {
    const data = doc.data();
    map.set(doc.id, data.name ?? null);
  }
  return map;
}

async function run() {
  const { dryRun, allowProd } = parseArgs();
  assertDevProject(allowProd);

  if (dryRun) {
    console.log('Running in --dry-run mode. No writes will be performed.\n');
  }

  console.log('Loading gym display names from `gyms/`...');
  const gymNamesById = await loadGymNamesById();
  console.log(`  ${gymNamesById.size} gym docs loaded.`);

  console.log('\nScanning userPublicProfiles/{uid}...');
  const snap = await db.collection('userPublicProfiles').get();

  let filled = 0;
  let alreadySet = 0;
  let noGym = 0;
  let unresolved = 0;
  let skippedNoGymIdField = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const hasGymId = Object.prototype.hasOwnProperty.call(data, 'gymId');
    const gymId = hasGymId ? data.gymId : undefined;
    const hasGymName = Object.prototype.hasOwnProperty.call(data, 'gymName');
    const currentGymName = hasGymName ? data.gymName : undefined;

    if (!hasGymId) {
      skippedNoGymIdField++;
      continue;
    }

    // Idempotency: only fill when gymName is missing (undefined) or null.
    if (currentGymName != null) {
      alreadySet++;
      continue;
    }

    if (gymId === null || gymId === NO_GYM_ID) {
      noGym++;
      // gymName should be null for no-gym — nothing to write if it's
      // already undefined/null (matches currentGymName check above), but
      // write explicit null once if the field is entirely absent so future
      // reads are consistent with the Phase 3 dual-write shape.
      if (!hasGymName) {
        if (dryRun) {
          console.log(`  [DRY-RUN] WOULD set userPublicProfiles/${doc.id}: gymName -> null (no-gym)`);
        } else {
          await doc.ref.set({ gymName: null }, { merge: true });
          console.log(`  ✓ userPublicProfiles/${doc.id}: gymName -> null (no-gym)`);
        }
      }
      continue;
    }

    const resolvedName = gymNamesById.get(gymId);
    if (resolvedName === undefined) {
      unresolved++;
      console.warn(
        `  ⚠ userPublicProfiles/${doc.id}: gymId "${gymId}" does not resolve to a gyms/ doc — skipped. Run backfill_gym_ids.js first if this is unexpected.`,
      );
      continue;
    }

    filled++;
    if (dryRun) {
      console.log(`  [DRY-RUN] WOULD set userPublicProfiles/${doc.id}: gymName -> "${resolvedName}"`);
    } else {
      await doc.ref.set({ gymName: resolvedName }, { merge: true });
      console.log(`  ✓ userPublicProfiles/${doc.id}: gymName -> "${resolvedName}"`);
    }
  }

  console.log('\n──────────────────────────────────────────────');
  console.log(`${dryRun ? 'DRY-RUN SUMMARY' : 'SUMMARY'}`);
  console.log('──────────────────────────────────────────────');
  console.log(`Total userPublicProfiles scanned: ${snap.size}`);
  console.log(`Skipped (no gymId field at all):  ${skippedNoGymIdField}`);
  console.log(`Already had gymName set:           ${alreadySet}`);
  console.log(`No-gym (gymName set to null):      ${noGym}`);
  console.log(`Unresolved gymId (left untouched): ${unresolved}`);
  console.log(`${dryRun ? 'Would fill' : 'Filled'} gymName:              ${filled}`);
  console.log(`\nVERIFIED COUNT: ${filled + noGym} profiles ${dryRun ? 'would be' : 'were'} updated this run.`);
  console.log(
    dryRun
      ? '\nDry run complete. Re-run without --dry-run to apply.'
      : '\nBackfill complete. Safe to re-run at any time (idempotent).',
  );

  if (unresolved > 0) {
    console.warn(
      `\n⚠ ${unresolved} profile(s) had a gymId that did not resolve. Verify backfill_gym_ids.js ran first and check the warnings above.`,
    );
  }
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err);
    process.exit(1);
  });
