/**
 * `app_config/min_version` (gate de versión mínima, `features/app_update`)
 * contra firestore.rules.
 *
 * El contrato:
 *   • LEER: cualquiera, también SIN sesión. El gate corre al arrancar, antes
 *     del login.
 *   • ESCRIBIR: nadie desde un cliente (ni anónimo, ni atleta, ni PF). Solo el
 *     Admin SDK / la consola, que se saltean las reglas.
 *   • Es EXACTAMENTE ese documento: listar `app_config` y leer otros
 *     documentos de la colección (p. ej. uno inventado) siguen denegados.
 *     `email_gate` conserva su regla (pide sesión).
 */
const { readFileSync } = require('fs');
const path = require('path');

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

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
}, 30000);

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('app_config/min_version').set({
      minVersion: { ios: '1.4.0', android: '1.4.0' },
    });
    await db.doc('app_config/email_gate').set({ enabled: false });
    await db.doc('app_config/otro').set({ x: 1 });
    await db.doc('users/athlete1').set({ role: 'athlete' });
    await db.doc('users/trainer1').set({ role: 'trainer' });
  });
});

const sinSesion = () => testEnv.unauthenticatedContext().firestore();
const atleta = () => testEnv.authenticatedContext('athlete1').firestore();
const pf = () => testEnv.authenticatedContext('trainer1').firestore();

describe('app_config/min_version', () => {
  test('lo lee un cliente SIN sesión', async () => {
    await assertSucceeds(sinSesion().doc('app_config/min_version').get());
  });

  test('lo lee un atleta con sesión', async () => {
    await assertSucceeds(atleta().doc('app_config/min_version').get());
  });

  test('lo lee un PF con sesión', async () => {
    await assertSucceeds(pf().doc('app_config/min_version').get());
  });

  test('leer un doc inexistente de esa ruta exacta también se permite (get)', async () => {
    await testEnv.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('app_config/min_version').delete(),
    );
    await assertSucceeds(sinSesion().doc('app_config/min_version').get());
  });

  test.each([
    ['sin sesión', sinSesion],
    ['atleta', atleta],
    ['PF', pf],
  ])('NO lo puede crear/pisar (%s)', async (_n, ctx) => {
    await assertFails(
      ctx().doc('app_config/min_version').set({
        minVersion: { ios: '0.0.1', android: '0.0.1' },
      }),
    );
  });

  test.each([
    ['sin sesión', sinSesion],
    ['atleta', atleta],
    ['PF', pf],
  ])('NO lo puede actualizar (%s)', async (_n, ctx) => {
    await assertFails(
      ctx().doc('app_config/min_version').update({ 'minVersion.ios': '9.9.9' }),
    );
  });

  test.each([
    ['sin sesión', sinSesion],
    ['atleta', atleta],
    ['PF', pf],
  ])('NO lo puede borrar (%s)', async (_n, ctx) => {
    await assertFails(ctx().doc('app_config/min_version').delete());
  });
});

describe('app_config: el resto sigue cerrado', () => {
  test('listar la colección sigue denegado (sin sesión y con sesión)', async () => {
    await assertFails(sinSesion().collection('app_config').get());
    await assertFails(atleta().collection('app_config').get());
  });

  test('otro documento de app_config sigue denegado', async () => {
    await assertFails(atleta().doc('app_config/otro').get());
    await assertFails(sinSesion().doc('app_config/otro').get());
  });

  test('email_gate conserva su regla: sin sesión NO, con sesión SÍ', async () => {
    await assertFails(sinSesion().doc('app_config/email_gate').get());
    await assertSucceeds(atleta().doc('app_config/email_gate').get());
  });
});
