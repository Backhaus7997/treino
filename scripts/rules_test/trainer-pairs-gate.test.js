'use strict';

/**
 * #1806 — un PF sólo crea sobre un alumno con el que tiene un par VIVO
 * (`trainer_athlete_pairs/{pf}_{alumno}.live == true`), detrás del kill-switch
 * `app_config/trainer_pairs_gate.enabled` (ausente ⇒ apagado). Y #1723:
 * recuperar un plan asignado archivado pide lo mismo.
 *
 * Por colección, la matriz: flag ausente / en false (comportamiento de hoy),
 * flag prendido sin par, con par vivo (active y paused), con par muerto y con
 * el par vivo de OTRO PF. Después, lo que NO se gatea (updates de docs viejos,
 * la rama del alumno) y la lectura del par.
 *
 * Run via: bash scripts/test_rules.sh
 */

const { readFileSync } = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const PF = 'pairs-coach';
const OTRO_PF = 'pairs-other-coach';
const ALUMNO = 'pairs-athlete';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(RULES_PATH, 'utf8'), host: 'localhost', port: 8080 },
  });
}, 30000);

afterAll(async () => { await testEnv.cleanup(); });
afterEach(async () => { await testEnv.clearFirestore(); });

/** Siembra con las reglas apagadas: roles, flag, pares y docs previos. */
async function sembrar(docs) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    for (const [p, data] of Object.entries(docs)) await ctx.firestore().doc(p).set(data);
  });
}
const roles = {
  [`users/${PF}`]: { uid: PF, role: 'trainer' },
  [`users/${OTRO_PF}`]: { uid: OTRO_PF, role: 'trainer' },
  [`users/${ALUMNO}`]: { uid: ALUMNO, role: 'athlete' },
};
const flag = (enabled) => ({ 'app_config/trainer_pairs_gate': { enabled } });
const par = (trainerId, live, status) => ({
  [`trainer_athlete_pairs/${trainerId}_${ALUMNO}`]: { trainerId, athleteId: ALUMNO, live, status },
});
const db = (uid) => testEnv.authenticatedContext(uid).firestore();

/** Un create válido del PF sobre el alumno, por colección (payloads de coach-collections-role). */
const CREATES = {
  payments: (f) => f.doc('payments/p1').set({
    id: 'p1', trainerId: PF, athleteId: ALUMNO, amountArs: 15000, concept: 'Mensualidad',
    status: 'pending', createdAt: new Date(),
  }),
  measurements: (f) => f.doc('measurements/m1').set({ recordedBy: PF, athleteId: ALUMNO, recordedAt: new Date() }),
  performance_tests: (f) => f.doc('performance_tests/t1').set({
    recordedBy: PF, athleteId: ALUMNO, recordedAt: new Date(),
  }),
  athlete_billing: (f) => f.doc(`athlete_billing/${PF}_${ALUMNO}`).set({
    trainerId: PF, athleteId: ALUMNO, amountArs: 20000, cadence: 'mensual', updatedAt: new Date(),
  }),
  appointments: (f) => f.doc('appointments/a1').set({
    id: 'a1', trainerId: PF, athleteId: ALUMNO, athleteDisplayName: 'Atleta', durationMin: 60,
    startsAt: new Date(Date.now() + 3 * 86400000), status: 'confirmed', cancelledAt: null,
    cancelledBy: null, cancellationLog: [], noteBefore: null, noteAfter: null, recurringId: null, paymentId: null,
  }),
  nutrition_plans: (f) => f.doc(`nutrition_plans/${PF}_${ALUMNO}`).set({
    trainerId: PF, athleteId: ALUMNO, title: 'Plan', meals: [],
  }),
  athlete_files: (f) => f.doc(`athlete_files/${PF}_${ALUMNO}_1`).set({
    trainerId: PF, athleteId: ALUMNO, fileName: 'plan.pdf', storagePath: `athleteFiles/${PF}_${ALUMNO}/1.pdf`,
    downloadUrl: 'https://example.test/f.pdf?token=abc', sizeBytes: 1024, sharedWithAthlete: true,
  }),
};

const MATRIZ = [
  ['flag ausente, sin par: como hoy', {}, assertSucceeds],
  ['flag en false, sin par: como hoy', flag(false), assertSucceeds],
  ['flag prendido, sin par', flag(true), assertFails],
  ['flag prendido, par vivo (active)', { ...flag(true), ...par(PF, true, 'active') }, assertSucceeds],
  ['flag prendido, par vivo (paused)', { ...flag(true), ...par(PF, true, 'paused') }, assertSucceeds],
  ['flag prendido, par muerto (terminated)', { ...flag(true), ...par(PF, false, 'terminated') }, assertFails],
  ['flag prendido, el par vivo es de OTRO PF', { ...flag(true), ...par(OTRO_PF, true, 'active') }, assertFails],
  ['flag con un valor no booleano: apagado', { 'app_config/trainer_pairs_gate': { enabled: 'yes' } }, assertSucceeds],
];

