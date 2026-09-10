/**
 * §4.3: el PF publica el plan de un alumno COMO PLANTILLA.
 *
 * No se publica el documento del alumno —UPDATE path 5 exige
 * `trainer-template`, así que está denegado por contrato—. Se crea una
 * plantilla NUEVA a partir de él y se publica ESA.
 *
 * Por qué esto necesita un test de reglas y no le alcanza con los de widget:
 * la plantilla se arma con `plan.copyWith(...)`, así que **arrastra los campos
 * del plan** (`summary`, `goals`, `estimatedMinutesPerDay`, `numWeeks`…). Si el
 * CREATE de `trainer-template` no acepta alguno de ellos, la publicación falla
 * con `permission-denied` sólo en producción y sólo para los planes que tengan
 * ese campo cargado — el modo de falla de #563, que es justamente por lo que
 * los paths de `routines` llevan COUPLING WARNING.
 *
 * Los widget tests no lo ven: mockean el repositorio.
 */
const { readFileSync } = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const PF = 'trainer-pub-x';
const ALUMNO = 'athlete-pub-y';

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

/** El path 5 tiene gate de rol: sin este doc, publicar se deniega. */
const sembrarPF = async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(PF).set({ role: 'trainer' });
  });
};

/**
 * La plantilla tal cual la manda `createTemplate` desde un plan asignado
 * CARGADO: con todos los campos opcionales puestos, que es el caso que puede
 * romper y el que un fixture mínimo no probaría.
 */
const plantillaDesdeUnPlanCargado = () => ({
  name: 'Fuerza para principiantes',
  split: 'Upper/Lower',
  level: 'intermediate',
  days: [],
  numWeeks: 4,
  status: 'active',
  source: 'trainer-template',
  assignedBy: PF,
  assignedTo: null,
  visibility: 'private',
  createdAt: new Date(),
  // Los arrastrados del plan del alumno:
  summary: 'Un plan de fuerza de cuatro semanas para arrancar.',
  goals: ['strength'],
  estimatedMinutesPerDay: 55,
});

const como = (uid, id) =>
  testEnv.authenticatedContext(uid).firestore().collection('routines').doc(id);

test('el PF crea la plantilla con los campos que arrastra del plan', async () => {
  await assertSucceeds(
    como(PF, 'tpl-1').set(plantillaDesdeUnPlanCargado()),
  );
});

test('y después la publica', async () => {
  await sembrarPF();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('tpl-2')
      .set(plantillaDesdeUnPlanCargado());
  });

  await assertSucceeds(como(PF, 'tpl-2').update({ visibility: 'public' }));
});

// --- los negativos: que esto NO sea una puerta de atrás ---------------------

// La razón por la que el flujo existe. Si esto pasara, no haría falta crear
// nada — y la rutina del alumno, con su nombre y su historial, quedaría en el
// catálogo público.
test('el plan del alumno NO se puede publicar directamente', async () => {
  await sembrarPF();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('plan-1').set({
      ...plantillaDesdeUnPlanCargado(),
      source: 'trainer-assigned',
      assignedTo: ALUMNO,
    });
  });

  await assertFails(como(PF, 'plan-1').update({ visibility: 'public' }));
});

test('la plantilla no puede nacer pública de una', async () => {
  // `createTemplate` fuerza `private`, pero eso es el cliente. Un cliente
  // parcheado no lo respetaría, y saltearse el flip dejaría un documento
  // público sin haber pasado nunca por el path 5 ni por su gate de rol.
  await assertFails(
    como(PF, 'tpl-3').set({
      ...plantillaDesdeUnPlanCargado(),
      visibility: 'public',
    }),
  );
});

test('otro PF no puede publicar una plantilla ajena', async () => {
  await sembrarPF();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('tpl-4')
      .set(plantillaDesdeUnPlanCargado());
  });

  await assertFails(como('trainer-otro', 'tpl-4').update({ visibility: 'public' }));
});
