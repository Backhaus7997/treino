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

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
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
