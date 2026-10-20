'use strict';

/**
 * El gate de 24 h de cancelación del alumno, en horas REALES de Argentina.
 *
 * `startsAt` es wall-clock etiquetado UTC (ADR-7): una sesión a las 10:00 de
 * Buenos Aires se guarda como 10:00Z, pero ocurre a las 13:00Z. El gate del
 * Path 1 restaba 24 h a ese valor contra `request.time` (instante real), así
 * que el alumno tenía que cancelar 27 h antes, no 24. Ahora resta 21 h: en ART
 * son exactamente 24 h reales, que es lo que mide el cliente en wall-clock.
 *
 * Los turnos se siembran COMO LOS GUARDA LA APP: el instante real menos 3 h.
 * Sembrarlos con el instante real (como hacen otros casos de la suite) mide
 * otra cosa y escondía el desfase.
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const H = 3600000;
const MIN = 60000;
/** ART = UTC−3, sin horario de verano desde 2009. */
const ART = 3 * H;

const ATHLETE = 'gate-art-athlete';
const TRAINER = 'gate-art-trainer';

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
});

afterAll(async () => {
  await testEnv.cleanup();
});

/** Instante real de cada turno, medido desde "ahora". */
const TURNOS = {
  'gate-art-2359': 23 * H + 59 * MIN,
  'gate-art-2401': 24 * H + 1 * MIN,
  'gate-art-25h': 25 * H,
  'gate-art-1h': 1 * H,
};

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, faltan] of Object.entries(TURNOS)) {
      await db.collection('appointments').doc(id).set({
        id,
        trainerId: TRAINER,
        athleteId: ATHLETE,
        athleteDisplayName: 'Alumno',
        // Como lo guarda la app: la hora de reloj ART etiquetada UTC.
        startsAt: new Date(Date.now() + faltan - ART),
        durationMin: 60,
        status: 'confirmed',
        cancelledAt: null,
        cancelledBy: null,
        cancellationLog: [],
        noteBefore: null,
        noteAfter: null,
        recurringId: null,
        paymentId: null,
      });
    }
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function cancelarComo(uid, id) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection('appointments')
    .doc(id)
    .update({ status: 'cancelled', cancelledBy: uid });
}

test('el alumno NO cancela a 23 h 59 min reales de la sesión', async () => {
  await assertFails(cancelarComo(ATHLETE, 'gate-art-2359'));
});

test('el alumno cancela a 24 h 01 min reales — el borde son 24 h, no 27', async () => {
  await assertSucceeds(cancelarComo(ATHLETE, 'gate-art-2401'));
});

test('el alumno cancela a 25 h reales — con el gate viejo (−24 h) daba DENY', async () => {
  await assertSucceeds(cancelarComo(ATHLETE, 'gate-art-25h'));
});

test('el PF sigue sin gate: cancela a 1 h (#1492)', async () => {
  await assertSucceeds(cancelarComo(TRAINER, 'gate-art-1h'));
});
