'use strict';

/**
 * scripts/seed_emulator_full.js
 *
 * EMULATOR-ONLY full-stack seed for manual testing.
 * Creates Auth users + Firestore docs for 5 athletes and 3 coaches,
 * with trainer links, routines, historical sessions, posts (all privacy
 * levels), friendships, and appointments.
 *
 * ────────────────────────────────────────────────────────────────────
 * WARNING: EMULATOR-ONLY CREDENTIALS — DO NOT USE IN PRODUCTION
 * ────────────────────────────────────────────────────────────────────
 * All passwords are throwaway, stored plaintext here intentionally.
 * This script ONLY works against the local Firebase emulator.
 * Running against a real project will fail (emulator env vars not set).
 *
 * USAGE
 *   # 1. Start emulator (separate terminal):
 *   #      bash scripts/emulator.sh
 *   # 2. Run seed:
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   node scripts/seed_emulator_full.js
 *
 * CLEAR (idempotent reset):
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   node scripts/seed_emulator_full.js --clear
 *
 * See scripts/README.md (Emulator seed section) for full details.
 */

const admin = require('firebase-admin');

// ── Guard: must target the emulator ─────────────────────────────────────────

if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    '\nERROR: This script must run against the Firebase emulator.\n' +
    'Set both environment variables before running:\n\n' +
    '  FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \\\n' +
    '  FIRESTORE_EMULATOR_HOST=localhost:8080 \\\n' +
    '  node scripts/seed_emulator_full.js\n',
  );
  process.exit(1);
}

// Admin SDK with emulator — no service account needed.
admin.initializeApp({ projectId: 'treino-dev' });

const auth = admin.auth();
const db = admin.firestore();

// Stock exercise catalogue — same data prod uses. Required AFTER
// initializeApp: seed_workout_catalog.js guards its own init, so requiring it
// here reuses this emulator-bound app instead of creating a prod one.
const {
  exercises: CATALOG_EXERCISES,
  buildExerciseDoc,
} = require('./seed_workout_catalog.js');

