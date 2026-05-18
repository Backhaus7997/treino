'use strict';

/**
 * scripts/seed_sessions.js
 *
 * Seeds 10 sample finished sessions into Firestore (emulator by default).
 * All sessions belong to seed_user_001. Doc IDs are deterministic:
 * seed_session_001 through seed_session_010.
 *
 * Status: all `finished` — no SetLogs seeded (Etapa 4 adds live set tracking).
 * Totals are fixed values for UI smoke-testing (Fase 4 Etapa 1, REQ-SMS-014).
 *
 * Usage:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_sessions.js
 *
 * Or point at production (careful!):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/seed_sessions.js
 */

const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ---------------------------------------------------------------------------
// Seed data — 10 finished sessions for seed_user_001
// ---------------------------------------------------------------------------

const UID = 'seed_user_001';

// Routine catalogue IDs match seed_routines.js (or emulator defaults).
const ROUTINES = [
  { routineId: 'upper-strength',    routineName: 'Upper Strength' },
  { routineId: 'lower-strength',    routineName: 'Lower Strength' },
  { routineId: 'hypertrophy-full',  routineName: 'Full Body Hypertrophy' },
  { routineId: 'push-day',          routineName: 'Push Day' },
  { routineId: 'pull-day',          routineName: 'Pull Day' },
];

function makeSession(index) {
  // index: 1-based (1..10)
  const daysAgo = (10 - index) * 2; // sessions every 2 days going back
  const startedAt = new Date(Date.UTC(2026, 4, 1) - daysAgo * 86_400_000); // 2026-05-01 base
  const durationMin = 45 + (index % 4) * 5;  // 45–60 min
  const totalVolumeKg = 2000 + index * 150;   // 2150–3500 kg
  const routine = ROUTINES[(index - 1) % ROUTINES.length];

  return {
    uid: UID,
    routineId: routine.routineId,
    routineName: routine.routineName,
    startedAt: admin.firestore.Timestamp.fromDate(startedAt),
    finishedAt: admin.firestore.Timestamp.fromDate(
      new Date(startedAt.getTime() + durationMin * 60_000),
    ),
    totalVolumeKg,
    durationMin,
    status: 'finished',
  };
}

const sessions = Array.from({ length: 10 }, (_, i) => ({
  id: `seed_session_${String(i + 1).padStart(3, '0')}`,
  ...makeSession(i + 1),
}));

// ---------------------------------------------------------------------------
// Seeder
// ---------------------------------------------------------------------------

async function seedSessions() {
  console.log(`Seeding ${sessions.length} sessions for uid=${UID}...`);
  for (const session of sessions) {
    const { id, ...data } = session;
    await db
      .collection('users')
      .doc(UID)
      .collection('sessions')
      .doc(id)
      .set(data);
    console.log(
      `  Seeded: ${id} (routine=${data.routineName}, volume=${data.totalVolumeKg}kg, dur=${data.durationMin}min)`,
    );
  }
  console.log(`Done. ${sessions.length} sessions written.`);
}

// ---------------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------------

seedSessions().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
