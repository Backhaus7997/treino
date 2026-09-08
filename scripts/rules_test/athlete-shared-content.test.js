'use strict';

/**
 * Firestore Security Rules test suite — contenido compartido con el alumno.
 *
 * Fija dos contratos: el alumno puede leer su plan nutricional y solamente
 * puede consultar archivos cuyo `sharedWithAthlete` sea verdadero. La query de
 * archivos debe incluir tanto `athleteId` como el flag para que Firestore pueda
 * demostrar que todos los resultados cumplen la regla.
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const TRAINER_ID = 'coach-shared';
const ATHLETE_ID = 'athlete-shared';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedNutritionPlan() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('nutrition_plans')
      .doc(`${TRAINER_ID}_${ATHLETE_ID}`)
      .set({
        id: `${TRAINER_ID}_${ATHLETE_ID}`,
        trainerId: TRAINER_ID,
        athleteId: ATHLETE_ID,
        title: 'Plan semanal',
        meals: [],
        updatedAt: new Date(),
      });
  });
}

function athleteFileData({ sharedWithAthlete, downloadUrl = 'https://example.test/file' } = {}) {
  const data = {
    id: `${TRAINER_ID}_${ATHLETE_ID}_1`,
    trainerId: TRAINER_ID,
    athleteId: ATHLETE_ID,
    fileName: 'plan.pdf',
    kind: 'pdf',
    contentType: 'application/pdf',
    sizeBytes: 128,
    storagePath: `athleteFiles/${TRAINER_ID}_${ATHLETE_ID}/1.pdf`,
    downloadUrl,
    uploadedAt: new Date('2026-07-02T12:00:00Z'),
  };
  if (sharedWithAthlete !== undefined) {
    data.sharedWithAthlete = sharedWithAthlete;
  }
  return data;
}

async function seedAthleteFile(docId, options) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('athlete_files')
      .doc(docId)
      .set({ ...athleteFileData(options), id: docId });
  });
}

test('el alumno puede leer su propio plan nutricional', async () => {
  await seedNutritionPlan();
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  await assertSucceeds(
    athlete
      .firestore()
      .collection('nutrition_plans')
      .doc(`${TRAINER_ID}_${ATHLETE_ID}`)
      .get(),
  );
});

test('un tercero no puede leer el plan nutricional del alumno', async () => {
  await seedNutritionPlan();
  const stranger = testEnv.authenticatedContext('stranger');

  await assertFails(
    stranger
      .firestore()
      .collection('nutrition_plans')
      .doc(`${TRAINER_ID}_${ATHLETE_ID}`)
      .get(),
  );
});

test('el alumno lista archivos con athleteId y sharedWithAthlete', async () => {
  await seedAthleteFile('shared-file', { sharedWithAthlete: true });
  await seedAthleteFile('private-file', { sharedWithAthlete: false });
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  const snapshot = await assertSucceeds(
    athlete
      .firestore()
      .collection('athlete_files')
      .where('athleteId', '==', ATHLETE_ID)
      .where('sharedWithAthlete', '==', true)
      .orderBy('uploadedAt', 'desc')
      .get(),
  );

  expect(snapshot.docs.map((doc) => doc.id)).toEqual(['shared-file']);
});

test('el alumno no puede listar archivos filtrando solamente por athleteId', async () => {
  await seedAthleteFile('shared-file', { sharedWithAthlete: true });
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  await assertFails(
    athlete
      .firestore()
      .collection('athlete_files')
      .where('athleteId', '==', ATHLETE_ID)
      .get(),
  );
});

test('el alumno no puede leer un archivo que no fue compartido', async () => {
  await seedAthleteFile('private-file', { sharedWithAthlete: false });
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  await assertFails(
    athlete.firestore().collection('athlete_files').doc('private-file').get(),
  );
});

test('el alumno no puede leer un archivo viejo sin sharedWithAthlete', async () => {
  await seedAthleteFile('legacy-file');
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  await assertFails(
    athlete.firestore().collection('athlete_files').doc('legacy-file').get(),
  );
});

test('el PF puede cambiar sharedWithAthlete en un archivo propio', async () => {
  await seedAthleteFile('toggle-file', { sharedWithAthlete: false });
  const trainer = testEnv.authenticatedContext(TRAINER_ID);

  await assertSucceeds(
    trainer
      .firestore()
      .collection('athlete_files')
      .doc('toggle-file')
      .update({ sharedWithAthlete: true }),
  );
});

test('el PF no puede cambiar downloadUrl junto con sharedWithAthlete', async () => {
  await seedAthleteFile('tampered-file', { sharedWithAthlete: false });
  const trainer = testEnv.authenticatedContext(TRAINER_ID);

  await assertFails(
    trainer
      .firestore()
      .collection('athlete_files')
      .doc('tampered-file')
      .update({
        sharedWithAthlete: true,
        downloadUrl: 'https://attacker.test/file',
      }),
  );
});

test('el alumno no puede cambiar sharedWithAthlete', async () => {
  await seedAthleteFile('athlete-toggle-file', { sharedWithAthlete: false });
  const athlete = testEnv.authenticatedContext(ATHLETE_ID);

  await assertFails(
    athlete
      .firestore()
      .collection('athlete_files')
      .doc('athlete-toggle-file')
      .update({ sharedWithAthlete: true }),
  );
});
