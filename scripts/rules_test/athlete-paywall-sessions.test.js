/**
 * Paywall del alumno suelto — el eje del CATÁLOGO, del lado servidor.
 *
 * `docs/paywall-alumno-suelto.md` §4.1.1: seguir una plantilla de nivel
 * principiante es gratis, las de intermedio y avanzado son del plan pago.
 *
 * ─── Por qué la regla vive sobre `sessions` y no sobre `activeRoutineId` ────
 *
 * Porque el reloj no toca `activeRoutineId`. Los DOS clientes de reloj —el
 * Wear en Flutter y el watchOS nativo en Swift— escriben `users/{uid}/sessions`
 * directamente: el primero con el SDK de Dart, el segundo por REST con su
 * propia credencial. El #1066 cerró las tres puertas del catálogo en la UI del
 * teléfono (la grilla, "Seguir esta plantilla" y EMPEZAR), y ninguna de las
 * tres está en el camino del reloj.
 *
 * ─── Sólo el CREATE ─────────────────────────────────────────────────────────
 *
 * Un `update` sobre una sesión es `finish()`. Si el alumno empezó el entreno
 * cuando tenía derecho y lo perdió en el medio —se le venció la suscripción, o
 * se terminó el vínculo con su PF— rebotarle el cierre le borraría un
 * entrenamiento que de verdad hizo. El tope frena antes de empezar, nunca en
 * el medio.
 *
 * ─── El default INERTE ──────────────────────────────────────────────────────
 *
 * `athletePaywallEnforced` ausente ⇒ no se aplica. Hoy la CF lo escribe en
 * `false` en todos lados, así que esta regla no le cambia nada a nadie: se
 * puede deployar sola, sin esperar al gate de UI de los relojes. Eso es lo que
 * permite que el enforcement server-side y el cliente vayan en PRs distintos
 * — tienen que estar los dos antes de ENCENDER el flag, que es otra cosa.
 */
const { readFileSync } = require('fs');
const path = require('path');

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');

// Mismo projectId que los hermanos: el runner los serializa con `--runInBand`
// justamente para que compartirlo sea seguro.
const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const ATHLETE = 'athlete-1';
const LIBRE = 'ppl-beginner';
const PAGA = 'bro-split-intermediate';

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

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

const sesion = ({ routineId = LIBRE, ...extra } = {}) => ({
  uid: ATHLETE,
  routineId,
  routineName: 'Una rutina',
  startedAt: new Date(),
  finishedAt: null,
  totalVolumeKg: 0,
  durationMin: 0,
  status: 'active',
  dayNumber: 1,
  weekNumber: 0,
  ...extra,
});

async function seedUser(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({
      uid,
      email: `${uid}@treino.app`,
      role: 'athlete',
      ...data,
    });
  });
}

/** Siembra una plantilla del catálogo, con o sin el flag de pago. */
async function seedPlantilla(id, { isPremium } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const doc = {
      source: 'system',
      visibility: 'public',
      name: id,
      level: isPremium ? 'intermediate' : 'beginner',
      days: [{ dayNumber: 1, name: 'Día 1', slots: [] }],
      numWeeks: 1,
      status: 'active',
      createdAt: new Date(),
    };
    if (isPremium !== undefined) doc.isPremium = isPremium;
    await ctx.firestore().collection('routines').doc(id).set(doc);
  });
}

async function seedSesion(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('users')
      .doc(ATHLETE)
      .collection('sessions')
      .doc(id)
      .set(data);
  });
}

const sesiones = (uid) =>
  as(uid).collection('users').doc(ATHLETE).collection('sessions');

describe('el default es INERTE — se puede deployar sin el gate de los relojes', () => {
  it('sin el campo: entrenar una plantilla PAGA se permite', async () => {
    // El estado de HOY. Este test es el que garantiza que subir esta regla no
    // le rompa el entrenamiento a nadie mientras el paywall siga apagado — y
    // es lo que hace que el gate de UI del reloj pueda ir en otro PR.
    await seedUser(ATHLETE, {});
    await seedPlantilla(PAGA, { isPremium: true });
    await assertSucceeds(sesiones(ATHLETE).add(sesion({ routineId: PAGA })));
  });

  it('con enforced=false: tampoco se aplica', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: false });
    await seedPlantilla(PAGA, { isPremium: true });
    await assertSucceeds(sesiones(ATHLETE).add(sesion({ routineId: PAGA })));
  });
});

