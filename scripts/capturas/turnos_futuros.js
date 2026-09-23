// EMULATOR-ONLY. Turnos futuros para seed-coach-001. Los del seed base tienen
// fecha fija de septiembre y ya vencieron: el home del PF muestra
// "No tenes turnos proximos confirmados", que es un empty state.
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

// Hora local ART = UTC-3. 17:00 ART de hoy y 10:00 ART de manana.
const turnos = [
  { athleteId: 'seed-athlete-002', nombre: 'Sofía Ramírez', diasDesdeHoy: 0, horaArt: 17 },
  { athleteId: 'seed-athlete-001', nombre: 'Martín López', diasDesdeHoy: 1, horaArt: 10 },
  { athleteId: 'seed-athlete-003', nombre: 'Mateo Quiroga', diasDesdeHoy: 1, horaArt: 18 },
];

(async () => {
  const b = db.batch();
  const ids = [];
  turnos.forEach((t) => {
    const d = new Date(Date.UTC(HOY.getUTCFullYear(), HOY.getUTCMonth(), HOY.getUTCDate() + t.diasDesdeHoy, t.horaArt + 3, 0, 0));
    const id = `seed-coach-001_${d.getTime()}`;
    ids.push(`${t.nombre} ${d.toISOString()}`);
    b.set(db.collection('appointments').doc(id), {
      id, trainerId: 'seed-coach-001', athleteId: t.athleteId,
      athleteDisplayName: t.nombre, startsAt: T.fromDate(d), durationMin: 60,
      status: 'confirmed', cancellationLog: [], cancelledAt: null, cancelledBy: null,
      noteBefore: null, noteAfter: null, recurringId: null,
    });
  });
  await b.commit();
  const futuros = await db.collection('appointments')
    .where('trainerId', '==', 'seed-coach-001')
    .where('startsAt', '>', T.fromDate(new Date())).get();
  console.log('turnos creados:', ids.join(' | '));
  console.log('turnos futuros que ve el PF:', futuros.size);
})().catch((e) => { console.error(e); process.exit(1); });
