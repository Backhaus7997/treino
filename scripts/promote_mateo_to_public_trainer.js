/**
 * promote_mateo_to_public_trainer.js
 *
 * One-shot script to give the real PF account (Mateo) a public trainer
 * profile so it shows up in the Coach Discovery list. Useful for smoke
 * tests where you want a NEW athlete to link to a REAL trainer (not the
 * fake seeded ones).
 *
 * What it does:
 *   1. Looks up the user by email in Firebase Auth.
 *   2. Writes `users/{uid}` with role:trainer + trainer public fields.
 *   3. Writes `trainerPublicProfiles/{uid}` mirror doc for discovery.
 *
 * USAGE
 *   cd treino  (repo root)
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
 *   node scripts/promote_mateo_to_public_trainer.js <email>
 *
 * Example:
 *   node scripts/promote_mateo_to_public_trainer.js tinchoignacio33@gmail.com
 *
 * Idempotent: safe to re-run, uses merge:true.
 */

'use strict';

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// ── Geohash5 (port of lib/core/utils/geohash.dart) ───────────────────────
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohash5(lat, lon) {
  let latMin = -90.0, latMax = 90.0;
  let lonMin = -180.0, lonMax = 180.0;
  let hash = '';
  let even = true;
  let bit = 0;
  let ch = 0;
  while (hash.length < 5) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonMin = mid; }
      else { ch = ch << 1; lonMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; }
      else { ch = ch << 1; latMax = mid; }
    }
    even = !even;
    bit++;
    if (bit === 5) {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

// ── Mateo profile (clustered in the same Córdoba geohash5 as the seed) ───
// Lat/Lon ~ Córdoba Centro-Norte → geohash5 "6d6m7" (same cell as seed trainers)
const MATEO = {
  displayName: 'Mateo Backhaus',
  avatarUrl: null,
  trainerBio: 'PF certificado, especialista en hipertrofia y fuerza. Plan personalizado + seguimiento semanal por chat.',
  trainerSpecialty: 'hipertrofia',
  trainerLatitude: -31.4135,
  trainerLongitude: -64.1810,
  trainerMonthlyRate: 7000,
};

async function run() {
  const email = process.argv[2];
  if (!email) {
    console.error('USAGE: node scripts/promote_mateo_to_public_trainer.js <email>');
    process.exit(1);
  }

  console.log(`Looking up user with email "${email}"...`);
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (err) {
    console.error(`No user found for "${email}" in Firebase Auth.`);
    console.error('Make sure you typed the email used to log in.');
    process.exit(1);
  }
  console.log(`  ✓ Found uid: ${user.uid}`);

  const geohash = geohash5(MATEO.trainerLatitude, MATEO.trainerLongitude);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const userDoc = {
    uid: user.uid,
    email,
    displayName: MATEO.displayName,
    role: 'trainer',
    updatedAt: now,
    avatarUrl: MATEO.avatarUrl,
    trainerBio: MATEO.trainerBio,
    trainerSpecialty: MATEO.trainerSpecialty,
    trainerLatitude: MATEO.trainerLatitude,
    trainerLongitude: MATEO.trainerLongitude,
    trainerGeohash: geohash,
    trainerMonthlyRate: MATEO.trainerMonthlyRate,
  };

  const publicDoc = {
    uid: user.uid,
    displayName: MATEO.displayName,
    displayNameLowercase: MATEO.displayName.trim().toLowerCase(),
    avatarUrl: MATEO.avatarUrl,
    trainerBio: MATEO.trainerBio,
    trainerSpecialty: MATEO.trainerSpecialty,
    trainerLatitude: MATEO.trainerLatitude,
    trainerLongitude: MATEO.trainerLongitude,
    trainerGeohash: geohash,
    trainerMonthlyRate: MATEO.trainerMonthlyRate,
  };

  const batch = db.batch();
  batch.set(db.collection('users').doc(user.uid), userDoc, { merge: true });
  batch.set(
    db.collection('trainerPublicProfiles').doc(user.uid),
    publicDoc,
    { merge: true },
  );
  await batch.commit();

  console.log(`\n✓ Promoted ${user.uid} to public trainer.`);
  console.log(`  displayName: ${MATEO.displayName}`);
  console.log(`  specialty:   ${MATEO.trainerSpecialty}`);
  console.log(`  geohash5:    ${geohash}`);
  console.log(`  monthlyRate: $${MATEO.trainerMonthlyRate}`);
  console.log('\nNow Mateo should appear in the Coach Discovery list of the app.');
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
