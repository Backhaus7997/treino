'use strict';

/**
 * scripts/cleanup_performance_tests.js
 *
 * Deletes every performance test seeded by seed_performance_tests.js,
 * identified by the `seedMock == true` marker. Real data never matched.
 *
 * Usage: node scripts/cleanup_performance_tests.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
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
