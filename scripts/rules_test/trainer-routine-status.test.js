/**
 * UPDATE path 6 de `/routines`: el PF archiva y recupera rutinas suyas.
 *
 * Existe por un botón que nunca funcionó. `RoutineRepository.archive()` es de
 * 2026-07-17 y el ⋮ ofrece «Archivar» en las dos pantallas de rutinas del Hub
 * (`athlete_routines_screen.dart`, `routine_card_grid.dart`), pero `status` no
 * estaba en el `affectedKeys().hasOnly([...])` de ningún path del PF —los 3 y 4
 * son de CONTENIDO— así que los cinco denegaban. `archive()` atrapa el
 * `permission-denied` y devuelve `false`: el PF veía «No se pudo. Probá de
 * nuevo.» cada vez, sin forma de aprender por qué. Dos meses así.
 *
 * Nada de esto lo detectaba Dart: el repo compila igual y los widget tests
 * mockean el repositorio. Sólo lo ve un test contra el emulador, que es este.
 *
 * Los negativos NO son decorativos. Un path que flipea `status` sobre un
 * documento que un alumno entrena tiene que probar que no se le puede colgar
 * nada más encima — si sólo se testeara el camino feliz, el verde no diría que
 * la regla es ANGOSTA, únicamente que existe.
 */
const { readFileSync } = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const PF = 'trainer-status-x';
const OTRO_PF = 'trainer-status-z';
const ALUMNO = 'athlete-status-y';

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

afterAll(async () => { await testEnv.cleanup(); });
afterEach(async () => { await testEnv.clearFirestore(); });

const base = {
  name: 'Fuerza 4x',
  split: 'Upper/Lower',
  level: 'intermediate',
  days: [],
  numWeeks: 4,
  status: 'active',
  createdAt: new Date(),
};

const asignada = (extra = {}) => ({
  ...base,
  source: 'trainer-assigned',
  assignedBy: PF,
  assignedTo: ALUMNO,
  visibility: 'private',
  ...extra,
});

const plantilla = (extra = {}) => ({
  ...base,
  source: 'trainer-template',
  assignedBy: PF,
  assignedTo: null,
  visibility: 'private',
  ...extra,
});

const sembrar = async (id, doc) => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc(id).set(doc);
  });
};

const como = (uid, id) =>
  testEnv.authenticatedContext(uid).firestore().collection('routines').doc(id);

// --- positivos ---------------------------------------------------------------

test('el PF archiva un plan asignado suyo', async () => {
  await sembrar('r-01', asignada());
  await assertSucceeds(como(PF, 'r-01').update({ status: 'archived' }));
});

test('el PF archiva una plantilla suya', async () => {
  await sembrar('r-02', plantilla());
  await assertSucceeds(como(PF, 'r-02').update({ status: 'archived' }));
});

// El camino de vuelta. Sin esto, «archivar» sería un borrado con otro nombre y
// el diálogo que promete «la podés recuperar» estaría mintiendo.
test('el PF recupera un plan asignado archivado', async () => {
  await sembrar('r-03', asignada({ status: 'archived' }));
  await assertSucceeds(como(PF, 'r-03').update({ status: 'active' }));
});

test('el PF recupera una plantilla archivada', async () => {
  await sembrar('r-04', plantilla({ status: 'archived' }));
  await assertSucceeds(como(PF, 'r-04').update({ status: 'active' }));
});

// --- negativos: de quién es -------------------------------------------------

test('otro PF no puede archivar una rutina ajena', async () => {
  await sembrar('r-10', asignada());
  await assertFails(como(OTRO_PF, 'r-10').update({ status: 'archived' }));
});

// El alumno LEE su plan y lo entrena; no decide si sigue vigente. Si pudiera,
// se sacaría de encima el plan que el PF le puso y el PF no se enteraría.
test('el alumno asignado no puede archivar su plan', async () => {
  await sembrar('r-11', asignada());
  await assertFails(como(ALUMNO, 'r-11').update({ status: 'archived' }));
});

// --- negativos: qué se puede colgar del flip --------------------------------

test('no se puede editar contenido junto con el status', async () => {
  await sembrar('r-20', plantilla());
  await assertFails(
    como(PF, 'r-20').update({ status: 'archived', name: 'Otro nombre' }),
  );
});

// El que más importa: §3.2 del diseño de biblioteca. Convertir un plan asignado
// en plantilla dejaría las `Session.routineId` del alumno colgando de un
// documento que pasó a ser del PF. El path 6 no puede ser la puerta de atrás.
test('no se puede mover un plan asignado a plantilla junto con el status', async () => {
  await sembrar('r-21', asignada());
  await assertFails(
    como(PF, 'r-21').update({
      status: 'archived',
      source: 'trainer-template',
      assignedTo: null,
    }),
  );
});

test('no se puede publicar junto con el status', async () => {
  await sembrar('r-22', plantilla());
  await assertFails(
    como(PF, 'r-22').update({ status: 'archived', visibility: 'public' }),
  );
});

test('un status fuera de active/archived se deniega', async () => {
  await sembrar('r-23', plantilla());
  await assertFails(como(PF, 'r-23').update({ status: 'deleted' }));
});

// --- control: los paths viejos siguen vivos ---------------------------------
//
// El path 6 se insertó ENTRE el 5 y el DELETE. Si al agregarlo se hubiera roto
// la llave de algún bloque anterior, los positivos de arriba podrían pasar por
// la razón equivocada. Estos dos fijan que 4 y 5 siguen haciendo lo suyo.

test('control: el PF sigue pudiendo editar el nombre de su plantilla', async () => {
  await sembrar('r-30', plantilla());
  await assertSucceeds(como(PF, 'r-30').update({ name: 'Fuerza 5x' }));
});

test('control: el PF sigue sin poder cambiar assignedTo por el path de contenido', async () => {
  await sembrar('r-31', asignada());
  await assertFails(como(PF, 'r-31').update({ name: 'X', assignedTo: null }));
});
