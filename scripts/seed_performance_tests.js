'use strict';

/**
 * scripts/seed_performance_tests.js
 *
 * Seeds throwaway MOCK performance tests into DEV so the rendimiento feature
 * (history + progress chart) can be smoke-tested with a realistic trend.
 *
 * Docs: top-level `performance_tests/{autoId}`, recordedBy = trainer,
 * athleteId = athlete. Each carries `seedMock: true`. Cleanup deletes exactly
 * `where seedMock == true`.
 *
 * 5 snapshots over ~8 weeks: jumps/strength/endurance ↑, sprint times ↓.
 *
 * Usage: node scripts/seed_performance_tests.js
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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_performance_tests.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const TRAINER_ID = 'zCqIMvyJNpeZFdyHAD0zjhZu13g1';
const ATHLETE_ID = 'UVjNGDxHc1PB6GppssbLEu8htRS2';

function weeksAgo(n) {
  const d = new Date();
  d.setTime(d.getTime() - n * 7 * 86_400_000);
  d.setHours(12, 0, 0, 0);
  return d;
}

// Oldest → newest. Jumps/strength/endurance ↑, sprint times ↓ (faster).
const SNAPSHOTS = [
  {
    when: weeksAgo(8),
    cmjCm: 32.0, squatJumpCm: 28.0, abalakovCm: 38.0, broadJumpCm: 210,
    sprint10mS: 1.85, sprint20mS: 3.10, sprint30mS: 4.40, sprint40mS: 5.80,
    squat1rmKg: 100, benchPress1rmKg: 70, deadlift1rmKg: 120, overheadPress1rmKg: 45, pullUp1rmKg: 10,
    vo2maxMlKgMin: 45.0, courseNavetteLevel: 8.5, cooperMeters: 2400, sitAndReachCm: 5.0,
    notes: 'Evaluación inicial.',
  },
  {
    when: weeksAgo(6),
    cmjCm: 33.5, squatJumpCm: 29.5, abalakovCm: 39.5, broadJumpCm: 216,
    sprint10mS: 1.82, sprint20mS: 3.06, sprint30mS: 4.34, sprint40mS: 5.73,
    squat1rmKg: 107, benchPress1rmKg: 73, deadlift1rmKg: 128, overheadPress1rmKg: 47, pullUp1rmKg: 14,
    vo2maxMlKgMin: 46.5, courseNavetteLevel: 9.0, cooperMeters: 2500, sitAndReachCm: 7.0,
  },
  {
    when: weeksAgo(4),
    cmjCm: 35.0, squatJumpCm: 31.0, abalakovCm: 41.5, broadJumpCm: 222,
    sprint10mS: 1.79, sprint20mS: 3.02, sprint30mS: 4.30, sprint40mS: 5.67,
    squat1rmKg: 113, benchPress1rmKg: 77, deadlift1rmKg: 136, overheadPress1rmKg: 50, pullUp1rmKg: 18,
    vo2maxMlKgMin: 48.0, courseNavetteLevel: 9.5, cooperMeters: 2580, sitAndReachCm: 9.0,
    notes: 'Buen salto en fuerza.',
  },
  {
    when: weeksAgo(2),
    cmjCm: 36.5, squatJumpCm: 32.5, abalakovCm: 43.0, broadJumpCm: 229,
    sprint10mS: 1.75, sprint20mS: 2.98, sprint30mS: 4.25, sprint40mS: 5.61,
    squat1rmKg: 119, benchPress1rmKg: 81, deadlift1rmKg: 143, overheadPress1rmKg: 52, pullUp1rmKg: 22,
    vo2maxMlKgMin: 50.0, courseNavetteLevel: 10.5, cooperMeters: 2680, sitAndReachCm: 10.5,
  },
  {
    when: weeksAgo(0),
    cmjCm: 38.0, squatJumpCm: 34.0, abalakovCm: 45.0, broadJumpCm: 235,
    sprint10mS: 1.72, sprint20mS: 2.95, sprint30mS: 4.20, sprint40mS: 5.55,
    squat1rmKg: 125, benchPress1rmKg: 85, deadlift1rmKg: 150, overheadPress1rmKg: 55, pullUp1rmKg: 25,
    vo2maxMlKgMin: 52.0, courseNavetteLevel: 11.0, cooperMeters: 2750, sitAndReachCm: 12.0,
    notes: 'Última evaluación. Progreso parejo.',
  },
];

async function main() {
  console.log(`Trainer:  ${TRAINER_ID}`);
  console.log(`Athlete:  ${ATHLETE_ID}`);
  console.log(`Seeding ${SNAPSHOTS.length} performance tests...\n`);

  for (const snap of SNAPSHOTS) {
    const { when, ...metrics } = snap;
    const data = {
      athleteId: ATHLETE_ID,
      recordedBy: TRAINER_ID,
      recordedAt: admin.firestore.Timestamp.fromDate(when),
      ...metrics,
      seedMock: true,
    };
    const ref = await db.collection('performance_tests').add(data);
    console.log(
      `  ✓ ${ref.id}  ${when.toISOString().slice(0, 10)}  CMJ ${metrics.cmjCm}cm  sentadilla ${metrics.squat1rmKg}kg`,
    );
  }
  console.log('\nDone. Run cleanup_performance_tests.js to remove all of these.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
