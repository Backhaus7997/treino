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
 * the SAME id (1:1 identity remap). So for these three there is nothing to
 * rewrite; this script's job is to VERIFY every user's `gymId` resolves to a
 * real `gyms/` doc, and to CORRECT any other stale/unknown id it finds by
 * mapping it to `kNoGymId` (safe fallback — never guesses a replacement doc).
 *
 * RECONCILES PER UID: `users/{uid}` is the source of truth for `gymId`; its
 * value is mirrored (denormalized) onto `userPublicProfiles/{uid}`. This
 * script computes ONE canonical corrected value per uid and writes it to BOTH
 * docs in a single atomic batch, so the two collections can never disagree
 * after the migration (UI/search read the public profile, profile/post flows
 * read `users` — a split would put the same athlete in two gyms).
 *
 * Idempotent: re-running is a no-op for uids whose `gymId` already resolves
 * (or is already `null`/`kNoGymId`) and already agrees across both docs.
 *
 * MUST run BEFORE `backfill_gym_names.js` (name backfill resolves against
 * the ids this script corrects).
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE  (run from the REPO ROOT — paths below are repo-root-relative)
 * ────────────────────────────────────────────────────────────────────────────
 *   (cd scripts && npm install)   # once — subshell keeps cwd at repo root
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
 * - Prints a final VERIFIED COUNT of uids whose `gymId` now resolves to a
 *   real `gyms/` doc (or is `null`/`kNoGymId`) and agrees across both docs.
 */

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');

const PROJECT_ID = serviceAccount.project_id;
const NO_GYM = 'no-gym';

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

/** Reads the `gymId` field state from a doc's data. */
function readGymId(data) {
  if (!Object.prototype.hasOwnProperty.call(data, 'gymId')) {
    return { hasField: false, value: undefined };
  }
  return { hasField: true, value: data.gymId };
}

/**
 * Computes the single canonical corrected `gymId` for a uid, given the state
 * of both docs. `users/{uid}` is the source of truth; if it has no gymId we
 * fall back to the public profile's value rather than wiping a real gym.
 *
 * Returns:
 *   - a real gym id  → both docs should store exactly this
 *   - NO_GYM         → stale/unknown id; both docs should be the sentinel
 *   - undefined      → no gym set anywhere; nothing to reconcile
 */
function computeTarget(users, pub, validGymIds) {
  let canonical;
  if (users.hasField && users.value !== undefined) {
    canonical = users.value;
  } else if (pub.hasField && pub.value !== undefined) {
    canonical = pub.value;
  } else {
    return undefined; // no field anywhere
  }

  if (canonical === null || canonical === NO_GYM) return NO_GYM;
  if (validGymIds.has(canonical)) return canonical;
  return NO_GYM; // stale / unknown id — safe fallback
}

/**
 * Decides whether an existing doc needs a write to reach `target`, and what
 * the human-readable "from" value is (for logging). Returns null if no write.
 */
function planDocWrite(state, target) {
  if (state.hasField) {
    // Treat null as equivalent to the NO_GYM sentinel for comparison.
    const current = state.value === null ? NO_GYM : state.value;
    if (current === target) return null; // already correct
    return { from: state.value === null ? 'null' : `"${state.value}"`, to: target };
  }
  // Field absent: only add it when target is a REAL gym id (mirror the
  // canonical). Don't add a NO_GYM field to a doc that simply has none —
  // absent already means "no gym", and we avoid churn.
  if (target !== NO_GYM) return { from: '(absent)', to: target };
  return null;
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
    console.log(
      `  Legacy id check: "${legacyId}" ${ok ? 'OK (resolves to real doc)' : 'MISSING — unexpected, investigate seed'}`,
    );
  }

  console.log('\nLoading users/ and userPublicProfiles/ ...');
  const [usersSnap, profilesSnap] = await Promise.all([
    db.collection('users').get(),
    db.collection('userPublicProfiles').get(),
  ]);

  // Index both collections by uid so we can reconcile per uid.
  const usersByUid = new Map();
  for (const doc of usersSnap.docs) {
    usersByUid.set(doc.id, { ref: doc.ref, ...readGymId(doc.data()) });
  }
  const profilesByUid = new Map();
  for (const doc of profilesSnap.docs) {
    profilesByUid.set(doc.id, { ref: doc.ref, ...readGymId(doc.data()) });
  }

  const allUids = new Set([...usersByUid.keys(), ...profilesByUid.keys()]);
  console.log(
    `  users=${usersSnap.size}  userPublicProfiles=${profilesSnap.size}  distinct uids=${allUids.size}`,
  );

  const ABSENT = { hasField: false, value: undefined };
  let verified = 0; // uids already consistent + resolving
  let corrected = 0; // uids that needed ≥1 write
  let noGym = 0; // uids with no gym anywhere (skipped)
  let docWrites = 0;

  console.log('');
  for (const uid of allUids) {
    const users = usersByUid.get(uid) || ABSENT;
    const pub = profilesByUid.get(uid) || ABSENT;

    const target = computeTarget(users, pub, validGymIds);
    if (target === undefined) {
      noGym++;
      continue;
    }

    // Plan writes for each doc that EXISTS (we never create missing docs here).
    const writes = [];
    if (usersByUid.has(uid)) {
      const plan = planDocWrite(users, target);
      if (plan) writes.push({ coll: 'users', ref: users.ref, plan });
    }
    if (profilesByUid.has(uid)) {
      const plan = planDocWrite(pub, target);
      if (plan) writes.push({ coll: 'userPublicProfiles', ref: pub.ref, plan });
    }

    if (writes.length === 0) {
      verified++;
      continue;
    }

    corrected++;
    docWrites += writes.length;

    if (dryRun) {
      for (const w of writes) {
        console.log(
          `  [DRY-RUN] WOULD update ${w.coll}/${uid}: gymId ${w.plan.from} -> "${w.plan.to}"`,
        );
      }
    } else {
      // Single atomic batch per uid → both docs move together, never split.
      const batch = db.batch();
      for (const w of writes) {
        batch.set(w.ref, { gymId: target }, { merge: true });
      }
      await batch.commit();
      for (const w of writes) {
        console.log(
          `  ✓ ${w.coll}/${uid}: gymId ${w.plan.from} -> "${w.plan.to}"`,
        );
      }
    }
  }

  console.log('\n──────────────────────────────────────────────');
  console.log(`${dryRun ? 'DRY-RUN SUMMARY' : 'SUMMARY'}`);
  console.log('──────────────────────────────────────────────');
  console.log(`distinct uids scanned:        ${allUids.size}`);
  console.log(`already consistent (verified): ${verified}`);
  console.log(`no gym set (skipped):          ${noGym}`);
  console.log(
    `${dryRun ? 'would-correct' : 'corrected'} uids:              ${corrected}  (${docWrites} doc write${docWrites === 1 ? '' : 's'} across both collections)`,
  );
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
