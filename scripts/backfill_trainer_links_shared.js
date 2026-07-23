/**
 * backfill_trainer_links_shared.js
 *
 * Backfills the `sharedWithTrainer` field on every doc in the
 * `trainer_links` collection that lacks it. Existing docs were created
 * before Fase 5 · Tech Debt introduced the privacy gate; the Dart model
 * decodes a missing key as `false` via `@Default(false)`, but the
 * Firestore rule on `update` reads `resource.data.sharedWithTrainer`
 * directly. If the key is absent and the athlete tries to flip it,
 * `resource.data.sharedWithTrainer != request.resource.data.sharedWithTrainer`
 * trivially evaluates `true`, so the rule's OR clause is the only thing
 * gating the request — but the rule comparison itself relies on the field
 * existing on both sides for stable semantics. Stamping `false`
 * explicitly normalises the schema and is required by REQ-COACH-LINK-001.
 *
 * Defaults:
 *   - missing `sharedWithTrainer` → `false`  (preserves prior privacy stance)
 *
 * Idempotent: docs that already have the field are skipped. Re-runs
 * write nothing.
 *
 * Usage:
 *   cd scripts && node backfill_trainer_links_shared.js          # writes
 *   cd scripts && node backfill_trainer_links_shared.js --dry-run # logs only
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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_trainer_links_shared.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const dryRun = process.argv.includes('--dry-run');

(async () => {
  const snap = await db.collection('trainer_links').get();
  console.log(`Found ${snap.size} trainer_links doc(s).`);
  if (dryRun) console.log('(dry-run: no writes will be issued)');
  console.log('');

  let toBackfill = 0;
  let alreadyOk = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if ('sharedWithTrainer' in data) {
      alreadyOk++;
      continue;
    }
    toBackfill++;
    console.log(
      `  → ${doc.id} (trainer=${data.trainerId ?? '?'}, athlete=${data.athleteId ?? '?'}): adding sharedWithTrainer=false`,
    );
    if (!dryRun) {
      batch.update(doc.ref, { sharedWithTrainer: false });
      batchCount++;
      if (batchCount === 400) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }
  }

  if (!dryRun && batchCount > 0) await batch.commit();

  console.log(
    `\n${dryRun ? '[dry-run] would backfill' : '✓ Backfilled'} ${toBackfill} doc(s). ${alreadyOk} already had the field.`,
  );
})()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err.message);
    process.exit(1);
  });
