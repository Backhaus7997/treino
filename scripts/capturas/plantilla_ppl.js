// EMULATOR-ONLY. Plantilla "Fuerza PPL" completa para seed-coach-001, para la
// captura del editor de rutina. La libreria del PF la lista con
// where('assignedBy' == trainerId) + source 'trainer-template'
// (routine_repository.dart:710) — NO con createdBy.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
if (!process.env.FIRESTORE_EMULATOR_HOST) { console.error('solo emulador'); process.exit(1); }
// API modular (`firebase-admin/app`, `firebase-admin/firestore`), no la
// namespaced: firebase-admin 14 borró `admin.firestore()` y
// `admin.firestore.Timestamp` enteros. Lo fija
// `scripts/test/firebase_admin_superficie.test.js`.
const app = initializeApp({ projectId: 'treino-dev' });
const db = getFirestore(app);
const T = Timestamp;
const COACH = 'seed-coach-001';

const DIAS = [
  { name: 'Push – Empuje', min: 55, ex: [
    ['bench-press', 4, 5, 6, 80, 180], ['incline-dumbbell-press', 3, 8, 10, 30, 120],
    ['overhead-press', 3, 6, 8, 50, 150], ['lateral-raise', 3, 12, 15, 10, 90],
    ['tricep-pushdown', 3, 10, 12, 30, 90] ] },
  { name: 'Pull – Tirón', min: 55, ex: [
    ['deadlift', 4, 4, 5, 120, 210], ['barbell-row', 4, 6, 8, 70, 150],
    ['lat-pulldown', 3, 8, 10, 60, 120], ['barbell-curl', 3, 8, 10, 30, 90],
    ['face-pull', 3, 12, 15, 20, 75] ] },
  { name: 'Legs – Piernas', min: 60, ex: [
    ['back-squat', 4, 5, 6, 100, 180], ['romanian-deadlift', 3, 8, 10, 90, 150],
    ['leg-press', 3, 10, 12, 180, 120], ['leg-curl', 3, 10, 12, 45, 90],
    ['calf-raise', 4, 12, 15, 60, 60] ] },
];

(async () => {
  const cat = {};
  (await db.collection('exercises').get()).forEach((d) => { cat[d.id] = d.data(); });
  const faltan = DIAS.flatMap((d) => d.ex.map((e) => e[0])).filter((id) => !cat[id]);
  if (faltan.length) throw new Error(`exerciseId inexistentes en el catalogo: ${faltan.join(', ')}`);

  const days = DIAS.map((d, i) => ({
    dayNumber: i + 1,
    name: d.name,
    estimatedMinutes: d.min,
    slots: d.ex.map(([id, sets, rmin, rmax, kg, rest]) => ({
      exerciseId: id,
      exerciseName: cat[id].name ?? id,
      muscleGroup: cat[id].muscleGroup ?? null,
      targetSets: sets, targetRepsMin: rmin, targetRepsMax: rmax,
      restSeconds: rest, targetWeightKg: kg,
      notes: null, supersetGroup: null, targetReps: [], durationSeconds: null,
      exerciseMode: 'reps', repMode: 'single',
      sets: Array.from({ length: sets }, () => ({ type: 'normal', weightKg: kg, reps: rmin, repsMin: null, repsMax: null, durationSeconds: null })),
      weeklySets: [], activeWeeks: [],
    })),
  }));

  await db.collection('routines').doc('cap-template-ppl').set({
    id: 'cap-template-ppl',
    name: 'Fuerza PPL',
    split: 'PPL',
    summary: 'Empujar, tirar y piernas: cada dia trabajas un tipo de movimiento distinto.',
    level: 'intermediate',
    numWeeks: 1,
    source: 'trainer-template',
    assignedBy: COACH,
    assignedTo: null,
    createdBy: COACH,
    visibility: 'private',
    estimatedMinutesPerDay: 55,
    imageUrl: null,
    days,
    status: 'active',
    createdAt: T.fromDate(new Date(Date.now() - 12 * 86_400_000)),
  }, { merge: true });

  const q = await db.collection('routines').where('assignedBy', '==', COACH).where('source', '==', 'trainer-template').get();
  console.log('plantillas del PF:', q.size, '->', q.docs.map((d) => `${d.get('name')} (${d.get('days').length} dias, ${d.get('days').map((x) => x.slots.length).join('/')} ejercicios)`).join(' | '));
})().catch((e) => { console.error(e.message); process.exit(1); });
