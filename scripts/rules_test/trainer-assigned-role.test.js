'use strict';

/**
 * Firestore Security Rules — CREATE branch 1 de `/routines` (plan asignado).
 *
 * La rama del ATLETA de este mismo create (branch 2, ~945) valida seis cosas:
 * tipos, `hasOnly`, `createdAt is timestamp` y el tope del paywall. La rama del
 * ENTRENADOR validaba tres: el `source`, la `visibility`, y que `assignedTo`
 * fuera un string no vacío. Nada más. Ni rol, ni forma, ni tipos.
 *
 * O sea que cualquier cuenta podía escribir un plan diciendo que lo asignó un
 * entrenador, y eso compraba tres cosas distintas:
 *
 *   1. CONTENIDO FALSO EN LA APP DE OTRO. El doc aparece en la lista del
 *      `assignedTo` con el chip «DE TU COACH» (`unified_routines_providers`
 *      marca `fromCoach: true` para todo lo que viene de `listAssignedTo`), y
 *      si la víctima no tiene rutina activa la app lo ADOPTA como activa. La
 *      víctima no puede sacarlo: el delete es sólo del `assignedBy` (~1300).
 *   2. ROMPERLE LA PANTALLA. Sin validación de tipos, un doc al que le falta
 *      `days` o trae `level` mal tipado hace que `Routine.fromJson` tire, y ese
 *      parseo no tiene try/catch por documento: se cae la lista entera de
 *      Rutinas de la víctima, que tampoco puede borrar el doc que la rompe.
 *   3. SALTEAR EL TOPE DEL PLAN GRATIS. El tope de forma
 *      (`withinFreeRoutineShape`, 3 días y 1 semana) vive SÓLO en la rama del
 *      atleta. Un alumno free que se autoasigna un plan —`assignedBy` ==
 *      `assignedTo` == su uid— entrena 7 días y 12 semanas, y la sesión lo
 *      deja pasar porque sólo mira `isPremium` de la rutina (~2880).
 *
 * ALCANCE — rol, NO rol + vínculo. Es la misma decisión AD-1 de
 * `rules-hardening` Slice C ("ROLE-CHECK ONLY"), que dejó explícitamente como
 * residuo aceptado el caso "un PF real sin vínculo escribe sobre un alumno que
 * no es suyo": es atribuible, porque el uid del que escribe queda en el doc. Y
 * acá sigue sin poder hacerse mejor: `trainer_links` tiene ids autogenerados,
 * así que una regla no puede preguntar "¿hay vínculo entre A y B?".
 *
 * Lo que el rol SÍ cierra entero es el punto 3 —un atleta deja de poder ser
 * `assignedBy`— y reduce los puntos 1 y 2 a ese residuo.
 *
 * Run via: bash scripts/test_rules.sh  (trae su propio emulador; Java 21+)
 */

const { readFileSync } = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const PF = 'trainer-assign-role';
const ALUMNO = 'athlete-assign-role';
const VICTIMA = 'athlete-assign-victim';

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

async function sembrarRol(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({ uid, role });
  });
}

/**
 * Payload por lo demás VÁLIDO de un plan asignado, modelado sobre el
 * `asignada()` de trainer-routine-status.test.js.
 *
 * Que sea completo importa: un `assertFails` que pasa por el motivo equivocado
 * —denegado por la forma en vez de por el rol que dice custodiar— no avisa
 * nunca. Es la lección de SCENARIO-CC-05 en coach-collections-role.test.js.
 */
