/**
 * backfill_routine_visibility.js
 *
 * Backfills the `visibility` and `source` fields on every doc in the
 * `routines` collection that's missing them. The seeded plantillas
 * (Fase 2) were written without these fields — that was fine while there
 * was no `trainer-assigned` doc in the collection, but Fase 5 Etapa 4
 * introduced private docs, which means the `listAll()` query now needs an
 * explicit `where('visibility', whereIn: ['public', 'shared'])` filter to
 * pass Firestore rules. That filter requires every public doc to actually
 * carry the field.
 *
 * Defaults:
 *   - missing `visibility` → 'public'  (seeded plantillas are public)
 *   - missing `source`     → 'system'  (seeded plantillas are system catalog)
 *
 * Idempotent: docs that already have both fields are skipped.
 *
 * Usage:
 *   cd scripts && node backfill_routine_visibility.js
 */

'use strict';

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('routines').get();
  console.log(`Found ${snap.size} routine doc(s).\n`);

  let toBackfill = 0;
  let alreadyOk = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const update = {};
    if (!('visibility' in data)) update.visibility = 'public';
    if (!('source' in data)) update.source = 'system';

    if (Object.keys(update).length === 0) {
      alreadyOk++;
      continue;
    }
    toBackfill++;
    console.log(`  → ${doc.id} (${data.name ?? '?'}): adding ${JSON.stringify(update)}`);
    batch.update(doc.ref, update);
    batchCount++;
    if (batchCount === 400) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) await batch.commit();

  console.log(`\n✓ Backfilled ${toBackfill} doc(s). ${alreadyOk} already had both fields.`);
})()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err.message);
    process.exit(1);
  });
