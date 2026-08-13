'use strict';

/**
 * scripts/cleanup_dashboard_mocks.js
 *
 * Deletes everything seeded by seed_dashboard_mocks.js, identified by the
 * `seedMock == true` marker field:
 *   - appointments
 *   - session_shares/{athleteId} grant
 *   - users/{athleteId}/sessions finished-today mocks
 * Real data is never matched.
 *
 * Usage:
 *   node scripts/cleanup_dashboard_mocks.js
 */

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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/cleanup_dashboard_mocks.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const ACTIVE_ATHLETE_ID = 'UVjNGDxHc1PB6GppssbLEu8htRS2';

async function deleteWhereSeedMock(label, query) {
  const snap = await query.get();
  if (snap.empty) {
    console.log(`  ${label}: nothing to delete`);
    return;
  }
  for (const doc of snap.docs) {
    await doc.ref.delete();
    console.log(`  ✗ ${label}: deleted ${doc.ref.path}`);
  }
}

async function main() {
  console.log('Cleaning up dashboard mocks...\n');

  await deleteWhereSeedMock(
    'appointments',
    db.collection('appointments').where('seedMock', '==', true),
  );

  await deleteWhereSeedMock(
    'session_shares',
    db.collection('session_shares').where('seedMock', '==', true),
  );

  await deleteWhereSeedMock(
    'sessions',
    db
      .collection('users')
      .doc(ACTIVE_ATHLETE_ID)
      .collection('sessions')
      .where('seedMock', '==', true),
  );

  console.log('\nDone. Dashboard mocks removed.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Cleanup failed:', err);
    process.exit(1);
  });