const asignada = (extra = {}) => ({
  name: 'Fuerza 4x',
  split: 'Upper/Lower',
  level: 'intermediate',
  days: [],
  numWeeks: 4,
  status: 'active',
  createdAt: new Date(),
  source: 'trainer-assigned',
  assignedBy: PF,
  assignedTo: ALUMNO,
  visibility: 'private',
  ...extra,
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-01: el salto del tope. Un alumno free se autoasigna un plan que
// excede la forma gratis (7 días, 12 semanas) diciendo que se lo asignó un
// entrenador — él mismo. [REQ:trainer-assigned-role-gate#create exige rol]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-01: un alumno no puede autoasignarse un plan fuera del tope free', async () => {
  await sembrarRol(ALUMNO, 'athlete');

  const alumno = testEnv.authenticatedContext(ALUMNO);
  await assertFails(
    alumno.firestore().collection('routines').doc('ta-self').set(
      asignada({
        assignedBy: ALUMNO,
        assignedTo: ALUMNO,
        days: [{}, {}, {}, {}, {}, {}, {}],
        numWeeks: 12,
      }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-02: el contenido falso. Un alumno le planta a OTRO un plan que
// la app de la víctima muestra con el chip «DE TU COACH», y que la víctima no
// puede borrar. [REQ:trainer-assigned-role-gate#create exige rol]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-02: un alumno no puede plantarle un «plan de tu coach» a otro', async () => {
  await sembrarRol(ALUMNO, 'athlete');
  await sembrarRol(VICTIMA, 'athlete');

  const atacante = testEnv.authenticatedContext(ALUMNO);
  await assertFails(
    atacante.firestore().collection('routines').doc('ta-plant').set(
      asignada({ assignedBy: ALUMNO, assignedTo: VICTIMA }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-03: ancla del camino legítimo. Un PF real asigna un plan. Tiene
// que seguir verde: un gate que deniega todo pasaría los dos tests de arriba
// sin proteger nada. [REQ:trainer-assigned-role-gate#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-03: un PF real SÍ puede asignarle un plan a un alumno', async () => {
  await sembrarRol(PF, 'trainer');
  await sembrarRol(ALUMNO, 'athlete');

  const pf = testEnv.authenticatedContext(PF);
  await assertSucceeds(
    pf.firestore().collection('routines').doc('ta-legit').set(asignada()),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-03b: el ancla que de verdad protege producción. El payload EXACTO
// que manda `RoutineRepository.createAssigned`: `routine.toJson()` sin `id`,
// más `createdAt`. Son las 17 claves que emite el `toJson` generado, y entre
// ellas va `copiedFrom` —con null cuando el plan no se copió de ninguna rutina,
// porque json_serializable la emite SIEMPRE.
//
// Si el `hasOnly` del create se escribiera copiando la lista de los UPDATE 3 y
// 4, `copiedFrom` quedaría afuera y TODA asignación real moriría con
// permission-denied. Los otros tests de este archivo no lo verían: ninguno
// manda el payload completo. Éste sí. [REQ:trainer-assigned-role-gate#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-03b: el payload REAL de createAssigned (17 claves, con copiedFrom) pasa', async () => {
  await sembrarRol(PF, 'trainer');

  const pf = testEnv.authenticatedContext(PF);
  await assertSucceeds(
    pf.firestore().collection('routines').doc('ta-real').set({
      name: 'Fuerza 4x',
      split: 'Upper/Lower',
      level: 'intermediate',
      days: [],
      estimatedMinutesPerDay: 60,
      imageUrl: null,
      source: 'trainer-assigned',
      assignedBy: PF,
      assignedTo: ALUMNO,
      visibility: 'private',
      createdBy: PF,
      status: 'active',
      numWeeks: 4,
      copiedFrom: null,
      summary: 'Un plan de fuerza de cuatro semanas.',
      goals: [],
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-04: la forma. Un campo fuera del set conocido se rechaza, igual
// que en la rama del atleta (`hasOnly`). El PF está sembrado a propósito: lo
// que se prueba acá es la FORMA, no el rol.
// [REQ:trainer-assigned-role-gate#create valida forma]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-04: un campo desconocido se rechaza aunque lo escriba un PF', async () => {
  await sembrarRol(PF, 'trainer');

  const pf = testEnv.authenticatedContext(PF);
  await assertFails(
    pf.firestore().collection('routines').doc('ta-extra').set(
      asignada({ campoInventado: 'x' }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TA-05: los tipos. Un `createdAt` que no es timestamp se rechaza. Es
// la mitad del punto 2 que una regla SÍ puede cubrir: el doc deja de poder
// nacer con una forma que el cliente no sabe parsear.
// [REQ:trainer-assigned-role-gate#create valida forma]
// ---------------------------------------------------------------------------
test('SCENARIO-TA-05: un createdAt que no es timestamp se rechaza', async () => {
  await sembrarRol(PF, 'trainer');

  const pf = testEnv.authenticatedContext(PF);
  await assertFails(
    pf.firestore().collection('routines').doc('ta-badstamp').set(
      asignada({ createdAt: '2026-01-01' }),
    ),
  );
});
