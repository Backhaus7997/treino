// EMULATOR-ONLY. Una sesion de HOY para dos alumnas de seed-coach-001, para
// que "ENTRENARON HOY" no quede en empty state en el home del entrenador.
// NO toca a seed-athlete-001: sus capturas ya estan tomadas y el doc exige
// que los numeros sean coherentes entre capturas.
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

const HOY = new Date();
const alumnos = [
  { uid: 'seed-athlete-002', routineId: 'seed-routine-003', hora: 8, dur: 47 },
  { uid: 'seed-athlete-003', routineId: 'seed-routine-002', hora: 7, dur: 52 },
];

(async () => {
  for (const a of alumnos) {
    const rutina = (await db.collection('routines').doc(a.routineId).get()).data();
    const dia = rutina.days[0];
    // Hora local de Argentina: hora + 3 = UTC. Una sesion de hoy tiene que
    // caer HOY tambien en hora argentina, que es con la que buckets y
    // "entrenaron hoy" comparan.
    const inicio = new Date(Date.UTC(HOY.getUTCFullYear(), HOY.getUTCMonth(), HOY.getUTCDate(), a.hora + 3, 15));
    const id = `cap-hoy-${a.uid}`;
    const logs = [];
    let vol = 0, n = 0;
    dia.slots.forEach((slot) => {
      const peso = slot.targetWeightKg ?? 0;
      const reps = slot.targetRepsMin ?? 10;
      for (let s = 1; s <= (slot.targetSets ?? 3); s++) {
        n++; vol += reps * peso;
        logs.push({ id: `${id}-set-${String(n).padStart(2, '0')}`, exerciseId: slot.exerciseId, exerciseName: slot.exerciseName, setNumber: s, reps, weightKg: peso, rpe: null, _o: n });
      }
    });
    const paso = Math.floor(((a.dur - 4) * 60_000) / Math.max(1, logs.length - 1));
    const ref = db.collection('users').doc(a.uid).collection('sessions').doc(id);
    const b = db.batch();
    b.set(ref, {
      id, uid: a.uid, routineId: a.routineId, routineName: rutina.name,
      startedAt: T.fromDate(inicio),
      finishedAt: T.fromDate(new Date(inicio.getTime() + a.dur * 60_000)),
      totalVolumeKg: vol, durationMin: a.dur, status: 'finished',
      dayNumber: dia.dayNumber, weekNumber: 0, wasFullyCompleted: true,
    });
    logs.forEach((l) => { const { _o, ...d } = l; b.set(ref.collection('setLogs').doc(l.id), { ...d, completedAt: T.fromDate(new Date(inicio.getTime() + 120_000 + (_o - 1) * paso)) }); });
    await b.commit();
    console.log(`${a.uid}: sesion de hoy ${inicio.toISOString()} | ${vol} kg | ${logs.length} sets`);
  }
})().catch((e) => { console.error(e); process.exit(1); });
