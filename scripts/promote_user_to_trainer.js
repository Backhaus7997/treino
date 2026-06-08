'use strict';

/**
 * promote_user_to_trainer.js
 *
 * Flips `users/{uid}.role` to `'trainer'`. Trainer profile fields are NOT
 * seeded — the user must complete the in-app onboarding flow to populate
 * them (`trainerBio`, `trainerSpecialty`, `trainerMonthlyRate`, etc.).
 *
 * See scripts/README.md for full usage and prerequisites.
 *
 * ADR-TPO-007: role-flip only, uid-based, validate doc exists, idempotent.
 */

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function run() {
  const uid = process.argv[2];
  if (!uid) {
    console.error('USAGE: node scripts/promote_user_to_trainer.js <uid>');
    process.exit(1);
  }

  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    console.error(`User document users/${uid} not found.`);
    process.exit(1);
  }

  const { email, displayName } = snap.data();
  console.log(
    `Promoting ${email} (${displayName || '(no displayName)'}) → role: trainer`,
  );

  await db.collection('users').doc(uid).update({ role: 'trainer' });
  console.log('Done.');
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
