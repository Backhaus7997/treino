'use strict';

/**
 * scripts/seed_dashboard_mocks.js
 *
 * Seeds throwaway MOCK appointments into the DEV Firebase project so the
 * trainer dashboard ("Resumen del día" + "Próximas sesiones") can be
 * smoke-tested with realistic data on a real device.
 *
 * Every doc carries `seedMock: true` — an extra field the Dart model ignores
 * on parse. Cleanup deletes exactly `where seedMock == true`
 * (see cleanup_dashboard_mocks.js). Real appointments are never touched.
 *
 * Times are RELATIVE TO NOW (now-2h, now+2h, …) so the pendiente/completada
 * classification in the dashboard (computed in UTC vs DateTime.now().toUtc())
 * is correct regardless of timezone.
 *
 * Usage:
 *   node scripts/seed_dashboard_mocks.js
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
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_dashboard_mocks.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

// ── Targets (from diag_trainer_links.js --trainer-email mateopresset7@gmail.com)
const TRAINER_ID = 'zCqIMvyJNpeZFdyHAD0zjhZu13g1';
const ACTIVE_ATHLETE_ID = 'UVjNGDxHc1PB6GppssbLEu8htRS2'; // real active link

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Returns a Date floored to the whole hour (minute/second/ms zeroed),
 *  offset from now. Round times like 19:00, not 19:18. */
function atOffset({ hours = 0, days = 0 } = {}) {
  const d = new Date();
  d.setTime(d.getTime() + days * 86_400_000 + hours * 3_600_000);
  d.setMinutes(0, 0, 0); // floor to the hour (ADR-7 minute precision satisfied)
  return d;
}

/** Reads the trainer's configured slot duration. Uses the most common
 *  slotDurationMin across availability rules; falls back to 60. */
async function resolveSlotDurationMin() {
  const snap = await db
    .collection('coach_availability_rules')
    .where('trainerId', '==', TRAINER_ID)
    .get();
  if (snap.empty) return 60;
  const counts = {};
  snap.docs.forEach((d) => {
    const v = d.data().slotDurationMin;
    if (typeof v === 'number') counts[v] = (counts[v] || 0) + 1;
  });
  const entries = Object.entries(counts);
  if (entries.length === 0) return 60;
  entries.sort((a, b) => b[1] - a[1]);
  return Number(entries[0][0]);
}

function apptDoc({ athleteId, athleteDisplayName, startsAt, durationMin }) {
  const startsAtMs = startsAt.getTime();
  const id = `${TRAINER_ID}_${startsAtMs}`;
  return {
    id,
    data: {
      trainerId: TRAINER_ID,
      athleteId,
      athleteDisplayName,
      startsAt: admin.firestore.Timestamp.fromDate(startsAt),
      durationMin,
      status: 'confirmed',
      cancellationLog: [],
      seedMock: true, // ← cleanup marker
    },
  };
}

// ── Seed ─────────────────────────────────────────────────────────────────────

async function main() {
  // Pull the real active athlete's display name for realism.
  let realName = 'Alumno Real';
  const upp = await db.collection('userPublicProfiles').doc(ACTIVE_ATHLETE_ID).get();
  if (upp.exists && upp.data().displayName) {
    realName = upp.data().displayName;
  }
  const slotDurationMin = await resolveSlotDurationMin();
  console.log(`Trainer:        ${TRAINER_ID}`);
  console.log(`Active athlete: ${ACTIVE_ATHLETE_ID} (${realName})`);
  console.log(`Slot duration:  ${slotDurationMin} min (from trainer config)\n`);

  const appts = [
    // COMPLETADA today (in the past) — real athlete
    apptDoc({
      athleteId: ACTIVE_ATHLETE_ID,
      athleteDisplayName: realName,
      startsAt: atOffset({ hours: -2 }),
      durationMin: slotDurationMin,
    }),
    // PENDIENTE today + próxima #1 — mock athlete (no real profile → falls back to displayName)
    apptDoc({
      athleteId: 'seed_mock_athlete_001',
      athleteDisplayName: 'Sofía Gómez',
      startsAt: atOffset({ hours: 2 }),
      durationMin: slotDurationMin,
    }),
    // PENDIENTE today + próxima #2 — mock athlete
    apptDoc({
      athleteId: 'seed_mock_athlete_002',
      athleteDisplayName: 'Lucas Díaz',
      startsAt: atOffset({ hours: 4 }),
      durationMin: slotDurationMin,
    }),
    // próxima #3 — real athlete, tomorrow
    apptDoc({
      athleteId: ACTIVE_ATHLETE_ID,
      athleteDisplayName: realName,
      startsAt: atOffset({ days: 1 }),
      durationMin: slotDurationMin,
    }),
    // próxima #4 (beyond top-3) — mock athlete, in 2 days
    apptDoc({
      athleteId: 'seed_mock_athlete_003',
      athleteDisplayName: 'Martina Ruiz',
      startsAt: atOffset({ days: 2 }),
      durationMin: slotDurationMin,
    }),
  ];

  console.log(`Seeding ${appts.length} mock appointments...`);
  for (const { id, data } of appts) {
    await db.collection('appointments').doc(id).set(data);
    console.log(
      `  ✓ ${id}  ${data.startsAt.toDate().toISOString()}  ${data.athleteDisplayName}`,
    );
  }

  // ── "Entrenaron hoy" — privacy grant + a finished session today ─────────────
  // session_shares/{athleteId} is the deterministic doc the security rule reads
  // to authorize the trainer's cross-athlete session reads (opt-in gate).
  // NOTE: admin SDK bypasses security rules, so this writes regardless of deploy.
  await db.collection('session_shares').doc(ACTIVE_ATHLETE_ID).set({
    trainerId: TRAINER_ID,
    seedMock: true,
  });
  console.log(`\n  ✓ session_shares/${ACTIVE_ATHLETE_ID} → trainer ${TRAINER_ID}`);

  const finishedAt = atOffset({ hours: -2 }); // earlier today, on the hour
  const startedAt = new Date(finishedAt.getTime() - slotDurationMin * 60_000);
  const todaySession = {
    id: 'seed_mock_session_001',
    uid: ACTIVE_ATHLETE_ID,
    routineId: 'seed_mock_routine',
    routineName: 'Push Day',
    startedAt: admin.firestore.Timestamp.fromDate(startedAt),
    finishedAt: admin.firestore.Timestamp.fromDate(finishedAt),
    totalVolumeKg: 3120,
    durationMin: slotDurationMin,
    status: 'finished',
    dayNumber: 3,
    wasFullyCompleted: true,
    seedMock: true,
  };
  await db
    .collection('users')
    .doc(ACTIVE_ATHLETE_ID)
    .collection('sessions')
    .doc('seed_mock_session_001')
    .set(todaySession);
  console.log(
    `  ✓ users/${ACTIVE_ATHLETE_ID}/sessions/seed_mock_session_001 (Push Day, finished today)`,
  );

  console.log('\nExpected dashboard:');
  console.log('  Resumen del día → PENDIENTES 2 · COMPLETADAS 1 · CANCELADAS 0');
  console.log('  Próximas sesiones → 3 rows (Sofía, Lucas, ' + realName + ' mañana)');
  console.log('  Entrenaron hoy → 1 row (' + realName + ' · Push Day)');
  console.log('\nDone. Run cleanup_dashboard_mocks.js to remove all of these.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
