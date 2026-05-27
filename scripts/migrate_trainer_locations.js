'use strict';

/**
 * migrate_trainer_locations.js
 *
 * Migra los PFs existentes del schema singular legacy
 * (`trainerLatitude/Longitude/Geohash`) al schema multi-location
 * (`trainerLocations[]` + `trainerGeohashes[]` + `trainerOffersOnline`).
 *
 * Idempotente: skipea PFs que ya tienen `trainerLocations` no vacío.
 *
 * Caso especial Mateo: si el script se ejecuta con `--mateo-to-gym <gymId>`,
 * en lugar de crear una location de tipo `custom` para Mateo, lo asigna
 * directo al gym `<gymId>` (debe existir en `gyms/{gymId}` previamente).
 *
 * USAGE
 *   # Migración estándar (todos los PFs legacy → custom location):
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
 *   node scripts/migrate_trainer_locations.js
 *
 *   # Migración + asignar Mateo a un gym específico:
 *   node scripts/migrate_trainer_locations.js --mateo-email tinchoignacio33@gmail.com --mateo-to-gym megatlon-nueva-cordoba
 */

const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();
const db = admin.firestore();

function uuid() {
  return crypto.randomUUID();
}

function parseArgs() {
  const args = { mateoEmail: null, mateoToGym: null };
  for (let i = 2; i < process.argv.length; i++) {
    if (process.argv[i] === '--mateo-email') args.mateoEmail = process.argv[++i];
    if (process.argv[i] === '--mateo-to-gym') args.mateoToGym = process.argv[++i];
  }
  return args;
}

async function fetchMateoUid(email) {
  if (!email) return null;
  try {
    const user = await admin.auth().getUserByEmail(email);
    return user.uid;
  } catch (_) {
    console.warn(`No user found for email "${email}". Skipping Mateo override.`);
    return null;
  }
}

async function fetchGymById(gymId) {
  if (!gymId) return null;
  const snap = await db.collection('gyms').doc(gymId).get();
  if (!snap.exists) {
    console.warn(`Gym "${gymId}" not found in catalog. Skipping Mateo override.`);
    return null;
  }
  return { id: gymId, ...snap.data() };
}

function buildCustomLocation({ lat, lng, geohash, label }) {
  return {
    id: uuid(),
    type: 'custom',
    gymId: null,
    customLabel: label || 'Ubicación principal',
    lat,
    lng,
    geohash,
  };
}

function buildGymLocation(gym) {
  return {
    id: uuid(),
    type: 'gym',
    gymId: gym.id,
    customLabel: null,
    lat: gym.lat,
    lng: gym.lng,
    geohash: gym.geohash,
  };
}

async function migrateUser(doc, opts) {
  const data = doc.data();
  const uid = doc.id;

  // Skip si ya tiene trainerLocations no vacío (idempotencia).
  if (Array.isArray(data.trainerLocations) && data.trainerLocations.length > 0) {
    return { skipped: true, reason: 'already migrated' };
  }

  // Skip si no tiene legacy fields.
  const lat = data.trainerLatitude;
  const lng = data.trainerLongitude;
  const geohash = data.trainerGeohash;
  if (typeof lat !== 'number' || typeof lng !== 'number' || typeof geohash !== 'string') {
    return { skipped: true, reason: 'no legacy location' };
  }

  let location;
  if (opts.mateoUid && uid === opts.mateoUid && opts.mateoGym) {
    location = buildGymLocation(opts.mateoGym);
  } else {
    location = buildCustomLocation({ lat, lng, geohash, label: 'Ubicación principal' });
  }

  const patch = {
    trainerLocations: [location],
    trainerGeohashes: [location.geohash],
    trainerOffersOnline: false,
  };

  // Dual-write: users + trainerPublicProfiles (mismo subset que el repo
  // hace en runtime — mantenido consistente).
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid), patch, { merge: true });
  batch.set(db.collection('trainerPublicProfiles').doc(uid), patch, { merge: true });
  await batch.commit();

  return { migrated: true, location };
}

async function run() {
  const args = parseArgs();
  const mateoUid = await fetchMateoUid(args.mateoEmail);
  const mateoGym = await fetchGymById(args.mateoToGym);
  const opts = { mateoUid, mateoGym };

  if (mateoUid && mateoGym) {
    console.log(`Mateo override: ${mateoUid} → ${mateoGym.id} (${mateoGym.name})`);
  } else if (args.mateoEmail || args.mateoToGym) {
    console.warn('Mateo override skipped (email o gymId no resolvieron). Mateo recibe migración estándar.');
  }
  console.log('---');

  // Solo procesamos PFs con role: trainer.
  const snap = await db.collection('users').where('role', '==', 'trainer').get();
  console.log(`Found ${snap.size} trainer docs. Migrating...`);

  let migrated = 0, skipped = 0;
  for (const doc of snap.docs) {
    const result = await migrateUser(doc, opts);
    if (result.migrated) {
      const loc = result.location;
      const tag = loc.type === 'gym' ? `gym=${loc.gymId}` : `custom="${loc.customLabel}"`;
      console.log(`  ✓ ${doc.id} (${tag}, geohash=${loc.geohash})`);
      migrated++;
    } else {
      console.log(`  -  ${doc.id} skipped (${result.reason})`);
      skipped++;
    }
  }

  console.log(`\nMigrated: ${migrated} · Skipped: ${skipped} · Total: ${snap.size}`);
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
