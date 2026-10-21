'use strict';

/**
 * `userPublicProfiles.hiddenFromDiscovery` es un flag de ADMIN: saca a una
 * cuenta interna (soporte, QA, revisores de las tiendas) de la búsqueda de
 * personas, las sugerencias y los rankings. Lo escribe sólo
 * `scripts/set_trainer_discovery_visibility.js` con el Admin SDK.
 *
 * Fija dos cosas:
 *   - el dueño NO puede ocultarse, mostrarse ni cambiar el flag;
 *   - una cuenta YA oculta puede seguir actualizando su perfil. El campo
 *     tiene que estar en el `hasOnly` del update: si no, el doc entero queda
 *     fuera de la allowlist y toda escritura de la app sale permission-denied.
 */

const { initializeTestEnvironment, assertSucceeds, assertFails } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const UID = 'soporte';

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

async function seedPerfil(extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('userPublicProfiles').doc(UID).set({
      uid: UID,
      displayName: 'treinoSupport',
      displayNameLowercase: 'treinosupport',
      ...extra,
    });
  });
}

const perfil = () =>
  testEnv.authenticatedContext(UID).firestore().collection('userPublicProfiles').doc(UID);

describe('create', () => {
  test('HIDDEN-01: el dueño no puede crearse oculto', async () => {
    await assertFails(perfil().set({ uid: UID, displayName: 'x', hiddenFromDiscovery: true }));
  });

  test('HIDDEN-02: crear sin el campo se permite', async () => {
    await assertSucceeds(perfil().set({ uid: UID, displayName: 'x' }));
  });

  test('HIDDEN-03: crear con false se permite', async () => {
    await assertSucceeds(perfil().set({ uid: UID, displayName: 'x', hiddenFromDiscovery: false }));
  });
});

describe('update', () => {
  test('HIDDEN-04: un perfil visible no puede ocultarse solo', async () => {
    await seedPerfil();
    await assertFails(perfil().set({ hiddenFromDiscovery: true }, { merge: true }));
  });

  test('HIDDEN-05: una cuenta oculta no puede mostrarse sola', async () => {
    await seedPerfil({ hiddenFromDiscovery: true });
    await assertFails(perfil().set({ hiddenFromDiscovery: false }, { merge: true }));
  });

  test('HIDDEN-06: una cuenta oculta no puede borrarse el campo', async () => {
    await seedPerfil({ hiddenFromDiscovery: true });
    await assertFails(
      perfil().set({ uid: UID, displayName: 'treinoSupport' }),
    );
  });

  test('HIDDEN-07: una cuenta oculta sigue pudiendo editar su perfil', async () => {
    await seedPerfil({ hiddenFromDiscovery: true });
    await assertSucceeds(
      perfil().set({ displayName: 'Soporte', displayNameLowercase: 'soporte' }, { merge: true }),
    );
  });

  test('HIDDEN-08: re-presentar el valor guardado se permite', async () => {
    await seedPerfil({ hiddenFromDiscovery: true });
    await assertSucceeds(perfil().set({ hiddenFromDiscovery: true }, { merge: true }));
  });
});
