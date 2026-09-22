/**
 * seed_cobros_pendientes.js — EMULATOR-ONLY.
 *
 * Crea cobros `pending` para los alumnos del PF de las capturas, para que el
 * card «PAGOS POR COBRAR» del dashboard del entrenador NO salga en su empty
 * state («Sin cobros pendientes»).
 *
 * Por qué existe: una captura de tienda no puede mostrar un empty state. El
 * seed base no siembra la colección `payments`, así que el card del dashboard
 * salía vacío y la captura 06 quedaba inservible de la mitad para abajo.
 *
 * Qué lee la app (`pagosPorCobrarProvider`): documentos de `payments` con
 * `trainerId` del PF, `athleteId` de un vínculo `active` o `paused`, y
 * `status: 'pending'`. Agrupa por alumno y suma `amountArs`.
 *
 * Idempotente: borra sus propios documentos (`cap-cobro-*`) antes de escribir.
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

const COACH = 'seed-coach-001';

// Importes en pesos, en el orden en que se asignan a los alumnos encontrados.
const IMPORTES = [32000, 32000];
const CONCEPTOS = ['Plan mensual · Septiembre', 'Plan mensual · Septiembre'];

(async () => {
  // 1. Borrar lo que sembró una corrida anterior.
  const previos = await db
    .collection('payments')
    .where('trainerId', '==', COACH)
    .get();
  let borrados = 0;
  for (const doc of previos.docs) {
    if (doc.id.startsWith('cap-cobro-')) {
      await doc.ref.delete();
      borrados++;
    }
  }

  // 2. Vínculos facturables del PF: el provider acepta 'active' y 'paused'.
  const links = await db
    .collection('trainer_links')
    .where('trainerId', '==', COACH)
    .get();
  // Sólo alumnos con UN vínculo facturable, y no es una manía.
  //
  // El seed base y la capa de capturas crean CADA UNO su vínculo para los
  // mismos alumnos: `seed-link-001` y `cap-link-001` apuntan los dos a
  // `seed-athlete-001`, los dos `active`. Y `pagosPorCobrarProvider` itera
  // VÍNCULOS, no alumnos (`for (final link in billableLinks)`), así que con
  // dos vínculos facturables el MISMO cobro se agrega dos veces al resultado.
  // Medido: sembré 2 pagos y la pantalla dibujó 4 filas, dos de ellas con el
  // mismo alumno y el mismo importe.
  //
  // Deduplicar acá no arreglaría nada —la duplicación la produce el provider,
  // no la semilla—, así que se facturan sólo los alumnos cuyo conteo de
  // vínculos facturables es exactamente 1. La captura queda determinística sin
  // tocar el provider.
  const porAlumno = new Map();
  for (const l of links.docs.map((d) => d.data())) {
    if (l.status !== 'active' && l.status !== 'paused') continue;
    porAlumno.set(l.athleteId, (porAlumno.get(l.athleteId) ?? 0) + 1);
  }
  const duplicados = [...porAlumno.entries()].filter(([, n]) => n > 1);
  if (duplicados.length > 0) {
    console.log(
      `AVISO: ${duplicados.length} alumno(s) con vínculo facturable duplicado ` +
        `(${duplicados.map(([a, n]) => `${a}×${n}`).join(', ')}); se los saltea ` +
        'porque el provider los contaría doble.',
    );
  }
  const facturables = [...porAlumno.entries()]
    .filter(([, n]) => n === 1)
    .map(([a]) => a)
    .sort();

  if (facturables.length === 0) {
    console.error('ERROR: el PF no tiene vínculos activos. Corré antes seed_emulator_full.js.');
    process.exit(1);
  }

  // 3. Un cobro pendiente por alumno, hasta agotar los importes.
  const ahora = new Date();
  const vence = new Date(ahora.getTime() + 5 * 24 * 60 * 60 * 1000);
  const creados = [];
  for (let i = 0; i < Math.min(IMPORTES.length, facturables.length); i++) {
    const athleteId = facturables[i];
    const id = `cap-cobro-${athleteId}`;
    await db.collection('payments').doc(id).set({
      id,
      trainerId: COACH,
      athleteId,
      amountArs: IMPORTES[i],
      concept: CONCEPTOS[i],
      status: 'pending',
      periodKey: `${ahora.getUTCFullYear()}-${String(ahora.getUTCMonth() + 1).padStart(2, '0')}`,
      createdAt: T.fromDate(ahora),
      dueAt: T.fromDate(vence),
    });
    creados.push(`${athleteId}: $${IMPORTES[i].toLocaleString('es-AR')}`);
  }

  const total = IMPORTES.slice(0, creados.length).reduce((a, b) => a + b, 0);
  console.log(`cobros cap-* borrados: ${borrados} | creados: ${creados.length}`);
  console.log(`  ${creados.join(' | ')}`);
  console.log(`  total por cobrar: $${total.toLocaleString('es-AR')}`);
  process.exit(0);
})();
