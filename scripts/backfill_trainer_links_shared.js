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

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
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
