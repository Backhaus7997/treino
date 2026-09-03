'use strict';

/**
 * scripts/cleanup_performance_tests.js
 *
 * Deletes every performance test seeded by seed_performance_tests.js,
 * identified by the `seedMock == true` marker. Real data never matched.
 *
 * Usage: node scripts/cleanup_performance_tests.js
 */

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

async function main() {
  const snap = await db
    .collection('performance_tests')
    .where('seedMock', '==', true)
    .get();

  if (snap.empty) {
    console.log('No mock performance tests found. Nothing to delete.');
    return;
  }

  console.log(`Deleting ${snap.size} mock performance tests...`);
  for (const doc of snap.docs) {
    await doc.ref.delete();
    console.log(`  ✗ deleted ${doc.id}`);
  }
  console.log('\nDone. Mock performance tests removed.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Cleanup failed:', err);
    process.exit(1);
  });
