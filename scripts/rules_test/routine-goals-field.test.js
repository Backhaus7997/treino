/**
 * `Routine.goals` (#635 PR#1) contra firestore.rules.
 *
 * Existe por el modo de falla de #563: los paths de `routines` tienen guardas
 * `keys().hasOnly([...])` con COUPLING WARNING, y `goals` sale en el `toJson()`
 * de TODA rutina desde este PR. Si una sola de las cinco listas se hubiera
 * quedado sin el campo, esa rama entera de edición falla con permission-denied
 * — en silencio, y sólo en producción, porque nada en Dart lo detecta.
 *
 * El reparto que se testea es ASIMÉTRICO a propósito:
 *   • PF (paths 3 y 4): puede escribir `goals` Y editarlo.
 *   • Atleta (create + path 2): puede CONVIVIR con el campo, no cambiarlo.
 *     El objetivo es una afirmación editorial de quien publica la plantilla,
 *     no una preferencia de quien la usa.
 */
const { readFileSync } = require('fs');
const path = require('path');

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

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
  // Explícito: el default de jest (5s) no alcanza para la primera conexión
  // contra un emulador recién levantado.
}, 30000);

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

const athleteOwned = (uid, extra = {}) => ({
  source: 'user-created',
  createdBy: uid,
  visibility: 'private',
  name: 'Mi rutina',
  split: 'Full Body',
  level: 'beginner',
  days: [],
  status: 'active',
  createdAt: new Date(),
  ...extra,
});

const trainerTemplate = (uid, extra = {}) => ({
  source: 'trainer-template',
  assignedBy: uid,
  // PRESENTE y null, no ausente. Las reglas comparan `assignedTo == null`, y
  // sobre un campo que no existe eso es un error de evaluación, no `false`.
  // El cliente real siempre lo emite: json_serializable escribe el null
  // literal. Un fixture que lo omitiera probaría un documento que la app
  // nunca manda.
  assignedTo: null,
  visibility: 'private',
  name: 'Plantilla',
  split: 'PPL',
  level: 'intermediate',
  days: [],
  status: 'active',
  createdAt: new Date(),
  ...extra,
});

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
  ...extra,
});

const seed = (docId, data) =>
  testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('routines').doc(docId).set(data),
  );

// ── El atleta: convive con el campo, no lo cambia ──────────────────────────

test('el atleta puede CREAR una rutina que lleva goals', async () => {
  // Sin `goals` en userCreatedRoutineFields(), esto falla — y con él falla
  // TODA creación de rutina propia, porque el cliente siempre lo emite.
  const athlete = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athlete
      .firestore()
      .collection('routines')
      .doc('r-goals-create')
      .set(athleteOwned('athlete-a', { goals: ['health', 'aesthetics'] })),
  );
});

test('el atleta puede EDITAR el contenido de una rutina que ya tiene goals', async () => {
  // El caso que rompía #563: el doc lleva el campo nuevo, el diff no lo toca,
  // y aun así el `keys().hasOnly` lo rechaza si no lo conoce.
  await seed('r-goals-edit', athleteOwned('athlete-a', { goals: ['sport'] }));

  const athlete = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athlete
      .firestore()
      .collection('routines')
      .doc('r-goals-edit')
      .update({ name: 'Renombrada' }),
  );
});

test('el atleta NO puede cambiar goals', async () => {
  await seed('r-goals-athlete', athleteOwned('athlete-a', { goals: ['sport'] }));

  const athlete = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athlete
      .firestore()
      .collection('routines')
      .doc('r-goals-athlete')
      .update({ goals: ['aesthetics'] }),
  );
});

// ── El PF: lo declara y lo edita ───────────────────────────────────────────

test('el PF puede CREAR una plantilla con goals', async () => {
  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    trainer
      .firestore()
      .collection('routines')
      .doc('t-goals-create')
      .set(trainerTemplate('trainer-a', { goals: ['injury_prevention'] })),
  );
});

test('el PF puede EDITAR los goals de su plantilla', async () => {
  await seed(
    't-goals-edit',
    trainerTemplate('trainer-a', { goals: ['health'] }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    trainer
      .firestore()
      .collection('routines')
      .doc('t-goals-edit')
      .update({ goals: ['health', 'wellbeing'] }),
  );
});

test('el PF puede editar el contenido de una plantilla que ya tiene goals', async () => {
  await seed(
    't-goals-content',
    trainerTemplate('trainer-a', { goals: ['health'] }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    trainer
      .firestore()
      .collection('routines')
      .doc('t-goals-content')
      .update({ name: 'Renombrada' }),
  );
});

test('un PF ajeno no puede tocar los goals de una plantilla que no es suya', async () => {
  await seed(
    't-goals-foreign',
    trainerTemplate('trainer-a', { goals: ['health'] }),
  );

  const other = testEnv.authenticatedContext('trainer-b');
  await assertFails(
    other
      .firestore()
      .collection('routines')
      .doc('t-goals-foreign')
      .update({ goals: ['sport'] }),
  );
});

// ── El plan ASIGNADO: arrastra el campo, no lo edita ───────────────────────

test('el PF puede editar el contenido de un plan asignado que arrastra goals', async () => {
  // Un plan copiado desde una plantilla puede traer el campo. Si `keys()` no
  // lo conociera, editar ese plan fallaría con permission-denied.
  await seed(
    'a-goals-content',
    trainerAssigned('trainer-a', 'athlete-a', { goals: ['sport'] }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertSucceeds(
    trainer
      .firestore()
      .collection('routines')
      .doc('a-goals-content')
      .update({ name: 'Renombrado' }),
  );
});

test('el PF NO puede cambiar los goals de un plan asignado', async () => {
  // Deliberado: un plan asignado es privado de un alumno y no aparece en la
  // grilla de PLANTILLAS, así que nada lo rankea por objetivo. `updateAssigned`
  // tampoco lo manda. El permiso de escritura vive sólo en el path de
  // PLANTILLA, que es la superficie que el catálogo realmente lee.
  await seed(
    'a-goals-edit',
    trainerAssigned('trainer-a', 'athlete-a', { goals: ['sport'] }),
  );

  const trainer = testEnv.authenticatedContext('trainer-a');
  await assertFails(
    trainer
      .firestore()
      .collection('routines')
      .doc('a-goals-edit')
      .update({ goals: ['health'] }),
  );
});
