/**
 * seed_trainer_profiles.js
 *
 * Seeds 5 fake trainer profiles in Firestore for testing the Coach Discovery
 * flow (Fase 5 · Etapa 2).
 *
 * What it writes:
 *   - `users/{uid}` — full UserProfile with `role: trainer` + trainer fields
 *   - `trainerPublicProfiles/{uid}` — public subset for discovery queries
 *
 * Deterministic UIDs (`seed-trainer-1`..`seed-trainer-5`) so re-runs are
 * idempotent and a `--clear` flag deletes them cleanly.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE
 * ────────────────────────────────────────────────────────────────────────────
 *   cd scripts
 *   node seed_trainer_profiles.js          # creates / upserts 5 trainers
 *   node seed_trainer_profiles.js --clear  # deletes the 5 seeded trainers
 *
 * Requires `sa-key.json` (Firebase service account) in scripts/ — see
 * backfill_user_public_profiles.js for setup instructions.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * NOTES
 * ────────────────────────────────────────────────────────────────────────────
 * - Geohashes are precomputed (geohash5) for Buenos Aires neighborhoods.
 * - These are FAKE users — they do NOT exist in Firebase Auth. The athlete
 *   can browse and tap them in /coach but `getById` reads from
 *   trainerPublicProfiles which is auth-only-read (any logged-in athlete
 *   can read).
 * - To deploy in prod: do NOT run this. Only for dev/QA emulator or a
 *   throwaway test project.
 */

'use strict';

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// ──────────────────────────────────────────────────────────────────────────
// Geohash5 implementation (port of lib/core/utils/geohash.dart)
// ──────────────────────────────────────────────────────────────────────────

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
      if (lon >= mid) {
        ch = (ch << 1) | 1;
        lonMin = mid;
      } else {
        ch = ch << 1;
        lonMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
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

// ──────────────────────────────────────────────────────────────────────────
// Seed data — 5 trainers in Buenos Aires neighborhoods
// ──────────────────────────────────────────────────────────────────────────

// All 5 trainers clustered in Palermo (within ~1.5km radius) so they share
// the same geohash5 cell `69y7q`. This makes the seed useful BOTH with
// location permission granted AND with "Ahora no" (listAll fallback).
const TRAINERS = [
  {
    uid: 'seed-trainer-1',
    displayName: 'Lautaro Pérez',
    email: 'lautaro.fake@treino.app',
    avatarUrl: null,
    trainerBio: 'Powerlifter competitivo desde 2018. Especializado en sentadilla, banco y peso muerto. Atletas all-level.',
    trainerSpecialty: 'powerlifting',
    trainerLatitude: -34.5755,
    trainerLongitude: -58.4338,
    trainerHourlyRate: 8000,
  },
  {
    uid: 'seed-trainer-2',
    displayName: 'Camila Ruiz',
    email: 'camila.fake@treino.app',
    avatarUrl: null,
    trainerBio: 'Crossfit Level 2. Programas de fuerza + condicionamiento metabólico. Atención personalizada por whatsapp.',
    trainerSpecialty: 'crossfit',
    trainerLatitude: -34.5808,
    trainerLongitude: -58.4290,
    trainerHourlyRate: 7500,
  },
  {
    uid: 'seed-trainer-3',
    displayName: 'Federico Sosa',
    email: 'federico.fake@treino.app',
    avatarUrl: null,
    trainerBio: 'Hipertrofia y composición corporal. 6 años de experiencia en gimnasios de zona norte. Plan + seguimiento semanal.',
    trainerSpecialty: 'hipertrofia',
    trainerLatitude: -34.5720,
    trainerLongitude: -58.4395,
    trainerHourlyRate: 6500,
  },
  {
    uid: 'seed-trainer-4',
    displayName: 'Sol Martínez',
    email: 'sol.fake@treino.app',
    avatarUrl: null,
    trainerBio: 'Yoga vinyasa + entrenamiento funcional. Mujeres 30+, posparto, rehabilitación articular. Clases online disponibles.',
    trainerSpecialty: 'yoga',
    trainerLatitude: -34.5790,
    trainerLongitude: -58.4310,
    trainerHourlyRate: 5500,
  },
  {
    uid: 'seed-trainer-5',
    displayName: 'Diego Aguirre',
    email: 'diego.fake@treino.app',
    avatarUrl: null,
    trainerBio: 'Kinesiología + entrenamiento. Recupero post-lesión, runners con sobrecargas, fortalecimiento de core.',
    trainerSpecialty: 'kinesiologia',
    trainerLatitude: -34.5765,
    trainerLongitude: -58.4360,
    trainerHourlyRate: 9000,
  },
];

// ──────────────────────────────────────────────────────────────────────────

function userDoc(t) {
  const geohash = geohash5(t.trainerLatitude, t.trainerLongitude);
  const now = admin.firestore.FieldValue.serverTimestamp();
  return {
    uid: t.uid,
    email: t.email,
    displayName: t.displayName,
    role: 'trainer',
    createdAt: now,
    updatedAt: now,
    avatarUrl: t.avatarUrl,
    trainerBio: t.trainerBio,
    trainerSpecialty: t.trainerSpecialty,
    trainerLatitude: t.trainerLatitude,
    trainerLongitude: t.trainerLongitude,
    trainerGeohash: geohash,
    trainerHourlyRate: t.trainerHourlyRate,
  };
}

function publicDoc(t) {
  const geohash = geohash5(t.trainerLatitude, t.trainerLongitude);
  return {
    uid: t.uid,
    displayName: t.displayName,
    displayNameLowercase: t.displayName.trim().toLowerCase(),
    avatarUrl: t.avatarUrl,
    trainerBio: t.trainerBio,
    trainerSpecialty: t.trainerSpecialty,
    trainerLatitude: t.trainerLatitude,
    trainerLongitude: t.trainerLongitude,
    trainerGeohash: geohash,
    trainerHourlyRate: t.trainerHourlyRate,
  };
}

async function seed() {
  console.log(`Seeding ${TRAINERS.length} trainer profiles...`);

  for (const t of TRAINERS) {
    const batch = db.batch();
    batch.set(db.collection('users').doc(t.uid), userDoc(t), { merge: true });
    batch.set(
      db.collection('trainerPublicProfiles').doc(t.uid),
      publicDoc(t),
      { merge: true },
    );
    await batch.commit();
    const gh = geohash5(t.trainerLatitude, t.trainerLongitude);
    console.log(`  ✓ ${t.uid} — ${t.displayName} (${t.trainerSpecialty}, geohash5=${gh})`);
  }

  console.log('Seed complete.');
}

async function clear() {
  console.log(`Deleting ${TRAINERS.length} seeded trainer profiles...`);

  for (const t of TRAINERS) {
    const batch = db.batch();
    batch.delete(db.collection('users').doc(t.uid));
    batch.delete(db.collection('trainerPublicProfiles').doc(t.uid));
    await batch.commit();
    console.log(`  ✗ ${t.uid} deleted`);
  }

  console.log('Clear complete.');
}

const flag = process.argv[2];
const action = flag === '--clear' ? clear : seed;

action()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err);
    process.exit(1);
  });
