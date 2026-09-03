'use strict';

/**
 * scripts/cleanup_measurements.js
 *
 * Deletes every measurement seeded by seed_measurements.js, identified by the
 * `seedMock == true` marker. Real measurements are never matched.
 *
 * Usage:
 *   node scripts/cleanup_measurements.js
 */

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

async function main() {
  const snap = await db
    .collection('measurements')
    .where('seedMock', '==', true)
    .get();

  if (snap.empty) {
    console.log('No mock measurements found. Nothing to delete.');
    return;
  }

  console.log(`Deleting ${snap.size} mock measurements...`);
  for (const doc of snap.docs) {
    await doc.ref.delete();
    console.log(`  ✗ deleted ${doc.id}`);
  }
  console.log('\nDone. Mock measurements removed.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Cleanup failed:', err);
    process.exit(1);
  });
