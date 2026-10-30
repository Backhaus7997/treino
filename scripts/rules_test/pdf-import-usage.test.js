/**
 * `pdfImportUsage/{uid}` (cupo de imports de PDF, `parsePlanPdf`) contra
 * firestore.rules.
 *
 * El contrato:
 *   • LEER (`get`): solo el dueño, con sesión.
 *   • LISTAR: nadie — mostraría quién importa y cuánto.
 *   • ESCRIBIR: nadie desde un cliente, ni el dueño. Solo la Cloud Function
 *     con el Admin SDK, que se saltea las reglas. Si el PF pudiera escribir,
 *     se resetearía el contador y el cupo sería decorativo.
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

const USO = {
  weekKey: '2026-10-19',
  weekCount: 1,
  dayKey: '2026-10-22',
  dayCount: 1,
};

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('users/trainer1').set({ role: 'trainer' });
    await db.doc('users/trainer2').set({ role: 'trainer' });
    await db.doc('users/athlete1').set({ role: 'athlete' });
    await db.doc('pdfImportUsage/trainer1').set(USO);
    await db.doc('pdfImportUsage/trainer2').set(USO);
  });
});

const sinSesion = () => testEnv.unauthenticatedContext().firestore();
const pf1 = () => testEnv.authenticatedContext('trainer1').firestore();
const pf2 = () => testEnv.authenticatedContext('trainer2').firestore();
const atleta = () => testEnv.authenticatedContext('athlete1').firestore();

describe('pdfImportUsage/{uid}: lectura', () => {
  test('el dueño lee su propio cupo', async () => {
    await assertSucceeds(pf1().doc('pdfImportUsage/trainer1').get());
  });

  test('el dueño puede leer su doc aunque todavía no exista', async () => {
    await testEnv.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('pdfImportUsage/trainer1').delete(),
    );
    await assertSucceeds(pf1().doc('pdfImportUsage/trainer1').get());
  });

  test('otro PF NO lee el cupo ajeno', async () => {
    await assertFails(pf2().doc('pdfImportUsage/trainer1').get());
  });

  test('un atleta NO lee el cupo de un PF', async () => {
    await assertFails(atleta().doc('pdfImportUsage/trainer1').get());
  });

  test('sin sesión NO se lee', async () => {
    await assertFails(sinSesion().doc('pdfImportUsage/trainer1').get());
  });

  test('listar la colección se deniega, también al dueño', async () => {
    await assertFails(pf1().collection('pdfImportUsage').get());
  });
});

describe('pdfImportUsage/{uid}: escritura (solo Admin SDK)', () => {
  test('el dueño NO puede resetear su contador', async () => {
    await assertFails(
      pf1().doc('pdfImportUsage/trainer1').set({ ...USO, weekCount: 0, dayCount: 0 }),
    );
  });

  test('el dueño NO puede actualizar un campo', async () => {
    await assertFails(
      pf1().doc('pdfImportUsage/trainer1').update({ weekCount: 0 }),
    );
  });

  test('el dueño NO puede borrar su doc', async () => {
    await assertFails(pf1().doc('pdfImportUsage/trainer1').delete());
  });

  test('el dueño NO puede crearlo si no existe', async () => {
    await testEnv.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('pdfImportUsage/trainer1').delete(),
    );
    await assertFails(pf1().doc('pdfImportUsage/trainer1').set(USO));
  });

  test('otro PF NO escribe el cupo ajeno', async () => {
    await assertFails(
      pf2().doc('pdfImportUsage/trainer1').set({ ...USO, weekCount: 99 }),
    );
  });

  test('sin sesión NO se escribe', async () => {
    await assertFails(sinSesion().doc('pdfImportUsage/trainer1').set(USO));
  });
});