// ────────────────────────────────────────────────────────────────────────────
// Geohash5 — port of lib/core/utils/geohash.dart
// ────────────────────────────────────────────────────────────────────────────

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
    if (bit === 5) { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

// ────────────────────────────────────────────────────────────────────────────
// Data definitions
// ────────────────────────────────────────────────────────────────────────────

// Base "now" for every relative date below. Defaults to the real clock so the
// scenarios this seed promises (a session yesterday, appointments today and
// tomorrow, a live streak) actually land on today when you run it. Pin it via
// SEED_NOW=2026-06-16T12:00:00Z when you need byte-identical, reproducible data.
const NOW = process.env.SEED_NOW ? new Date(process.env.SEED_NOW) : new Date();

function daysAgo(n) {
  return new Date(NOW.getTime() - n * 86_400_000);
}

function daysFromNow(n) {
  return new Date(NOW.getTime() + n * 86_400_000);
}

// ── Gyms (subset — full set in seed_gyms.js) ────────────────────────────────

const GYMS = [
  { id: 'seed-gym-baires-001', name: 'Megatlon Palermo', address: 'Av. Santa Fe 5025, Palermo', lat: -34.5786, lng: -58.4243 },
  { id: 'seed-gym-baires-002', name: 'SmartFit Caballito', address: 'Av. Rivadavia 5050, Caballito', lat: -34.6189, lng: -58.4426 },
  { id: 'seed-gym-cba-001', name: 'Megatlon Nueva Córdoba', address: 'Av. H. Yrigoyen 384, Nueva Córdoba', lat: -31.4189, lng: -64.1859 },
];

// ── Coaches (trainers) ───────────────────────────────────────────────────────
// All in Buenos Aires zone so discovery geohash queries resolve them.
// Emulator-only passwords — clearly labelled.

const COACHES = [
  {
    uid: 'seed-coach-001',
    email: 'coach.lautaro@emulator.treino',  // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Lautaro Pérez',
    gymId: 'seed-gym-baires-001',
    trainerBio: 'Powerlifter competitivo desde 2018. Especializado en sentadilla, banco y peso muerto.',
    trainerSpecialty: 'powerlifting',
    lat: -34.5786, lng: -58.4243,
    trainerMonthlyRate: 45000,
    paymentAlias: 'lautaro.perez.mp',
    slotDurationMin: 60,
  },
  {
    uid: 'seed-coach-002',
    email: 'coach.camila@emulator.treino',   // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Camila Ruiz',
    gymId: 'seed-gym-baires-002',
    trainerBio: 'Crossfit Level 2. Fuerza + condicionamiento metabólico. Atención personalizada.',
    trainerSpecialty: 'crossfit',
    lat: -34.6189, lng: -58.4426,
    trainerMonthlyRate: 38000,
    paymentAlias: 'camila.ruiz.mp',
    slotDurationMin: 60,
  },
  {
    uid: 'seed-coach-003',
    email: 'coach.diego@emulator.treino',    // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Diego Aguirre',
    gymId: null,
    trainerBio: 'Kinesiología + entrenamiento. Recupero post-lesión, runners, fortalecimiento de core.',
    trainerSpecialty: 'kinesiologia',
    lat: -34.5847, lng: -58.4321,
    trainerMonthlyRate: 52000,
    paymentAlias: 'diego.aguirre.mp',
    slotDurationMin: 90,
  },
];

// ── Athletes ─────────────────────────────────────────────────────────────────

const ATHLETES = [
  {
    uid: 'seed-athlete-001',
    email: 'martin@emulator.treino',         // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Martín López',
    gymId: 'seed-gym-baires-001',
    gender: 'male',
    experienceLevel: 'intermediate',
    bodyWeightKg: 82.5,
    heightCm: 178,
  },
  {
    uid: 'seed-athlete-002',
    email: 'sofia@emulator.treino',          // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Sofía Ramírez',
    gymId: 'seed-gym-baires-001',
    gender: 'female',
    experienceLevel: 'beginner',
    bodyWeightKg: 61.0,
    heightCm: 165,
  },
  {
    uid: 'seed-athlete-003',
    email: 'mateo@emulator.treino',          // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Mateo Quiroga',
    gymId: 'seed-gym-baires-002',
    gender: 'male',
    experienceLevel: 'advanced',
    bodyWeightKg: 90.0,
    heightCm: 182,
  },
  {
    uid: 'seed-athlete-004',
    email: 'valentina@emulator.treino',      // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Valentina Peralta',
    gymId: 'seed-gym-baires-002',
    gender: 'female',
    experienceLevel: 'intermediate',
    bodyWeightKg: 68.0,
    heightCm: 169,
  },
  {
    uid: 'seed-athlete-005',
    email: 'nicolas@emulator.treino',        // EMULATOR-ONLY
    password: 'Emulator1234!',               // EMULATOR-ONLY
    displayName: 'Nicolás Fernández',
    gymId: null,
    gender: 'male',
    experienceLevel: 'beginner',
    bodyWeightKg: 75.0,
    heightCm: 174,
  },
];

// ── Trainer links ─────────────────────────────────────────────────────────────
// seed-coach-001 → seed-athlete-001 (active, with session sharing)
// seed-coach-001 → seed-athlete-002 (active)
// seed-coach-002 → seed-athlete-003 (active)
// seed-coach-003 → seed-athlete-004 (pending — inbox view)
// seed-coach-001 → seed-athlete-005 (terminated — history view)

const TRAINER_LINKS = [
  {
    id: 'seed-link-001',
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-001',
    status: 'active',
    requestedAt: daysAgo(60),
    acceptedAt: daysAgo(58),
    sharedWithTrainer: true,  // athlete shared sessions
  },
  {
    id: 'seed-link-002',
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-002',
    status: 'active',
    requestedAt: daysAgo(30),
    acceptedAt: daysAgo(28),
    sharedWithTrainer: false,
  },
  {
    id: 'seed-link-003',
    trainerId: 'seed-coach-002',
    athleteId: 'seed-athlete-003',
    status: 'active',
    requestedAt: daysAgo(45),
    acceptedAt: daysAgo(43),
    sharedWithTrainer: true,
  },
  {
    id: 'seed-link-004',
    trainerId: 'seed-coach-003',
    athleteId: 'seed-athlete-004',
    status: 'pending',
    requestedAt: daysAgo(2),
    acceptedAt: null,
    sharedWithTrainer: false,
  },
  {
    id: 'seed-link-005',
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-005',
    status: 'terminated',
    requestedAt: daysAgo(120),
    acceptedAt: daysAgo(118),
    terminatedAt: daysAgo(20),
    terminationReason: 'Alta voluntaria del atleta',
    sharedWithTrainer: false,
  },
];

// ── Friendships ──────────────────────────────────────────────────────────────
// Martin ↔ Sofia  (accepted) — same gym, feed shows gym + friends posts
// Martin ↔ Mateo  (accepted) — different gyms, feed shows friends posts
// Sofia ↔ Nicolas (pending)  — inbox view test

function sortedDocId(a, b) {
  return a.localeCompare(b) <= 0 ? `${a}_${b}` : `${b}_${a}`;
}

const FRIENDSHIPS = [
  {
    id: sortedDocId('seed-athlete-001', 'seed-athlete-002'),
    uidA: 'seed-athlete-001',
    uidB: 'seed-athlete-002',
    status: 'accepted',
    requesterId: 'seed-athlete-001',
    members: ['seed-athlete-001', 'seed-athlete-002'],
    createdAt: daysAgo(50),
  },
  {
    id: sortedDocId('seed-athlete-001', 'seed-athlete-003'),
    uidA: 'seed-athlete-001',
    uidB: 'seed-athlete-003',
    status: 'accepted',
    requesterId: 'seed-athlete-003',
    members: ['seed-athlete-001', 'seed-athlete-003'],
    createdAt: daysAgo(40),
  },
  {
    id: sortedDocId('seed-athlete-002', 'seed-athlete-005'),
    uidA: 'seed-athlete-002',
    uidB: 'seed-athlete-005',
    status: 'pending',
    requesterId: 'seed-athlete-002',
    members: ['seed-athlete-002', 'seed-athlete-005'],
    createdAt: daysAgo(3),
  },
];

// ── Routines ──────────────────────────────────────────────────────────────────
// 2 trainer-assigned plans (multi-week) + 1 system template.
// Slots use the simple legacy model (targetSets/targetRepsMin/Max/restSeconds)
// for maximum compatibility — no weeklySets needed for a smoke test.

const ROUTINES = [
  // Trainer-assigned plan: Lautaro → Martín (3 weeks, private)
  {
    id: 'seed-routine-001',
    name: 'Fuerza Base – 3 semanas',
    split: 'Upper/Lower',
    level: 'intermediate',
    numWeeks: 3,
    source: 'trainer-assigned',
    assignedBy: 'seed-coach-001',
    assignedTo: 'seed-athlete-001',
    visibility: 'private',
    estimatedMinutesPerDay: 55,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Upper A – Empuje',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'press-banca', exerciseName: 'Press de Banca', muscleGroup: 'chest', targetSets: 4, targetRepsMin: 5, targetRepsMax: 6, restSeconds: 180, targetWeightKg: 80 },
          { exerciseId: 'press-militar', exerciseName: 'Press Militar', muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 150, targetWeightKg: 50 },
          { exerciseId: 'fondos', exerciseName: 'Fondos en paralelas', muscleGroup: 'triceps', targetSets: 3, targetRepsMin: 8, targetRepsMax: 12, restSeconds: 120, targetWeightKg: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Lower A – Cuádriceps',
        estimatedMinutes: 60,
        slots: [
          { exerciseId: 'sentadilla', exerciseName: 'Sentadilla', muscleGroup: 'quads', targetSets: 4, targetRepsMin: 5, targetRepsMax: 6, restSeconds: 180, targetWeightKg: 100 },
          { exerciseId: 'prensa', exerciseName: 'Prensa de Piernas', muscleGroup: 'quads', targetSets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 150, targetWeightKg: 180 },
          { exerciseId: 'extension-cuadriceps', exerciseName: 'Extensión de Cuádriceps', muscleGroup: 'quads', targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 90, targetWeightKg: 40 },
        ],
      },
      {
        dayNumber: 3,
        name: 'Upper B – Tirón',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'peso-muerto', exerciseName: 'Peso Muerto Rumano', muscleGroup: 'back', targetSets: 4, targetRepsMin: 4, targetRepsMax: 5, restSeconds: 210, targetWeightKg: 110 },
          { exerciseId: 'remo-barra', exerciseName: 'Remo con Barra', muscleGroup: 'back', targetSets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 150, targetWeightKg: 70 },
          { exerciseId: 'dominadas', exerciseName: 'Dominadas', muscleGroup: 'back', targetSets: 3, targetRepsMin: 5, targetRepsMax: 8, restSeconds: 150, targetWeightKg: null },
        ],
      },
    ],
  },
  // Trainer-assigned plan: Camila → Mateo (2 weeks, private)
  {
    id: 'seed-routine-002',
    name: 'Crossfit WOD – 2 semanas',
    split: 'Full Body',
    level: 'advanced',
    numWeeks: 2,
    source: 'trainer-assigned',
    assignedBy: 'seed-coach-002',
    assignedTo: 'seed-athlete-003',
    visibility: 'private',
    estimatedMinutesPerDay: 45,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'WOD Lunes',
        estimatedMinutes: 45,
        slots: [
          { exerciseId: 'thruster', exerciseName: 'Thruster', muscleGroup: 'full_body', targetSets: 5, targetRepsMin: 10, targetRepsMax: 10, restSeconds: 90, targetWeightKg: 42.5 },
          { exerciseId: 'pull-ups-kipping', exerciseName: 'Pull-ups Kipping', muscleGroup: 'back', targetSets: 5, targetRepsMin: 10, targetRepsMax: 10, restSeconds: 90, targetWeightKg: null },
          { exerciseId: 'box-jump', exerciseName: 'Box Jump', muscleGroup: 'glutes', targetSets: 5, targetRepsMin: 15, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'WOD Miércoles',
        estimatedMinutes: 45,
        slots: [
          { exerciseId: 'deadlift-cf', exerciseName: 'Deadlift', muscleGroup: 'back', targetSets: 5, targetRepsMin: 5, targetRepsMax: 5, restSeconds: 120, targetWeightKg: 120 },
          { exerciseId: 'hspu', exerciseName: 'Handstand Push-Up', muscleGroup: 'shoulders', targetSets: 5, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 90, targetWeightKg: null },
          { exerciseId: 'ring-dip', exerciseName: 'Ring Dip', muscleGroup: 'chest', targetSets: 4, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 90, targetWeightKg: null },
        ],
      },
    ],
  },
  // System template (public) — any athlete can use it
  {
    id: 'seed-routine-003',
    name: 'Full Body Principiante',
    split: 'Full Body',
    level: 'beginner',
    numWeeks: 1,
    source: 'system',
    assignedBy: null,
    assignedTo: null,
    visibility: 'public',
    estimatedMinutesPerDay: 40,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Día A',
        estimatedMinutes: 40,
        slots: [
          { exerciseId: 'sentadilla-goblet', exerciseName: 'Sentadilla Goblet', muscleGroup: 'quads', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: 16 },
          { exerciseId: 'press-mancuernas', exerciseName: 'Press con Mancuernas', muscleGroup: 'chest', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: 14 },
          { exerciseId: 'remo-mancuerna', exerciseName: 'Remo con Mancuerna', muscleGroup: 'back', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: 14 },
          { exerciseId: 'plancha', exerciseName: 'Plancha Isométrica', muscleGroup: 'core', targetSets: 3, targetRepsMin: 30, targetRepsMax: 60, restSeconds: 60, targetWeightKg: null, durationSeconds: 45 },
        ],
      },
    ],
  },
];

