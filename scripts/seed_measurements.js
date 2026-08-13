'use strict';

/**
 * scripts/seed_measurements.js
 *
 * Seeds throwaway MOCK body measurements into the DEV Firebase project so the
 * anthropometry feature (history + progress chart) can be smoke-tested with a
 * realistic trend on a real device.
 *
 * Docs: top-level `measurements/{autoId}` with recordedBy = trainer, athleteId
 * = athlete. Each carries `seedMock: true` (extra field the Dart model ignores
 * on parse). Cleanup deletes exactly `where seedMock == true`.
 *
 * 5 snapshots over the last ~8 weeks: weight/fat/waist trending down,
 * muscle/chest/biceps trending up.
 *
 * Usage:
 *   node scripts/seed_measurements.js
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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_measurements.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const TRAINER_ID = 'zCqIMvyJNpeZFdyHAD0zjhZu13g1';
const ATHLETE_ID = 'UVjNGDxHc1PB6GppssbLEu8htRS2';

/** Date `weeksAgo` weeks before now, at noon (stable). */
function weeksAgo(n) {
  const d = new Date();
  d.setTime(d.getTime() - n * 7 * 86_400_000);
  d.setHours(12, 0, 0, 0);
  return d;
}

// Oldest → newest. Trend: weight/fat/waist ↓, muscle/chest/biceps ↑.
const SNAPSHOTS = [
  {
    when: weeksAgo(8),
    weightKg: 82.0, fatPercentage: 22.0, muscleMassKg: 58.0,
    shouldersCm: 120, chestCm: 102, waistCm: 92, hipsCm: 100, glutesCm: 101,
    bicepsLCm: 35.0, bicepsRCm: 35.5, bicepsFlexedLCm: 37.5, bicepsFlexedRCm: 38.0,
    forearmLCm: 29.0, forearmRCm: 29.0,
    upperThighLCm: 58.0, upperThighRCm: 58.5, midThighLCm: 52.0, midThighRCm: 52.0,
    calfLCm: 38.0, calfRCm: 38.0,
    notes: 'Inicio del plan.',
  },
  {
    when: weeksAgo(6),
    weightKg: 80.5, fatPercentage: 20.5, muscleMassKg: 59.0,
    shouldersCm: 121, chestCm: 103, waistCm: 90, hipsCm: 99, glutesCm: 101,
    bicepsLCm: 35.5, bicepsRCm: 36.0, bicepsFlexedLCm: 38.0, bicepsFlexedRCm: 38.5,
    forearmLCm: 29.5, forearmRCm: 29.5,
    upperThighLCm: 58.5, upperThighRCm: 59.0, midThighLCm: 52.5, midThighRCm: 52.5,
    calfLCm: 38.5, calfRCm: 38.5,
  },
  {
    when: weeksAgo(4),
    weightKg: 79.0, fatPercentage: 19.0, muscleMassKg: 60.0,
    shouldersCm: 122, chestCm: 104, waistCm: 88, hipsCm: 98, glutesCm: 102,
    bicepsLCm: 36.0, bicepsRCm: 36.5, bicepsFlexedLCm: 38.5, bicepsFlexedRCm: 39.0,
    forearmLCm: 29.5, forearmRCm: 30.0,
    upperThighLCm: 59.0, upperThighRCm: 59.5, midThighLCm: 53.0, midThighRCm: 53.0,
    calfLCm: 39.0, calfRCm: 39.0,
    notes: 'Buen progreso, baja de cintura.',
  },
  {
    when: weeksAgo(2),
    weightKg: 78.0, fatPercentage: 18.0, muscleMassKg: 60.5,
    shouldersCm: 123, chestCm: 105, waistCm: 86.5, hipsCm: 97, glutesCm: 102,
    bicepsLCm: 36.5, bicepsRCm: 37.0, bicepsFlexedLCm: 39.0, bicepsFlexedRCm: 39.5,
    forearmLCm: 30.0, forearmRCm: 30.0,
    upperThighLCm: 59.5, upperThighRCm: 60.0, midThighLCm: 53.5, midThighRCm: 53.5,
    calfLCm: 39.0, calfRCm: 39.5,
  },
  {
    when: weeksAgo(0),
    weightKg: 77.0, fatPercentage: 16.5, muscleMassKg: 61.0,
    shouldersCm: 124, chestCm: 106, waistCm: 85.0, hipsCm: 96, glutesCm: 103,
    bicepsLCm: 37.0, bicepsRCm: 37.5, bicepsFlexedLCm: 39.5, bicepsFlexedRCm: 40.0,
    forearmLCm: 30.0, forearmRCm: 30.5,
    upperThighLCm: 60.0, upperThighRCm: 60.5, midThighLCm: 54.0, midThighRCm: 54.0,
    calfLCm: 39.5, calfRCm: 40.0,
    notes: 'Última medición. Excelente evolución.',
  },
];

async function main() {
  console.log(`Trainer:  ${TRAINER_ID}`);
  console.log(`Athlete:  ${ATHLETE_ID}`);
  console.log(`Seeding ${SNAPSHOTS.length} measurements...\n`);

  for (const snap of SNAPSHOTS) {
    const { when, ...metrics } = snap;
    const data = {
      athleteId: ATHLETE_ID,
      recordedBy: TRAINER_ID,
      recordedAt: admin.firestore.Timestamp.fromDate(when),
      ...metrics,
      seedMock: true,
    };
    const ref = await db.collection('measurements').add(data);
    console.log(
      `  ✓ ${ref.id}  ${when.toISOString().slice(0, 10)}  ${metrics.weightKg}kg ${metrics.fatPercentage}% bf`,
    );
  }
  console.log('\nDone. Run cleanup_measurements.js to remove all of these.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
