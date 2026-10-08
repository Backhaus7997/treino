// EMULATOR-ONLY. Una sesion de HOY para seed-athlete-001, para que la tarjeta
// de racha no caiga en "TU RACHA TE ESPERA". El seed base reparte los dias del
// mes en curso y puede no tocar hoy.
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
const UID = 'seed-athlete-001';
const HOY = new Date();

(async () => {
  const rutina = (await db.collection('routines').doc('seed-routine-001').get()).data();
  const dia = rutina.days[0];
  const inicio = new Date(Date.UTC(HOY.getUTCFullYear(), HOY.getUTCMonth(), HOY.getUTCDate(), 11, 5));
  const id = 'cap-hoy-athlete-001';
  const dur = 54;
  const logs = []; let vol = 0, n = 0;
  dia.slots.forEach((slot) => {
    const peso = slot.targetWeightKg ?? 0;
    const reps = slot.targetRepsMin ?? 8;
    for (let s = 1; s <= (slot.targetSets ?? 3); s++) {
      n++; vol += reps * peso;
      logs.push({ id: `${id}-set-${String(n).padStart(2, '0')}`, exerciseId: slot.exerciseId, exerciseName: slot.exerciseName, setNumber: s, reps, weightKg: peso, rpe: null, _o: n });
    }
  });
  const paso = Math.floor(((dur - 4) * 60_000) / Math.max(1, logs.length - 1));
  const ref = db.collection('users').doc(UID).collection('sessions').doc(id);
  const b = db.batch();
  b.set(ref, { id, uid: UID, routineId: 'seed-routine-001', routineName: rutina.name,
    startedAt: T.fromDate(inicio), finishedAt: T.fromDate(new Date(inicio.getTime() + dur * 60_000)),
    totalVolumeKg: vol, durationMin: dur, status: 'finished', dayNumber: dia.dayNumber,
    weekNumber: 0, wasFullyCompleted: true });
  logs.forEach((l) => { const { _o, ...d } = l; b.set(ref.collection('setLogs').doc(l.id), { ...d, completedAt: T.fromDate(new Date(inicio.getTime() + 120_000 + (_o - 1) * paso)) }); });
  await b.commit();
  console.log(`sesion de hoy para ${UID}: ${inicio.toISOString()} | ${vol} kg | ${logs.length} sets`);
})().catch((e) => { console.error(e); process.exit(1); });
