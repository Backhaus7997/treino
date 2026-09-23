// EMULATOR-ONLY. Suma 2 rutinas propias a seed-athlete-001 para que
// "MIS RUTINAS" no muestre una sola card. El badge ACTIVA lo decide
// users/{uid}.activeRoutineId, no el status: las tres quedan `active` y
// el badge sigue en la del coach.
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

(async () => {
  const base = (await db.collection('routines').doc('seed-routine-001').get()).data();
  const nuevas = [
    { id: 'cap-routine-upper-lower', name: 'Upper / Lower', split: 'Upper/Lower', level: 'intermediate', min: 45, dias: 4 },
    { id: 'cap-routine-full-body', name: 'Full Body Base', split: 'Full Body', level: 'beginner', min: 38, dias: 3 },
  ];
  const b = db.batch();
  for (const r of nuevas) {
    // Reusa los dias reales de la rutina base, ciclandolos: un slot inventado
    // podria referenciar un exerciseId que no existe en el catalogo.
    const days = Array.from({ length: r.dias }, (_, i) => ({
      ...base.days[i % base.days.length],
      dayNumber: i + 1,
      estimatedMinutes: r.min,
    }));
    b.set(db.collection('routines').doc(r.id), {
      id: r.id,
      name: r.name,
      split: r.split,
      level: r.level,
      numWeeks: 4,
      source: 'user-created',
      assignedBy: null,
      assignedTo: null,
      createdBy: UID,
      visibility: 'private',
      estimatedMinutesPerDay: r.min,
      imageUrl: null,
      days,
      status: 'active',
      createdAt: T.fromDate(new Date(Date.now() - 60 * 86_400_000)),
    }, { merge: true });
  }
  await b.commit();
  const mias = await db.collection('routines').where('createdBy', '==', UID).get();
  const perfil = await db.collection('users').doc(UID).get();
  console.log('rutinas de', UID, '=', mias.size, '->', mias.docs.map((d) => `${d.get('name')}[${d.get('source')}]`).join(' | '));
  console.log('activeRoutineId:', perfil.get('activeRoutineId'));
})().catch((e) => { console.error(e); process.exit(1); });