// ── Historical sessions ───────────────────────────────────────────────────────
// Martín: 14 sessions over last 28 days — mix of fully completed and not
// Mateo:  8 sessions over last 20 days — all fully completed
// Sofia:  4 sessions over last 15 days — mix

// dayNumber/weekNumber cycle over the referenced routine's REAL day/week
// count — the app only ever writes dayNumbers that exist in the plan, so the
// seed must too (a dayNumber:3 session against a 2-day routine is data the
// app can't produce). Derived from ROUTINES so a routine edit can't drift.
// totalVolumeKg is stamped later from the generated setLogs (single source of
// truth: Σ reps×weightKg, exactly how SessionState computes it live).
function makeSessionsForAthlete({ uid, routineId, routineName, count, startDaysAgo, spacing, fullCompletedPattern }) {
  const routine = ROUTINES.find((r) => r.id === routineId);
  if (!routine) throw new Error(`makeSessionsForAthlete: unknown routine '${routineId}'`);
  const numDays = routine.days.length;
  const numWeeks = routine.numWeeks;
  const sessions = [];
  for (let i = 0; i < count; i++) {
    const daysBack = startDaysAgo - i * spacing;
    const startedAt = new Date(daysAgo(daysBack).getTime());
    startedAt.setUTCHours(10, 0, 0, 0);
    const durationMin = 45 + (i % 4) * 5;
    const wasFullyCompleted = fullCompletedPattern[i % fullCompletedPattern.length];
    sessions.push({
      id: `seed-session-${uid}-${String(i + 1).padStart(3, '0')}`,
      uid,
      routineId,
      routineName,
      startedAt,
      finishedAt: new Date(startedAt.getTime() + durationMin * 60_000),
      totalVolumeKg: 0, // recomputed below from setLogs
      durationMin,
      status: 'finished',
      dayNumber: (i % numDays) + 1,
      weekNumber: Math.floor(i / numDays) % numWeeks,
      wasFullyCompleted,
    });
  }
  return sessions;
}

const SESSIONS = [
  // Martín — 14 sessions, good streak
  ...makeSessionsForAthlete({
    uid: 'seed-athlete-001',
    routineId: 'seed-routine-001',
    routineName: 'Fuerza Base – 3 semanas',
    count: 14,
    startDaysAgo: 27,
    spacing: 2,
    fullCompletedPattern: [true, true, true, false, true, true, true],
  }),
  // Mateo — 8 sessions, all completed
  ...makeSessionsForAthlete({
    uid: 'seed-athlete-003',
    routineId: 'seed-routine-002',
    routineName: 'Crossfit WOD – 2 semanas',
    count: 8,
    startDaysAgo: 19,
    spacing: 2.5,
    fullCompletedPattern: [true],
  }),
  // Sofia — 4 sessions, mixed
  ...makeSessionsForAthlete({
    uid: 'seed-athlete-002',
    routineId: 'seed-routine-003',
    routineName: 'Full Body Principiante',
    count: 4,
    startDaysAgo: 14,
    spacing: 4,
    fullCompletedPattern: [true, false, true, true],
  }),
];

// ── Set logs ─────────────────────────────────────────────────────────────────
// Every seed session gets a `setLogs` subcollection mirroring what the live
// session player writes (issue #374): without them the whole muscle pipeline
// of Insights (radar, "Músculos del día", Volumen por grupo, Sets counts,
// frecuencia/progresión) sees empty sessions.

