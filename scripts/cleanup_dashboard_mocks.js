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

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
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
