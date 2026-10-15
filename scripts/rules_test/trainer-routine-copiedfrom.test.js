/**
 * `copiedFrom` en los planes y plantillas del PF contra firestore.rules.
 *
 * Regresión de #1365. Ese PR sumó `copiedFrom` a `trainerRoutineFields()` —la
 * lista del CREATE— porque `Routine.toJson()` lo emite SIEMPRE (null cuando la
 * rutina no se copió de ninguna). Pero los `keys().hasOnly([...])` de UPDATE 3
 * (plan asignado) y UPDATE 4 (plantilla) eran listas escritas a mano y no lo
 * tenían. `keys()` mira el POST-estado del doc, así que todo plan o plantilla
 * creado desde la app quedaba INEDITABLE: el guardado del editor daba
 * permission-denied, y el banner le echaba la culpa al cupo del plan.
 *
 * Mismo modo de falla que #563 y que `routine-goals-field.test.js`: nada en
 * Dart lo detecta, y los tests de reglas existentes no lo veían porque sus
 * fixtures no traen la clave. Acá los fixtures la traen PRESENTE y null, que
 * es lo que el cliente real escribe.
 *
 * Lo que se fija:
 *   • El PF puede editar el contenido de un doc que trae `copiedFrom` (null o
 *     con valor), en los dos paths.
 *   • `copiedFrom` sigue siendo inmutable: se sella al crear y ningún update
 *     lo cambia ni lo borra.
 */
const { readFileSync } = require('fs');
const path = require('path');

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const firebaseCompat = require('firebase/compat/app');
require('firebase/compat/firestore');

const { FieldValue } = firebaseCompat.firestore;

// Mismo projectId que los hermanos: el runner los serializa con
// `--runInBand` justamente para que compartirlo sea seguro.
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

afterEach(async () => {
  await testEnv.clearFirestore();
});

// `copiedFrom: null` PRESENTE, no ausente: es lo que escribe `toJson()`. Un
// fixture que lo omitiera probaría un documento que la app nunca manda — que
// es exactamente por qué la suite no vio la regresión.
const trainerAssigned = (uid, athleteUid, extra = {}) => ({
  source: 'trainer-assigned',
  assignedBy: uid,
  assignedTo: athleteUid,
  visibility: 'private',
  name: 'Plan',
  split: 'PPL',
  level: 'intermediate',
  days: [],
  status: 'active',
  createdAt: new Date(),
  copiedFrom: null,
  ...extra,
});

const trainerTemplate = (uid, extra = {}) => ({
  source: 'trainer-template',
  assignedBy: uid,
  assignedTo: null,
  visibility: 'private',
  name: 'Plantilla',
  split: 'PPL',
  level: 'intermediate',
  days: [],
  status: 'active',
  createdAt: new Date(),
  copiedFrom: null,
  ...extra,
});

const seed = (docId, data) =>
  testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('routines').doc(docId).set(data),
  );

const sembrarPF = (uid) =>
  testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('users').doc(uid).set({ uid, role: 'trainer' }),
  );

const routine = (ctx, docId) =>
  ctx.firestore().collection('routines').doc(docId);

// ── UPDATE 3: plan asignado ────────────────────────────────────────────────

test('el PF puede editar un plan asignado que trae copiedFrom: null', async () => {
  // El caso de la regresión: lo que crea `createAssigned` desde el Hub.
  await seed('a-cf-null', trainerAssigned('trainer-a', 'athlete-a'));

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    routine(trainer, 'a-cf-null').update({ name: 'Renombrado' }),
  );
});

test('el PF puede editar un plan asignado copiado de otra rutina', async () => {
  await seed(
    'a-cf-value',
    trainerAssigned('trainer-a', 'athlete-a', { copiedFrom: 'tpl-origen' }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    routine(trainer, 'a-cf-value').update({ name: 'Renombrado' }),
  );
});

test('el PF NO puede cambiar el copiedFrom de un plan asignado', async () => {
  await seed('a-cf-change', trainerAssigned('trainer-a', 'athlete-a'));

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertFails(
    routine(trainer, 'a-cf-change').update({ copiedFrom: 'tpl-inventado' }),
  );
});

// ── UPDATE 4: plantilla ────────────────────────────────────────────────────

test('el PF puede editar una plantilla que trae copiedFrom: null', async () => {
  // El caso de la regresión: lo que crea `createTemplate` desde el Hub.
  await seed('t-cf-null', trainerTemplate('trainer-a'));

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    routine(trainer, 't-cf-null').update({ name: 'Renombrada' }),
  );
});

test('el PF NO puede cambiar el copiedFrom de una plantilla', async () => {
  await seed('t-cf-change', trainerTemplate('trainer-a'));

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertFails(
    routine(trainer, 't-cf-change').update({ copiedFrom: 'tpl-inventado' }),
  );
});

test('el PF NO puede borrar el copiedFrom de una plantilla', async () => {
  await seed(
    't-cf-delete',
    trainerTemplate('trainer-a', { copiedFrom: 'tpl-origen' }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  // Sacar la clave también es un cambio: aparece en `affectedKeys()`.
  await assertFails(
    routine(trainer, 't-cf-delete').update({ copiedFrom: FieldValue.delete() }),
  );
});

// ── De punta a punta: lo que crea el cliente, el mismo cliente lo edita ────

test('una plantilla creada por el PF con copiedFrom: null se puede editar después', async () => {
  // Sin `withSecurityRulesDisabled`: el create pasa por las reglas igual que
  // desde la app, y el update que le sigue también. Es el ida y vuelta que
  // ningún test cubría — cada mitad pasaba sola.
  await sembrarPF('trainer-a');
  const trainer = testEnv.authenticatedContext('trainer-a');

  await assertSucceeds(
    routine(trainer, 't-cf-roundtrip').set(trainerTemplate('trainer-a')),
  );
  await assertSucceeds(
    routine(trainer, 't-cf-roundtrip').update({ name: 'Renombrada' }),
  );
});