const ROUTINE_BY_ID = Object.fromEntries(ROUTINES.map((r) => [r.id, r]));

const plateRound = (kg) => Math.round(kg / 2.5) * 2.5;

/**
 * Deterministic per-set logs for one seed session.
 *
 * - Weight ramps +2.5 kg per prior occurrence of the same (routine, day),
 *   starting 10 kg under the slot's targetWeightKg — so the 5th occurrence
 *   lands exactly on target and Evolución por ejercicio gets a real
 *   progression curve. Bodyweight slots (targetWeightKg null) log 0 kg,
 *   matching how the player persists an empty weight field.
 * - Partial sessions (wasFullyCompleted=false) stop mid-workout: all sets of
 *   the first slot plus one set of the second.
 * - completedAt advances ~3 min per set from startedAt, staying inside the
 *   session's durationMin.
 */
function buildSetLogsForSession(session, occurrence) {
  const routine = ROUTINE_BY_ID[session.routineId];
  if (!routine) return [];
  const day =
    routine.days.find((d) => d.dayNumber === session.dayNumber) ??
    routine.days[(session.dayNumber - 1) % routine.days.length];
  const slots = session.wasFullyCompleted ? day.slots : day.slots.slice(0, 2);

  // Set counts first, so completedAt can be paced evenly across the session's
  // real durationMin instead of a fixed stride that could overrun finishedAt.
  const setCounts = slots.map((slot, slotIdx) => {
    // Partial = abandoned mid-workout: full sets of the first slot + one set
    // of the second. A 1-slot day has no second slot to cut, so cut the first
    // one in half instead — a partial must always log fewer sets than a full.
    const isPartialTail = !session.wasFullyCompleted &&
        (slotIdx === 1 || day.slots.length === 1);
    return isPartialTail
        ? Math.max(1, Math.floor(slot.targetSets / 2))
        : slot.targetSets;
  });
  const totalSets = setCounts.reduce((a, b) => a + b, 0);
  if (totalSets === 0) return [];
  // First set ~2 min in, last set ~2 min before finishedAt, evenly spaced.
  const usableMs = Math.max((session.durationMin - 4), 1) * 60_000;
  const strideMs = totalSets > 1 ? Math.floor(usableMs / (totalSets - 1)) : 0;

  const logs = [];
  slots.forEach((slot, slotIdx) => {
    // Ramp +2.5 kg per prior occurrence, floored at 60% of target and CAPPED
    // at targetWeightKg — extending an athlete's session count must plateau
    // at the plan's target, never overshoot it.
    const weightKg = slot.targetWeightKg == null
      ? 0
      : plateRound(Math.min(
          slot.targetWeightKg,
          Math.max(
            slot.targetWeightKg * 0.6,
            slot.targetWeightKg - 10 + 2.5 * occurrence,
          ),
        ));
    for (let n = 1; n <= setCounts[slotIdx]; n++) {
      logs.push({
        id: `${session.id}-set-${String(logs.length + 1).padStart(2, '0')}`,
        exerciseId: slot.exerciseId,
        exerciseName: slot.exerciseName,
        setNumber: n,
        reps: slot.targetRepsMax,
        weightKg,
        rpe: null,
        completedAt: new Date(
          session.startedAt.getTime() + 2 * 60_000 + logs.length * strideMs),
      });
    }
  });
  return logs;
}

// Stamp logs + recompute totalVolumeKg (Σ reps×weightKg — same formula the
// live SessionState uses, so summary docs and subcollections always agree).
// Sorted by startedAt so the occurrence counter tracks REAL calendar order —
// the weight ramp must follow dates, not fixture declaration order.
const SETLOGS_BY_SESSION = {};
{
  const occurrenceCounter = {};
  for (const s of [...SESSIONS].sort((a, b) => a.startedAt - b.startedAt)) {
    const key = `${s.uid}|${s.routineId}|${s.dayNumber}`;
    const occ = occurrenceCounter[key] ?? 0;
    occurrenceCounter[key] = occ + 1;
    const logs = buildSetLogsForSession(s, occ);
    SETLOGS_BY_SESSION[s.id] = logs;
    s.totalVolumeKg = logs.reduce((sum, l) => sum + l.reps * l.weightKg, 0);
  }
}

// ── Posts ─────────────────────────────────────────────────────────────────────
// All three privacy levels seeded.

const AUTHOR_META = {
  'seed-athlete-001': { displayName: 'Martín L.', avatarUrl: null, gymId: 'seed-gym-baires-001' },
  'seed-athlete-002': { displayName: 'Sofía R.', avatarUrl: null, gymId: 'seed-gym-baires-001' },
  'seed-athlete-003': { displayName: 'Mateo Q.', avatarUrl: null, gymId: 'seed-gym-baires-002' },
  'seed-athlete-004': { displayName: 'Valentina P.', avatarUrl: null, gymId: 'seed-gym-baires-002' },
  'seed-coach-001':   { displayName: 'Lautaro P.', avatarUrl: null, gymId: 'seed-gym-baires-001' },
};

