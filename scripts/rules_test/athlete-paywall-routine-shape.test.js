/**
 * Paywall del alumno suelto — los topes de FORMA de rutina, del lado servidor.
 *
 * `docs/paywall-alumno-suelto.md` §4 y §6.2. El cliente ya muestra estos topes
 * (`kFreeMaxRoutineDays` / `kFreeMaxRoutineWeeks`), pero eso es UX: un cliente
 * parcheado los ignora. Esto es la ley.
 *
 * Los dos ejes que cubre este archivo:
 *
 *   1. Que el tope MUERDA en create Y en update. Sólo en create sería una
 *      puerta con la ventana abierta al lado: creás con 2 días y editás a 7.
 *
 *   2. Que el default sea INERTE. `athletePaywallEnforced` lo escribe una CF
 *      que TODAVÍA NO EXISTE, así que hoy el campo está ausente en todos los
 *      docs. Ausente ⇒ no se aplica. Si fuera al revés, subir esta regla le
 *      cortaría la rutina de 3 días a TODOS los atletas —sin que ninguno pueda
 *      pagar— porque las reglas no leen el flag del cliente: se aplican apenas
 *      se deployan.
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

/** Un día con un slot — el contenido no importa acá, sólo cuántos hay. */
const day = (n) => ({ dayNumber: n, name: `Día ${n}`, slots: [] });

const rutina = (uid, { days = 1, numWeeks = 1, ...extra } = {}) => ({
  source: 'user-created',
  createdBy: uid,
  visibility: 'private',
  name: 'Mi rutina',
  level: 'beginner',
  days: Array.from({ length: days }, (_, i) => day(i + 1)),
  numWeeks,
  status: 'active',
  createdAt: new Date(),
  ...extra,
});

/** Siembra `users/{uid}` saltéandose las reglas. */
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

/** Siembra una rutina saltéandose las reglas (para probar updates). */
async function seedRoutine(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc(id).set(data);
  });
}

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

describe('paywall del alumno — CREATE de rutina propia', () => {
  it('sin el campo: NO se aplica, aunque la rutina exceda el tope', async () => {
    // El estado de HOY: la CF que escribe `athletePaywallEnforced` no existe,
    // así que el campo está ausente en todos los docs. Este test es el que
    // garantiza que subir la regla no le rompa la app a nadie.
    await seedUser(ATHLETE, {});
    await assertSucceeds(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 5 })),
    );
  });

  it('con enforced=false: tampoco se aplica', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: false });
    await assertSucceeds(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 7 })),
    );
  });

  it('con enforced=true: 2 días pasa', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertSucceeds(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 2 })),
    );
  });

  it('con enforced=true: 3 días REBOTA', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 3 })),
    );
  });

  it('con enforced=true: 2 semanas REBOTA aunque los días entren', async () => {
    // El otro eje del tope. Periodizar es la parte paga.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(
      as(ATHLETE)
        .collection('routines')
        .add(rutina(ATHLETE, { days: 2, numWeeks: 2 })),
    );
  });

  it('con enforced=true y numWeeks ausente: se asume 1 y pasa', async () => {
    // Docs viejos y payloads mínimos no traen `numWeeks`. El default del
    // modelo es 1, y la regla tiene que leerlo igual o rebotaría escrituras
    // perfectamente válidas.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    const sinNumWeeks = rutina(ATHLETE, { days: 2 });
    delete sinNumWeeks.numWeeks;
    await assertSucceeds(
      as(ATHLETE).collection('routines').add(sinNumWeeks),
    );
  });
});

describe('paywall del alumno — UPDATE de rutina propia', () => {
  const ID = 'r-1';

  it('con enforced=true: crecer a 3 días REBOTA', async () => {
    // SIN esta cláusula el tope del create sería una puerta con la ventana
    // abierta al lado: creo con 2 y edito a 7.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2 }));
    await assertFails(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3)] }),
    );
  });

  it('con enforced=true: editar dentro del tope sigue permitido', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2 }));
    await assertSucceeds(
      as(ATHLETE).collection('routines').doc(ID).update({ name: 'Otro nombre' }),
    );
  });

  it('con enforced=true: subir a 2 semanas REBOTA', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2 }));
    await assertFails(
      as(ATHLETE).collection('routines').doc(ID).update({ numWeeks: 2 }),
    );
  });

  it('sin el campo: se puede editar una rutina grande sin problema', async () => {
    await seedUser(ATHLETE, {});
    await seedRoutine(ID, rutina(ATHLETE, { days: 5 }));
    await assertSucceeds(
      as(ATHLETE).collection('routines').doc(ID).update({ name: 'Renombrada' }),
    );
  });

  it('ARCHIVAR una rutina grande NO pasa por el tope', async () => {
    // Archivar es UPDATE path 1 (`affectedKeys == ['status']`), que no lleva
    // la cláusula del paywall. Y tiene que seguir así: la spec §5 dice que al
    // cancelar no se borra ni se bloquea nada, sólo se congela la EDICIÓN. Si
    // el tope alcanzara a archivar, alguien con una rutina de 5 días quedaría
    // sin poder ni sacársela de encima.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 5 }));
    await assertSucceeds(
      as(ATHLETE).collection('routines').doc(ID).update({ status: 'archived' }),
    );
  });
});

describe('el tope NO alcanza a las rutinas del PF', () => {
  it('un plan trainer-assigned de 5 días se crea igual', async () => {
    // El PF ya paga por su cupo (§2). Su paywall es otro y vive en
    // `subscription`, no acá.
    const TRAINER = 'trainer-1';
    await seedUser(TRAINER, {
      role: 'trainer',
      athletePaywallEnforced: true, // aunque estuviera marcado
    });
    await seedUser(ATHLETE, { athletePaywallEnforced: true });

    await assertSucceeds(
      testEnv
        .authenticatedContext(TRAINER)
        .firestore()
        .collection('routines')
        .add({
          source: 'trainer-assigned',
          assignedBy: TRAINER,
          assignedTo: ATHLETE,
          visibility: 'private',
          name: 'Plan del PF',
          level: 'beginner',
          days: [day(1), day(2), day(3), day(4), day(5)],
          numWeeks: 8,
          createdAt: new Date(),
        }),
    );
  });
});

describe('el campo es CF-write-only', () => {
  it('el alumno NO puede eximirse a sí mismo', async () => {
    // Si pudiera, todo esto sería decorativo: se pone `false` y listo.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(
      as(ATHLETE)
        .collection('users')
        .doc(ATHLETE)
        .update({ athletePaywallEnforced: false }),
    );
  });
});
