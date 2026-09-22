/**
 * seed_capturas_store.js — EMULATOR-ONLY.
 *
 * Capa de datos ENCIMA de scripts/seed_emulator_full.js para las capturas de
 * tienda (issue #629). No reemplaza al seed base: lo requiere corrido antes.
 *
 * Hace tres cosas, y ninguna toca el seed compartido:
 *  1. Rellena `bornAt` en todos los users. El seed base es anterior al gate de
 *     edad minima de 13 anios (`/birth-date`), asi que HOY todo usuario
 *     sembrado queda trabado en ese muro y no se puede entrar a la app.
 *  2. Extiende el historial de seed-athlete-001 a ~8 meses con densidad
 *     creciente. El reporte mensual dibuja 12 barras fijas
 *     (monthlyReportWindowSize), no 5: con los 2 meses del seed base el
 *     grafico sale casi vacio.
 *  3. Deja 5 vinculos activos en seed-coach-001 para el panel del entrenador.
 *
 * Idempotente: borra sus propias sesiones (`cap-*`) antes de reescribirlas.
 * Nunca toca las del seed base.
 */
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('ERROR: sin FIRESTORE_EMULATOR_HOST. Este script es solo para el emulador.');
  process.exit(1);
}
// API modular (`firebase-admin/app`, `firebase-admin/firestore`), no la
// namespaced: firebase-admin 14 borró `admin.firestore()` y
// `admin.firestore.Timestamp` enteros. Lo fija
// `scripts/test/firebase_admin_superficie.test.js`.
const app = initializeApp({ projectId: 'treino-dev' });
const db = getFirestore(app);
const T = Timestamp;

const UID = 'seed-athlete-001';
const ROUTINE_ID = 'seed-routine-001';
const COACH = 'seed-coach-001';
const HOY = new Date();

// Entrenos por mes, del mas viejo al actual. Creciente para que las flechas de
// tendencia salgan verdes hacia arriba. El seed base ya aporta 4 en agosto y 8
// en septiembre, asi que estos numeros son EL AGREGADO, no el total.
const POR_MES = [
  { atras: 11, n: 3 }, { atras: 10, n: 4 }, { atras: 9, n: 4 }, { atras: 8, n: 5 },
  { atras: 7, n: 6 }, { atras: 6, n: 8 }, { atras: 5, n: 10 }, { atras: 4, n: 12 },
  { atras: 3, n: 13 }, { atras: 2, n: 15 }, { atras: 1, n: 14 }, { atras: 0, n: 12 },
];

const redondearDisco = (kg) => Math.round(kg / 2.5) * 2.5;

/**
 * Reparte `n` dias dentro del mes `atras` meses atras del actual.
 * En el mes en curso solo usa dias ya transcurridos: una sesion con fecha
 * futura es un dato que la app no puede producir.
 */
function diasDelMes(atras, n) {
  const ancla = new Date(Date.UTC(HOY.getUTCFullYear(), HOY.getUTCMonth() - atras, 1));
  const anio = ancla.getUTCFullYear();
  const mes = ancla.getUTCMonth();
  const ultimo = atras === 0 ? HOY.getUTCDate() : new Date(Date.UTC(anio, mes + 1, 0)).getUTCDate();
  const paso = ultimo / (n + 1);
  const dias = [];
  for (let i = 1; i <= n; i++) {
    const d = Math.max(1, Math.min(ultimo, Math.round(i * paso)));
    // 13:00 UTC = 10:00 ART. El bucketing del reporte usa hora argentina, asi
    // que la hora tiene que caer lejos de los bordes del dia en LAS DOS zonas.
    dias.push(new Date(Date.UTC(anio, mes, d, 13, 0, 0)));
  }
  return dias;
}