describe.each(Object.keys(CREATES))('%s: create del PF', (col) => {
  test.each(MATRIZ)('%s', async (_name, semilla, esperado) => {
    await sembrar({ ...roles, ...semilla });
    await esperado(CREATES[col](db(PF)));
  });
});

test('un par con el id correcto pero otro trainerId adentro no autoriza', async () => {
  await sembrar({
    ...roles, ...flag(true),
    [`trainer_athlete_pairs/${PF}_${ALUMNO}`]: { trainerId: OTRO_PF, athleteId: ALUMNO, live: true, status: 'active' },
  });
  await assertFails(CREATES.payments(db(PF)));
});

describe('lo que NO se gatea (flag prendido, par muerto)', () => {
  const exAlumno = { ...roles, ...flag(true), ...par(PF, false, 'terminated') };

  test('el PF marca pagado un cobro viejo de un ex-alumno', async () => {
    await sembrar({
      ...exAlumno,
      'payments/viejo': { id: 'viejo', trainerId: PF, athleteId: ALUMNO, amountArs: 1000, concept: 'Cuota',
        status: 'pending', createdAt: new Date() },
    });
    await assertSucceeds(db(PF).doc('payments/viejo').update({ status: 'paid', paidAt: new Date() }));
  });

  test('el PF corrige una medición que él cargó', async () => {
    await sembrar({ ...exAlumno, 'measurements/m0': { recordedBy: PF, athleteId: ALUMNO, recordedAt: new Date() } });
    await assertSucceeds(db(PF).doc('measurements/m0').update({ weightKg: 80 }));
  });

  test('el alumno se carga su propia medición y se reserva su turno, sin par', async () => {
    await sembrar({ ...roles, ...flag(true) });
    const f = db(ALUMNO);
    await assertSucceeds(f.doc('measurements/self').set({ recordedBy: ALUMNO, athleteId: ALUMNO, recordedAt: new Date() }));
    await assertSucceeds(f.doc('appointments/self').set({
      id: 'self', trainerId: PF, athleteId: ALUMNO, athleteDisplayName: 'Atleta', durationMin: 60,
      startsAt: new Date(Date.now() + 3 * 86400000), status: 'confirmed', cancelledAt: null,
      cancelledBy: null, cancellationLog: [], noteBefore: null, noteAfter: null, recurringId: null, paymentId: null,
    }));
  });
});

describe('#1723: recuperar un plan asignado archivado', () => {
  const plan = (status) => ({
    'routines/r1': {
      name: 'Fuerza', split: 'Upper/Lower', level: 'intermediate', days: [], numWeeks: 4, createdAt: new Date(),
      source: 'trainer-assigned', assignedBy: PF, assignedTo: ALUMNO, visibility: 'private', status,
    },
  });
  const recuperar = () => db(PF).doc('routines/r1').update({ status: 'active' });

  test.each([
    ['flag ausente, sin par', {}, assertSucceeds],
    ['flag prendido, sin par (ex-PF)', flag(true), assertFails],
    ['flag prendido, par muerto', { ...flag(true), ...par(PF, false, 'terminated') }, assertFails],
    ['flag prendido, par vivo', { ...flag(true), ...par(PF, true, 'active') }, assertSucceeds],
  ])('%s', async (_name, semilla, esperado) => {
    await sembrar({ ...roles, ...semilla, ...plan('archived') });
    await esperado(recuperar());
  });

  test('archivar no pide par: es la salida', async () => {
    await sembrar({ ...roles, ...flag(true), ...plan('active') });
    await assertSucceeds(db(PF).doc('routines/r1').update({ status: 'archived' }));
  });
});

describe('trainer_athlete_pairs y el flag: sólo lectura de los miembros', () => {
  const ID = `trainer_athlete_pairs/${PF}_${ALUMNO}`;

  test('el PF y el alumno leen su par; un tercero no; nadie lo escribe', async () => {
    await sembrar({ ...roles, ...par(PF, true, 'active') });
    await assertSucceeds(db(PF).doc(ID).get());
    await assertSucceeds(db(ALUMNO).doc(ID).get());
    await assertFails(db(OTRO_PF).doc(ID).get());
    await assertFails(db(PF).collection('trainer_athlete_pairs').get());
    await assertFails(db(PF).doc(ID).update({ live: true }));
    await assertFails(db(OTRO_PF).doc(`trainer_athlete_pairs/${OTRO_PF}_${ALUMNO}`).set({
      trainerId: OTRO_PF, athleteId: ALUMNO, live: true, status: 'active',
    }));
  });

  test('un par que no existe no se lee (ni siendo uno de los uids del id)', async () => {
    await sembrar(roles);
    await assertFails(db(PF).doc(ID).get());
  });

  test('ningún cliente lee ni escribe el kill-switch', async () => {
    await sembrar({ ...roles, ...flag(false) });
    await assertFails(db(PF).doc('app_config/trainer_pairs_gate').get());
    await assertFails(db(PF).doc('app_config/trainer_pairs_gate').set({ enabled: false }));
  });
});