describe('con el paywall aplicado', () => {
  beforeEach(async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
  });

  it('una plantilla de principiante se entrena gratis', async () => {
    // La mitad que la spec §4.1.1 promete y que es fácil de romper de más:
    // gatear el catálogo entero dejaría al free sin nada que entrenar.
    await seedPlantilla(LIBRE, { isPremium: false });
    await assertSucceeds(sesiones(ATHLETE).add(sesion({ routineId: LIBRE })));
  });

  it('una plantilla PAGA REBOTA', async () => {
    await seedPlantilla(PAGA, { isPremium: true });
    await assertFails(sesiones(ATHLETE).add(sesion({ routineId: PAGA })));
  });

  it('sin el campo isPremium: se asume gratis y pasa', async () => {
    // Falla ABIERTO, igual que el `@Default(false)` del modelo Dart. Un doc
    // sembrado antes de que existiera el campo —o un error de siembra— abre
    // en vez de cobrar.
    await seedPlantilla(LIBRE);
    await assertSucceeds(sesiones(ATHLETE).add(sesion({ routineId: LIBRE })));
  });

  it('rutina inexistente: pasa, no tira error de evaluación', async () => {
    // `get()` de un doc ausente devuelve null, y desreferenciarlo NO deniega:
    // tira error de evaluación, que rebota con un mensaje que no dice nada.
    // Una sesión sobre una rutina borrada es un problema de datos, no de cobro.
    await assertSucceeds(
      sesiones(ATHLETE).add(sesion({ routineId: 'no-existe' })),
    );
  });

  it('la rutina PROPIA del alumno no la toca este eje', async () => {
    // El tope de la rutina propia es el de FORMA (días/semanas) y vive en el
    // match de `routines`. Acá una `user-created` nunca es `isPremium`.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('routines').doc('mia').set({
        source: 'user-created',
        createdBy: ATHLETE,
        visibility: 'private',
        name: 'Mi rutina',
        level: 'beginner',
        days: [{ dayNumber: 1, name: 'Día 1', slots: [] }],
        numWeeks: 1,
        status: 'active',
        createdAt: new Date(),
      });
    });
    await assertSucceeds(sesiones(ATHLETE).add(sesion({ routineId: 'mia' })));
  });

  it('sin routineId REBOTA', async () => {
    // `routineId` es `required` en el modelo (session.dart:16) y el watchOS lo
    // exige para armar la sesión (HistorySync.swift:142). En el camino gateado
    // su ausencia no es un cliente viejo: es el payload que se armaría para
    // esquivar el `get()` de la rutina.
    const sinRutina = sesion();
    delete sinRutina.routineId;
    await assertFails(sesiones(ATHLETE).add(sinRutina));
  });
});

describe('TERMINAR un entreno empezado nunca rebota', () => {
  // La decisión más importante de este bloque de reglas. El update es
  // `finish()`: si el derecho se venció DESPUÉS de empezar, rebotarle el
  // cierre le borraría un entrenamiento que de verdad hizo — que es
  // exactamente el daño que esta regla existe para evitar.
  const ID = 's-1';

  beforeEach(async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedPlantilla(PAGA, { isPremium: true });
    await seedSesion(ID, sesion({ routineId: PAGA }));
  });

  it('cerrar una sesión sobre una plantilla paga PASA', async () => {
    await assertSucceeds(
      sesiones(ATHLETE).doc(ID).update({
        status: 'completed',
        finishedAt: new Date(),
        durationMin: 45,
        totalVolumeKg: 1200,
      }),
    );
  });

  it('escribir setLogs de esa sesión PASA', async () => {
    // El entreno en curso tiene que poder seguir registrándose entero.
    await assertSucceeds(
      sesiones(ATHLETE)
        .doc(ID)
        .collection('setLogs')
        .add({
          exerciseId: 'bench-press',
          exerciseName: 'Press de Banca',
          setNumber: 1,
          reps: 10,
          weightKg: 60,
          createdAt: new Date(),
        }),
    );
  });

  it('borrarla PASA', async () => {
    await assertSucceeds(sesiones(ATHLETE).doc(ID).delete());
  });
});

describe('el eje no le toca nada al PF', () => {
  it('el PF vinculado sigue leyendo las sesiones de su alumno', async () => {
    // El paywall del alumno no puede recortarle al PF lo que ve de él.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedPlantilla(PAGA, { isPremium: true });
    await seedSesion('s-9', sesion({ routineId: PAGA }));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection('session_shares')
        .doc(ATHLETE)
        .set({ trainerId: 'trainer-1' });
    });
    await assertSucceeds(
      as('trainer-1')
        .collection('users')
        .doc(ATHLETE)
        .collection('sessions')
        .doc('s-9')
        .get(),
    );
  });
});