const POSTS = [
  // public ──────────────────────────────────────────────────────────────
  {
    id: 'seed-post-001',
    authorUid: 'seed-athlete-001',
    authorDisplayName: AUTHOR_META['seed-athlete-001'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: 'Terminé mi primer bloque de fuerza. 3 semanas, 14 sesiones. Sin perder un día de los programados. La constancia paga.',
    routineTag: { routineId: 'seed-routine-001', routineName: 'Fuerza Base – 3 semanas' },
    privacy: 'public',
    createdAt: daysAgo(1),
  },
  {
    id: 'seed-post-002',
    authorUid: 'seed-athlete-003',
    authorDisplayName: AUTHOR_META['seed-athlete-003'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-002',
    text: 'PR en Deadlift: 140 kg × 3. Camila me tenía con el plan perfecto.',
    routineTag: { routineId: 'seed-routine-002', routineName: 'Crossfit WOD – 2 semanas' },
    privacy: 'public',
    createdAt: daysAgo(3),
  },
  {
    id: 'seed-post-003',
    authorUid: 'seed-coach-001',
    authorDisplayName: AUTHOR_META['seed-coach-001'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: '¿Querés arrancar con powerlifting pero no sabés por dónde empezar? Mandame un mensaje. Tengo slots disponibles para junio.',
    routineTag: null,
    privacy: 'public',
    createdAt: daysAgo(5),
  },
  // friends ─────────────────────────────────────────────────────────────
  {
    id: 'seed-post-004',
    authorUid: 'seed-athlete-001',
    authorDisplayName: AUTHOR_META['seed-athlete-001'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: 'Entrené con 38.5°C de fiebre. No se lo cuenten a Lautaro.',
    routineTag: null,
    privacy: 'friends',
    createdAt: daysAgo(7),
  },
  {
    id: 'seed-post-005',
    authorUid: 'seed-athlete-002',
    authorDisplayName: AUTHOR_META['seed-athlete-002'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: 'Primera semana de entreno terminada. Me duele absolutamente todo.',
    routineTag: null,
    privacy: 'friends',
    createdAt: daysAgo(10),
  },
  {
    id: 'seed-post-006',
    authorUid: 'seed-athlete-003',
    authorDisplayName: AUTHOR_META['seed-athlete-003'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-002',
    text: 'El WOD de hoy fue una tortura. Tres rondas de Thrusters + Pull-ups. Me quiero morir (positivamente).',
    routineTag: { routineId: 'seed-routine-002', routineName: 'Crossfit WOD – 2 semanas' },
    privacy: 'friends',
    createdAt: daysAgo(12),
  },
  // gym ─────────────────────────────────────────────────────────────────
  {
    id: 'seed-post-007',
    authorUid: 'seed-athlete-001',
    authorDisplayName: AUTHOR_META['seed-athlete-001'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: 'El rack 3 de Megatlon Palermo va a hacer que algún día me lastime. Alguien que hable con administración.',
    routineTag: null,
    privacy: 'gym',
    createdAt: daysAgo(4),
  },
  {
    id: 'seed-post-008',
    authorUid: 'seed-athlete-002',
    authorDisplayName: AUTHOR_META['seed-athlete-002'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-001',
    text: '¿Alguien más nota que los martes al mediodía el gym está casi vacío? Mejor horario del mundo.',
    routineTag: null,
    privacy: 'gym',
    createdAt: daysAgo(8),
  },
  {
    id: 'seed-post-009',
    authorUid: 'seed-athlete-004',
    authorDisplayName: AUTHOR_META['seed-athlete-004'].displayName,
    authorAvatarUrl: null,
    authorGymId: 'seed-gym-baires-002',
    text: 'SmartFit Caballito renovó las cintas. Finalmente.',
    routineTag: null,
    privacy: 'gym',
    createdAt: daysAgo(6),
  },
];

// ── Appointments ─────────────────────────────────────────────────────────────
// Coach 001 (Lautaro) — 3 appts with athletes 001 and 002
// Coach 002 (Camila)  — 2 appts with athlete 003

function startsAtUTC(daysOffset, hour) {
  const d = daysFromNow(daysOffset);
  d.setUTCHours(hour, 0, 0, 0);
  return d;
}

const APPOINTMENTS = [
  // Past (completada) — coach 001
  {
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-001',
    athleteDisplayName: 'Martín López',
    startsAt: startsAtUTC(-1, 10),  // yesterday 10:00 UTC
    durationMin: 60,
    status: 'confirmed',
    cancellationLog: [],
  },
  // Today upcoming — coach 001
  {
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-002',
    athleteDisplayName: 'Sofía Ramírez',
    startsAt: startsAtUTC(0, 17),   // today 17:00 UTC
    durationMin: 60,
    status: 'confirmed',
    cancellationLog: [],
  },
  // Tomorrow — coach 001
  {
    trainerId: 'seed-coach-001',
    athleteId: 'seed-athlete-001',
    athleteDisplayName: 'Martín López',
    startsAt: startsAtUTC(1, 10),   // tomorrow 10:00 UTC
    durationMin: 60,
    status: 'confirmed',
    cancellationLog: [],
  },
  // Day after tomorrow — coach 002
  {
    trainerId: 'seed-coach-002',
    athleteId: 'seed-athlete-003',
    athleteDisplayName: 'Mateo Quiroga',
    startsAt: startsAtUTC(1, 18),   // tomorrow 18:00 UTC
    durationMin: 60,
    status: 'confirmed',
    cancellationLog: [],
  },
  {
    trainerId: 'seed-coach-002',
    athleteId: 'seed-athlete-003',
    athleteDisplayName: 'Mateo Quiroga',
    startsAt: startsAtUTC(3, 18),   // in 3 days 18:00 UTC
    durationMin: 60,
    status: 'confirmed',
    cancellationLog: [],
  },
];

// ── Availability rules ────────────────────────────────────────────────────────
// Coach 001: Mon/Wed/Fri 09:00-13:00, slots 60 min
// Coach 002: Tue/Thu 17:00-20:00, slots 60 min
// Coach 003: Mon-Sat 08:00-11:30, slots 90 min

const AVAILABILITY_RULES = [
  // Lautaro — Lunes
  { id: 'seed-avail-001', trainerId: 'seed-coach-001', dayOfWeek: 1, startHour: 9, startMinute: 0, endHour: 13, endMinute: 0, slotDurationMin: 60 },
  // Lautaro — Miércoles
  { id: 'seed-avail-002', trainerId: 'seed-coach-001', dayOfWeek: 3, startHour: 9, startMinute: 0, endHour: 13, endMinute: 0, slotDurationMin: 60 },
  // Lautaro — Viernes
  { id: 'seed-avail-003', trainerId: 'seed-coach-001', dayOfWeek: 5, startHour: 9, startMinute: 0, endHour: 13, endMinute: 0, slotDurationMin: 60 },
  // Camila — Martes
  { id: 'seed-avail-004', trainerId: 'seed-coach-002', dayOfWeek: 2, startHour: 17, startMinute: 0, endHour: 20, endMinute: 0, slotDurationMin: 60 },
  // Camila — Jueves
  { id: 'seed-avail-005', trainerId: 'seed-coach-002', dayOfWeek: 4, startHour: 17, startMinute: 0, endHour: 20, endMinute: 0, slotDurationMin: 60 },
  // Diego — Lunes a Sábado
  { id: 'seed-avail-006', trainerId: 'seed-coach-003', dayOfWeek: 1, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
  { id: 'seed-avail-007', trainerId: 'seed-coach-003', dayOfWeek: 2, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
  { id: 'seed-avail-008', trainerId: 'seed-coach-003', dayOfWeek: 3, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
  { id: 'seed-avail-009', trainerId: 'seed-coach-003', dayOfWeek: 4, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
  { id: 'seed-avail-010', trainerId: 'seed-coach-003', dayOfWeek: 5, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
  { id: 'seed-avail-011', trainerId: 'seed-coach-003', dayOfWeek: 6, startHour: 8, startMinute: 0, endHour: 11, endMinute: 30, slotDurationMin: 90 },
];

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function ts(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

/** Deletes every doc in a (sub)collection ref. Overwriting or deleting a
 * parent doc never touches its subcollections, so both seed and --clear need
 * this for `setLogs`. */
async function deleteAllDocs(collectionRef) {
  const snap = await collectionRef.get().catch(() => null);
  if (snap && !snap.empty) {
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

/** Deterministic appointment doc ID per ADR-7 */
function apptDocId(trainerId, startsAt) {
  return `${trainerId}_${startsAt.getTime()}`;
}

// ────────────────────────────────────────────────────────────────────────────
// Seed
// ────────────────────────────────────────────────────────────────────────────

async function seedGyms() {
  console.log('\n── Gyms ─────────────────────────────────────────────────────────');
  for (const g of GYMS) {
    const geohash = geohash5(g.lat, g.lng);
    await db.collection('gyms').doc(g.id).set({
      name: g.name,
      address: g.address,
      lat: g.lat,
      lng: g.lng,
      geohash,
      source: 'seed',
      createdAt: ts(NOW),
    });
    console.log(`  ✓ gyms/${g.id} — ${g.name}`);
  }
}

async function seedAuthUser({ uid, email, password, displayName }) {
  try {
    await auth.createUser({ uid, email, password, displayName });
    console.log(`  ✓ Auth user created: ${email}`);
  } catch (err) {
    if (err.code === 'auth/uid-already-exists' || err.code === 'auth/email-already-exists') {
      await auth.updateUser(uid, { email, password, displayName });
      console.log(`  ↺ Auth user updated: ${email}`);
    } else {
      throw err;
    }
  }
}

async function seedCoaches() {
  console.log('\n── Coaches ──────────────────────────────────────────────────────');
  for (const c of COACHES) {
    await seedAuthUser(c);
    const geohash = geohash5(c.lat, c.lng);
    const locationId = `loc-${c.uid}-0`;
    const gymId = c.gymId;

    const trainerLocation = gymId
      ? { id: locationId, type: 'gym', gymId, customLabel: null, lat: c.lat, lng: c.lng, geohash }
      : { id: locationId, type: 'custom', gymId: null, customLabel: 'Estudio propio', lat: c.lat, lng: c.lng, geohash };

    const userDoc = {
      uid: c.uid,
      email: c.email,
      displayName: c.displayName,
      role: 'trainer',
      createdAt: ts(daysAgo(90)),
      updatedAt: ts(NOW),
      avatarUrl: null,
      gymId: gymId || null,
      trainerBio: c.trainerBio,
      trainerSpecialty: c.trainerSpecialty,
      trainerMonthlyRate: c.trainerMonthlyRate,
      paymentAlias: c.paymentAlias,
      // Legacy fields (backward compat)
      trainerLatitude: c.lat,
      trainerLongitude: c.lng,
      trainerGeohash: geohash,
      // Multi-location model
      trainerLocations: [trainerLocation],
      trainerGeohashes: [geohash],
      trainerOffersOnline: false,
    };

    const publicDoc = {
      uid: c.uid,
      displayName: c.displayName,
      displayNameLowercase: c.displayName.trim().toLowerCase(),
      avatarUrl: null,
      trainerBio: c.trainerBio,
      trainerSpecialty: c.trainerSpecialty,
      trainerMonthlyRate: c.trainerMonthlyRate,
      paymentAlias: c.paymentAlias,
      // Legacy
      trainerLatitude: c.lat,
      trainerLongitude: c.lng,
      trainerGeohash: geohash,
      // Multi-location
      trainerLocations: [trainerLocation],
      trainerGeohashes: [geohash],
      trainerOffersOnline: false,
      averageRating: null,
      reviewCount: 0,
    };

    // trainerPublicProfiles holds the DISCOVERY data (rate, bio, geohash), but
    // the app resolves a person's IDENTITY — trainers included — through
    // userPublicProfiles: routine detail ("Asignado por …"), mi plan, reviews
    // and chat all read it by uid. Without this doc a trainer-assigned routine
    // renders "Asignado por ?".
    const userPublicDoc = {
      uid: c.uid,
      displayName: c.displayName,
      displayNameLowercase: c.displayName.trim().toLowerCase(),
      avatarUrl: null,
      gymId: null,
      workoutsCount: 0,
      racha: 0,
      followersCount: 0,
      followingCount: 0,
      sharedTemplatesWithAthletes: false,
    };

    const batch = db.batch();
    batch.set(db.collection('users').doc(c.uid), userDoc, { merge: true });
    batch.set(db.collection('trainerPublicProfiles').doc(c.uid), publicDoc, { merge: true });
    batch.set(
      db.collection('userPublicProfiles').doc(c.uid),
      userPublicDoc,
      { merge: true },
    );
    await batch.commit();
    console.log(
      `  ✓ Firestore docs: users/${c.uid} + trainerPublicProfiles/${c.uid} + userPublicProfiles/${c.uid} (geohash=${geohash})`,
    );
  }
}

async function seedAthletes() {
  console.log('\n── Athletes ─────────────────────────────────────────────────────');
  for (const a of ATHLETES) {
    await seedAuthUser(a);

    const userDoc = {
      uid: a.uid,
      email: a.email,
      displayName: a.displayName,
      role: 'athlete',
      createdAt: ts(daysAgo(70)),
      updatedAt: ts(NOW),
      avatarUrl: null,
      gymId: a.gymId || null,
      gender: a.gender,
      experienceLevel: a.experienceLevel,
      bodyWeightKg: a.bodyWeightKg,
      heightCm: a.heightCm,
    };

    // Public profile counters are derived — seed approximate values
    const completedSessions = SESSIONS.filter(s => s.uid === a.uid && s.wasFullyCompleted).length;
    const publicDoc = {
      uid: a.uid,
      displayName: a.displayName,
      displayNameLowercase: a.displayName.trim().toLowerCase(),
      avatarUrl: null,
      gymId: a.gymId || null,
      workoutsCount: completedSessions,
      racha: completedSessions > 0 ? Math.min(completedSessions, 7) : 0,
      followersCount: 0,
      followingCount: 0,
      sharedTemplatesWithAthletes: false,
    };

    const batch = db.batch();
    batch.set(db.collection('users').doc(a.uid), userDoc, { merge: true });
    batch.set(db.collection('userPublicProfiles').doc(a.uid), publicDoc, { merge: true });
    await batch.commit();
    console.log(`  ✓ users/${a.uid} + userPublicProfiles/${a.uid} — ${a.displayName}`);
  }
}

async function seedTrainerLinks() {
  console.log('\n── Trainer Links ────────────────────────────────────────────────');
  for (const link of TRAINER_LINKS) {
    const data = {
      id: link.id,
      trainerId: link.trainerId,
      athleteId: link.athleteId,
      status: link.status,
      requestedAt: ts(link.requestedAt),
      acceptedAt: link.acceptedAt ? ts(link.acceptedAt) : null,
      terminatedAt: link.terminatedAt ? ts(link.terminatedAt) : null,
      terminationReason: link.terminationReason || null,
      pausedAt: null,
      sharedWithTrainer: link.sharedWithTrainer,
    };
    await db.collection('trainer_links').doc(link.id).set(data);
    console.log(`  ✓ trainer_links/${link.id} [${link.status}] ${link.trainerId} → ${link.athleteId}`);

    // If sharedWithTrainer, write session_shares grant
    if (link.sharedWithTrainer && link.status === 'active') {
      await db.collection('session_shares').doc(link.athleteId).set({
        trainerId: link.trainerId,
      });
      console.log(`    ↪ session_shares/${link.athleteId} (trainer read access granted)`);
    }
  }
}

async function seedFriendships() {
  console.log('\n── Friendships ──────────────────────────────────────────────────');
  for (const f of FRIENDSHIPS) {
    const data = {
      id: f.id,
      uidA: f.uidA,
      uidB: f.uidB,
      status: f.status,
      requesterId: f.requesterId,
      members: f.members,
      createdAt: ts(f.createdAt),
    };
    await db.collection('friendships').doc(f.id).set(data);
    console.log(`  ✓ friendships/${f.id} [${f.status}] ${f.uidA} ↔ ${f.uidB}`);
  }
}

async function seedRoutines() {
  console.log('\n── Routines ─────────────────────────────────────────────────────');
  for (const r of ROUTINES) {
    const data = {
      id: r.id,
      name: r.name,
      split: r.split,
      level: r.level,
      numWeeks: r.numWeeks,
      source: r.source,
      assignedBy: r.assignedBy || null,
      assignedTo: r.assignedTo || null,
      visibility: r.visibility,
      estimatedMinutesPerDay: r.estimatedMinutesPerDay || null,
      imageUrl: r.imageUrl || null,
      days: r.days.map(d => ({
        dayNumber: d.dayNumber,
        name: d.name,
        estimatedMinutes: d.estimatedMinutes || null,
        slots: d.slots.map(s => ({
          exerciseId: s.exerciseId,
          exerciseName: s.exerciseName,
          muscleGroup: s.muscleGroup,
          targetSets: s.targetSets,
          targetRepsMin: s.targetRepsMin,
          targetRepsMax: s.targetRepsMax,
          restSeconds: s.restSeconds,
          targetWeightKg: s.targetWeightKg || null,
          notes: s.notes || null,
          supersetGroup: s.supersetGroup || null,
          targetReps: [],
          durationSeconds: s.durationSeconds || null,
          exerciseMode: 'reps',
          repMode: 'single',
          sets: [],
          weeklySets: [],
          activeWeeks: [],
        })),
      })),
      status: 'active',
      // Required by the app's assigned/user routine queries, which
      // `orderBy('createdAt')` — Firestore silently drops docs missing the
      // field, so a routine without it is invisible to the athlete.
      createdAt: r.createdAt || daysAgo(60),
    };
    await db.collection('routines').doc(r.id).set(data);
    console.log(`  ✓ routines/${r.id} — ${r.name} (${r.numWeeks}w, ${r.source})`);
  }
}

async function seedSessions() {
  console.log('\n── Sessions ─────────────────────────────────────────────────────');
  for (const s of SESSIONS) {
    const { id, uid, ...data } = s;
    const docData = {
      ...data,
      id,
      uid,
      startedAt: ts(data.startedAt),
      finishedAt: ts(data.finishedAt),
    };
    const sessionRef = db
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(id);
    await sessionRef.set(docData);

    // setLogs: wipe leftovers first so a re-run with fewer sets can't leave
    // stale docs behind.
    const setLogsRef = sessionRef.collection('setLogs');
    await deleteAllDocs(setLogsRef);
    const logs = SETLOGS_BY_SESSION[id] ?? [];
    if (logs.length > 0) {
      const batch = db.batch();
      for (const log of logs) {
        batch.set(setLogsRef.doc(log.id), {
          ...log,
          completedAt: ts(log.completedAt),
        });
      }
      await batch.commit();
    }
    console.log(
      `  ✓ users/${uid}/sessions/${id} — ${data.routineName} ` +
      `[w=${data.weekNumber} d=${data.dayNumber}] ` +
      `${logs.length} sets, ${data.totalVolumeKg} kg ` +
      `${data.wasFullyCompleted ? '✅' : '⬡'}`,
    );
  }
}

// NOTE (deliberate tradeoff): the catalogue's canonical ids (bench-press,
// deadlift, …) do NOT match the exerciseIds the seed routines/sessions use
// (press-banca, peso-muerto, …). The seeded routines behave like routines
// built from custom exercises: Insights resolves their muscleGroup via the
// routine-slot fallback (English keys), while the catalogue's job here is to
// populate the exercise picker / CREAR RUTINA exactly like prod. Aligning the
// ids would orphan the muscle mapping of any session logged live in the
// emulator before a re-seed (their setLogs keep the old exerciseIds).
async function seedExercisesCatalog() {
  console.log('\n── Exercise catalogue ───────────────────────────────────────────');
  const batch = db.batch();
  for (const ex of CATALOG_EXERCISES) {
    batch.set(db.collection('exercises').doc(ex.id), buildExerciseDoc(ex));
  }
  await batch.commit();
  console.log(`  ✓ ${CATALOG_EXERCISES.length} ejercicios de catálogo (exercises/)`);
}

async function seedPosts() {
  console.log('\n── Posts ────────────────────────────────────────────────────────');
  for (const p of POSTS) {
    const { id, ...data } = p;
    await db.collection('posts').doc(id).set({
      ...data,
      createdAt: ts(data.createdAt),
    });
    console.log(`  ✓ posts/${id} [${data.privacy}] by ${data.authorUid}`);
  }
}

async function seedAppointments() {
  console.log('\n── Appointments ─────────────────────────────────────────────────');

  // An appointment's doc id embeds startsAt (`${trainerId}_${startsAtMs}`), so
  // once NOW follows the real clock a re-run writes NEW ids instead of
  // overwriting the previous ones — leaving last run's turnos behind. Drop this
  // seed's own appointments first so re-running stays idempotent. Scoped to the
  // seed trainers, so real data in the emulator is never touched.
  const seedTrainerIds = [...new Set(APPOINTMENTS.map(a => a.trainerId))];
  const stale = await db
    .collection('appointments')
    .where('trainerId', 'in', seedTrainerIds)
    .get();
  await Promise.all(stale.docs.map(d => d.ref.delete()));
  if (stale.size > 0) {
    console.log(`  ⌫ ${stale.size} turno(s) de corridas anteriores eliminados`);
  }

  for (const a of APPOINTMENTS) {
    const docId = apptDocId(a.trainerId, a.startsAt);
    const data = {
      id: docId,
      trainerId: a.trainerId,
      athleteId: a.athleteId,
      athleteDisplayName: a.athleteDisplayName,
      startsAt: ts(a.startsAt),
      durationMin: a.durationMin,
      status: a.status,
      cancellationLog: a.cancellationLog || [],
      cancelledAt: null,
      cancelledBy: null,
      noteBefore: null,
      noteAfter: null,
      recurringId: null,
    };
    await db.collection('appointments').doc(docId).set(data);
    console.log(
      `  ✓ appointments/${docId}  ${a.startsAt.toISOString().slice(0, 16)} — ${a.athleteDisplayName}`,
    );
  }
}

async function seedAvailabilityRules() {
  console.log('\n── Availability Rules ───────────────────────────────────────────');
  for (const rule of AVAILABILITY_RULES) {
    await db.collection('coach_availability_rules').doc(rule.id).set(rule);
    const days = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    console.log(
      `  ✓ ${rule.id} — ${rule.trainerId} ${days[rule.dayOfWeek]} ` +
      `${String(rule.startHour).padStart(2, '0')}:${String(rule.startMinute).padStart(2, '0')}–` +
      `${String(rule.endHour).padStart(2, '0')}:${String(rule.endMinute).padStart(2, '0')} ` +
      `(${rule.slotDurationMin} min)`,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Clear
// ────────────────────────────────────────────────────────────────────────────

async function deleteCollection(colPath, ids) {
  for (const id of ids) {
    await db.collection(colPath).doc(id).delete().catch(() => {});
  }
}

async function clear() {
  console.log('\n🗑  Clearing emulator seed data...\n');

  // Auth users
  const allUids = [...COACHES.map(c => c.uid), ...ATHLETES.map(a => a.uid)];
  for (const uid of allUids) {
    await auth.deleteUser(uid).catch(() => {});
    console.log(`  ✗ Auth user ${uid} deleted`);
  }

  // Firestore
  await deleteCollection('gyms', GYMS.map(g => g.id));
  await deleteCollection('users', allUids);
  // Coaches get a userPublicProfiles doc too (identity lookups) — clearing only
  // the athletes' would leave theirs orphaned.
  await deleteCollection('userPublicProfiles', [
    ...ATHLETES.map(a => a.uid),
    ...COACHES.map(c => c.uid),
  ]);
  await deleteCollection('trainerPublicProfiles', COACHES.map(c => c.uid));
  await deleteCollection('trainer_links', TRAINER_LINKS.map(l => l.id));
  await deleteCollection('friendships', FRIENDSHIPS.map(f => f.id));
  await deleteCollection('routines', ROUTINES.map(r => r.id));
  await deleteCollection('posts', POSTS.map(p => p.id));
  await deleteCollection('coach_availability_rules', AVAILABILITY_RULES.map(r => r.id));
  await deleteCollection('session_shares', TRAINER_LINKS.filter(l => l.sharedWithTrainer).map(l => l.athleteId));

  // Exercise catalogue
  await deleteCollection('exercises', CATALOG_EXERCISES.map(e => e.id));

  // Sessions (subcollections) — setLogs first: deleting the parent doc leaves
  // the subcollection orphaned otherwise.
  for (const s of SESSIONS) {
    const ref = db.collection('users').doc(s.uid).collection('sessions').doc(s.id);
    await deleteAllDocs(ref.collection('setLogs'));
    await ref.delete().catch(() => {});
  }

  // Appointments
  for (const a of APPOINTMENTS) {
    const docId = apptDocId(a.trainerId, a.startsAt);
    await db.collection('appointments').doc(docId).delete().catch(() => {});
  }

  console.log('\n  Clear complete.');
}

// ────────────────────────────────────────────────────────────────────────────
// Entrypoint
// ────────────────────────────────────────────────────────────────────────────

async function seed() {
  console.log('\n══════════════════════════════════════════════════════════════════');
  console.log('  TREINO Emulator Full Seed');
  console.log('══════════════════════════════════════════════════════════════════');

  await seedGyms();
  await seedCoaches();
  await seedAthletes();
  await seedTrainerLinks();
  await seedFriendships();
  await seedExercisesCatalog();
  await seedRoutines();
  await seedSessions();
  await seedPosts();
  await seedAppointments();
  await seedAvailabilityRules();

  console.log('\n══════════════════════════════════════════════════════════════════');
  console.log('  Seed complete.');
  console.log('══════════════════════════════════════════════════════════════════\n');
  console.log('Seeded accounts (EMULATOR-ONLY):');
  console.log('');
  console.log('  COACHES (role: trainer)');
  for (const c of COACHES) {
    console.log(`    ${c.email} / ${c.password}  (${c.displayName})`);
  }
  console.log('');
  console.log('  ATHLETES (role: athlete)');
  for (const a of ATHLETES) {
    console.log(`    ${a.email} / ${a.password}  (${a.displayName})`);
  }
  console.log('');
  console.log('App launch command:');
  console.log('  flutter run --dart-define=USE_EMULATOR=true');
  console.log('');
}

const flag = process.argv[2];
const action = flag === '--clear' ? clear : seed;

action()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\nSeed FAILED:', err);
    process.exit(1);
  });
