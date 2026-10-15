/**
 * `nutrition_plans`: el create ata el docId al par y exige rol de PF.
 *
 * El plan vive en `nutrition_plans/{trainerId}_{athleteId}` y la app del alumno
 * lee EXACTAMENTE ese docId (`NutritionPlanRepository._docId`) sin validar
 * `plan.trainerId`. El create validaba sólo que `trainerId == auth.uid`, no que
 * el docId fuera el del par. Con eso, cualquier cuenta podía:
 *
 *   1) Plantar un plan falso: crear `{PFdeLaVíctima}_{víctima}` con su propio
 *      `trainerId` y `athleteId = víctima`. La víctima lo veía como "el plan de
 *      tu PF" (la read gate deja leer a quien figura como `athleteId`).
 *   2) Squat: de paso, el PF real ya no podía crear ni editar ese plan — su
 *      write cae en el update, que exige `resource.data.trainerId == auth.uid`.
 *
 * Bastaba con conocer el uid del PF, que el discovery expone.
 *
 * El comentario de `athlete_notes` (QA-SEC-010) describía este ataque y decía
 * haberlo cerrado con el "mismo patrón que follow_up_entries / nutrition_plans".
 * `nutrition_plans` nunca lo tuvo. Este archivo existe para que esa afirmación
 * no dependa de que alguien la lea bien.
 */
const { readFileSync } = require('fs');
const path = require('path');

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

// Mismo projectId que los hermanos: el runner los serializa con
// `--runInBand` justamente para que compartirlo sea seguro.
const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const PF = 'pf-real';
const OTRO_PF = 'pf-ajeno';
const VICTIMA = 'atleta-victima';
const ATACANTE = 'atleta-atacante';
const PLAN_DEL_PAR = `${PF}_${VICTIMA}`;

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
  // Los roles reales: dos PF y dos atletas. Sin esto el gate de rol denegaría
  // todo y los tests del docId pasarían por el motivo equivocado.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const users = ctx.firestore().collection('users');
    await users.doc(PF).set({ uid: PF, role: 'trainer' });
    await users.doc(OTRO_PF).set({ uid: OTRO_PF, role: 'trainer' });
    await users.doc(VICTIMA).set({ uid: VICTIMA, role: 'athlete' });
    await users.doc(ATACANTE).set({ uid: ATACANTE, role: 'athlete' });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

const plan = (trainerId, athleteId, extra = {}) => ({
  id: `${trainerId}_${athleteId}`,
  trainerId,
  athleteId,
  title: 'Plan semanal',
  meals: [],
  updatedAt: new Date(),
  ...extra,
});

const planRef = (uid, docId) =>
  testEnv.authenticatedContext(uid).firestore().collection('nutrition_plans').doc(docId);

// ── El camino legítimo ─────────────────────────────────────────────────────

test('el PF crea el plan de su par en el docId del par', async () => {
  await assertSucceeds(planRef(PF, PLAN_DEL_PAR).set(plan(PF, VICTIMA)));
});

test('el PF vuelve a guardar su plan (el upsert de la app cae en el update)', async () => {
  await assertSucceeds(planRef(PF, PLAN_DEL_PAR).set(plan(PF, VICTIMA)));
  await assertSucceeds(
    planRef(PF, PLAN_DEL_PAR).set(plan(PF, VICTIMA, { title: 'Plan de definición' })),
  );
});

// ── El ataque: plantar un plan en el docId del par ajeno ───────────────────

test('un atleta NO puede plantar un plan en el docId del PF de la víctima', async () => {
  // El ataque exacto: docId del par real, trainerId propio (la única guarda
  // que había), athleteId de la víctima.
  await assertFails(
    planRef(ATACANTE, PLAN_DEL_PAR).set(plan(ATACANTE, VICTIMA, { id: PLAN_DEL_PAR })),
  );
});

test('otro PF NO puede ocupar el docId del par de un colega', async () => {
  // Tiene el rol, así que lo que lo frena es el docId, no el gate de rol.
  await assertFails(
    planRef(OTRO_PF, PLAN_DEL_PAR).set(plan(OTRO_PF, VICTIMA, { id: PLAN_DEL_PAR })),
  );
});

test('tras el intento, la víctima ve su estado vacío y el PF real puede crear el plan', async () => {
  await assertFails(
    planRef(ATACANTE, PLAN_DEL_PAR).set(plan(ATACANTE, VICTIMA, { id: PLAN_DEL_PAR })),
  );

  // La víctima lee el docId de su par: no existe, sin PERMISSION_DENIED.
  const snap = await assertSucceeds(planRef(VICTIMA, PLAN_DEL_PAR).get());
  expect(snap.exists).toBe(false);

  // Y el squat no ocurrió: el PF real crea su plan normalmente.
  await assertSucceeds(planRef(PF, PLAN_DEL_PAR).set(plan(PF, VICTIMA)));
});

// ── Forma del docId ────────────────────────────────────────────────────────

test('el PF NO puede crear un plan cuyo docId no corresponde al alumno del doc', async () => {
  // docId de un par, athleteId de otro: la app del alumno del docId leería un
  // plan que no es suyo.
  await assertFails(planRef(PF, PLAN_DEL_PAR).set(plan(PF, 'otro-atleta')));
});

// ── Gate de rol ────────────────────────────────────────────────────────────

test('un atleta NO puede crear planes nutricionales, ni en su propio prefijo', async () => {
  // El docId cuadra (`{atacante}_{víctima}`): lo que lo frena es el rol.
  await assertFails(
    planRef(ATACANTE, `${ATACANTE}_${VICTIMA}`).set(plan(ATACANTE, VICTIMA)),
  );
});