(async () => {
  // ── 1. bornAt ──────────────────────────────────────────────────────────────
  const users = await db.collection('users').get();
  let bornAtEscritos = 0;
  const bu = db.batch();
  users.forEach((doc) => {
    if (doc.get('bornAt')) return;
    bu.set(doc.ref, { bornAt: T.fromDate(new Date(Date.UTC(1992, 3, 17, 12))) }, { merge: true });
    bornAtEscritos++;
  });
  if (bornAtEscritos) await bu.commit();

  // ── 2. historial ───────────────────────────────────────────────────────────
  const rutina = (await db.collection('routines').doc(ROUTINE_ID).get()).data();
  if (!rutina) throw new Error(`falta ${ROUTINE_ID}: correr seed_emulator_full.js primero`);
  const dias = rutina.days;

  const sesiones = db.collection('users').doc(UID).collection('sessions');
  // Borrado de las propias, con sus setLogs.
  const viejas = await sesiones.get();
  let borradas = 0;
  for (const doc of viejas.docs) {
    if (!doc.id.startsWith('cap-')) continue;
    const logs = await doc.ref.collection('setLogs').get();
    const b = db.batch();
    logs.forEach((l) => b.delete(l.ref));
    b.delete(doc.ref);
    await b.commit();
    borradas++;
  }

  const fechas = POR_MES.flatMap(({ atras, n }) => diasDelMes(atras, n)).sort((a, b) => a - b);
  const total = fechas.length;
  let creadas = 0;
  let setsTotales = 0;

  for (let i = 0; i < total; i++) {
    const inicio = fechas[i];
    const dia = dias[i % dias.length];
    // Progresion 62% -> 100% del peso objetivo a lo largo de todo el historial.
    const p = total > 1 ? i / (total - 1) : 1;
    const factor = 0.62 + 0.38 * p;
    const durationMin = 48 + (i % 5) * 3;
    const id = `cap-${String(i + 1).padStart(3, '0')}`;

    const logs = [];
    let volumen = 0;
    let nSet = 0;
    dia.slots.forEach((slot) => {
      const peso = slot.targetWeightKg ? redondearDisco(slot.targetWeightKg * factor) : 0;
      const reps = slot.targetRepsMin ?? 8;
      for (let s = 1; s <= (slot.targetSets ?? 3); s++) {
        nSet++;
        volumen += reps * peso;
        logs.push({
          id: `${id}-set-${String(nSet).padStart(2, '0')}`,
          exerciseId: slot.exerciseId,
          exerciseName: slot.exerciseName,
          setNumber: s,
          reps,
          weightKg: peso,
          rpe: null,
          _orden: nSet,
        });
      }
    });

    const paso = Math.floor(((durationMin - 4) * 60_000) / Math.max(1, logs.length - 1));
    const b = db.batch();
    b.set(sesiones.doc(id), {
      id,
      uid: UID,
      routineId: ROUTINE_ID,
      routineName: rutina.name,
      startedAt: T.fromDate(inicio),
      finishedAt: T.fromDate(new Date(inicio.getTime() + durationMin * 60_000)),
      totalVolumeKg: volumen,
      durationMin,
      status: 'finished',
      dayNumber: dia.dayNumber,
      weekNumber: Math.floor(i / dias.length) % (rutina.numWeeks || 1),
      wasFullyCompleted: true,
    });
    logs.forEach((l) => {
      const { _orden, ...doc } = l;
      b.set(sesiones.doc(id).collection('setLogs').doc(l.id), {
        ...doc,
        completedAt: T.fromDate(new Date(inicio.getTime() + 120_000 + (_orden - 1) * paso)),
      });
    });
    await b.commit();
    creadas++;
    setsTotales += logs.length;
  }

  // ── 3. vinculos del entrenador ─────────────────────────────────────────────
  const alumnos = ['seed-athlete-001', 'seed-athlete-002', 'seed-athlete-003', 'seed-athlete-004', 'seed-athlete-005'];
  const bl = db.batch();
  alumnos.forEach((a, i) => {
    const id = `cap-link-${String(i + 1).padStart(3, '0')}`;
    bl.set(db.collection('trainer_links').doc(id), {
      id,
      trainerId: COACH,
      athleteId: a,
      status: 'active',
      requestedAt: T.fromDate(new Date(HOY.getTime() - (120 - i * 9) * 86_400_000)),
      acceptedAt: T.fromDate(new Date(HOY.getTime() - (118 - i * 9) * 86_400_000)),
      terminatedAt: null,
      terminationReason: null,
      pausedAt: null,
      sharedWithTrainer: true,
    }, { merge: true });

    // El grant REAL, que es lo que miran las reglas. `sharedWithTrainer: true`
    // en el vínculo es sólo la intención: `firestore.rules` deja al PF leer
    // las sesiones de un alumno si existe `session_shares/{athleteId}` y su
    // `trainerId` es el suyo (regla de `match /sessions/`). Sin este doc, el
    // dashboard pide las sesiones y se come un permission-denied.
    //
    // Sin esto, «ENTRENARON HOY» salía VACÍO con las reglas puestas y lleno
    // con el emulador sin reglas — que es como se sacó la primera tanda de
    // capturas, y por eso la 06 mostraba filas que un PF real no ve. El seed
    // base sólo otorga `seed-athlete-001`, y el de `seed-athlete-003` apunta a
    // `seed-coach-002`: va `{ merge: true }` para pisarle el trainerId.
    bl.set(db.collection('session_shares').doc(a), {
      trainerId: COACH,
    }, { merge: true });
  });
  await bl.commit();

  // ── Control: releer y contar lo que el reporte va a ver ────────────────────
  const post = await sesiones.get();
  const porMes = {};
  post.forEach((d) => {
    const v = d.data();
    if (v.status !== 'finished' || v.wasFullyCompleted !== true) return;
    const t = new Date(v.startedAt.toDate().getTime() - 3 * 3600_000); // ART
    const k = `${t.getUTCFullYear()}-${String(t.getUTCMonth() + 1).padStart(2, '0')}`;
    porMes[k] = (porMes[k] || 0) + 1;
  });
  const links = await db.collection('trainer_links').where('trainerId', '==', COACH).where('status', '==', 'active').get();

  console.log(`bornAt escritos: ${bornAtEscritos} (usuarios: ${users.size})`);
  console.log(`sesiones cap-* borradas: ${borradas} | creadas: ${creadas} | setLogs: ${setsTotales}`);
  console.log(`entrenos que CUENTAN, por mes (hora argentina):`, JSON.stringify(porMes));
  console.log(`vinculos activos de ${COACH}: ${links.size}`);
})().catch((e) => { console.error(e); process.exit(1); });
