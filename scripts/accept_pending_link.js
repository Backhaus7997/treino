/**
 * accept_pending_link.js
 *
 * Smoke-test helper: accepts the most recent pending trainer_link where
 * `trainerId` matches the given trainer email's uid. Mirrors the
 * `TrainerLinkRepository.accept()` transition (pending → active).
 *
 * USAGE
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
 *   node scripts/accept_pending_link.js <trainer-email>
 */

'use strict';

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function run() {
  const email = process.argv[2];
  if (!email) {
    console.error('USAGE: node scripts/accept_pending_link.js <trainer-email>');
    process.exit(1);
  }

  const user = await admin.auth().getUserByEmail(email);
  console.log(`Trainer uid: ${user.uid}`);

  const snap = await db
    .collection('trainer_links')
    .where('trainerId', '==', user.uid)
    .where('status', '==', 'pending')
    .orderBy('requestedAt', 'desc')
    .limit(1)
    .get();

  if (snap.empty) {
    console.log('No hay vínculos pendientes para este trainer.');
    process.exit(0);
  }

  const doc = snap.docs[0];
  await doc.ref.update({
    status: 'active',
    acceptedAt: admin.firestore.Timestamp.fromDate(new Date()),
  });
  console.log(`✓ Link ${doc.id} aceptado.`);
  console.log(`  athleteId: ${doc.get('athleteId')}`);
  console.log('\nEl atleta ya está vinculado. Ahora podés:');
  console.log('  1. Asignar el plan desde el Coach Hub (refrescar para ver al atleta en el dropdown).');
  console.log('  2. Verificar el plan en mobile entrando a ENTRENAR.');
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
