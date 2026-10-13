'use strict';

/**
 * Elegir "OTRO GYM / SIN GYM" en el perfil escribe en un solo WriteBatch
 * `users/{uid}` + `userPublicProfiles/{uid}` (UserRepository.update, merge).
 * Estos tests fijan que ese batch, tal cual lo arma la app, lo permiten las
 * reglas tanto con `null` (lo correcto) como con el sentinel legacy 'no-gym'.
 */

const { initializeTestEnvironment, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(RULES_PATH, 'utf8'), host: 'localhost', port: 8080 },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedAthleteConGym(gymId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc('u1').set({
      uid: 'u1',
      email: 'a@b.c',
      createdAt: new Date('2025-01-01'),
      updatedAt: new Date('2025-01-01'),
      role: 'athlete',
      displayName: 'Martin',
      gymId,
    });
    await ctx.firestore().collection('userPublicProfiles').doc('u1').set({
      uid: 'u1',
      displayName: 'Martin',
      displayNameLowercase: 'martin',
      gymId,
      gymName: 'Un gym',
    });
  });
}

async function guardarGym(gymId) {
  const db = testEnv.authenticatedContext('u1').firestore();
  const batch = db.batch();
  batch.set(
    db.collection('users').doc('u1'),
    { gymId, updatedAt: new Date() },
    { merge: true },
  );
  batch.set(
    db.collection('userPublicProfiles').doc('u1'),
    { gymId, gymName: null, uid: 'u1' },
    { merge: true },
  );
  return batch.commit();
}

test('GYM-SAVE-01: pasar de un gym real a "sin gym" (null) se permite', async () => {
  await seedAthleteConGym('ChIJreal');
  await assertSucceeds(guardarGym(null));
});

test('GYM-SAVE-02: el sentinel legacy "no-gym" también se permite', async () => {
  await seedAthleteConGym('ChIJreal');
  await assertSucceeds(guardarGym('no-gym'));
});
