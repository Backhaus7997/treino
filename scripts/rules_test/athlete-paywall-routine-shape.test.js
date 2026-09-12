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
 *      puerta con la ventana abierta al lado: creás con 3 días y editás a 7.
 *
 *      Y en update se mide el documento RESULTANTE, no el delta. De ahí sale
 *      lo que puede hacer el dueño de una rutina que quedó de antes por
 *      encima del tope: renombrarla REBOTA (el resultante sigue afuera),
 *      recortarla al tope PASA, archivarla PASA (es UPDATE path 1). Los tres
 *      están cubiertos abajo, porque los tres son el camino real de la
 *      población que ya tiene rutinas armadas el día que esto se encienda.
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

  it('con enforced=true: 3 días pasa — es el tope, y el tope entra', async () => {
    // El caso que fija el número contra el CATÁLOGO. Las tres plantillas que
    // el free puede seguir gratis (`ppl-beginner`, `full-body-3day`,
    // `calistenia-beginner`) tienen 3 días. Si este test se pone rojo, la app
    // volvió a recomendarle al alumno un programa que no lo deja armarse.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertSucceeds(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 3 })),
    );
  });

  it('con enforced=true: 4 días REBOTA', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(
      as(ATHLETE).collection('routines').add(rutina(ATHLETE, { days: 4 })),
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

  it('con enforced=true: crecer a 4 días REBOTA', async () => {
    // SIN esta cláusula el tope del create sería una puerta con la ventana
    // abierta al lado: creo con 3 y edito a 7.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 3 }));
    await assertFails(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3), day(4)] }),
    );
  });

  it('con enforced=true: crecer HASTA el tope (2 → 3) pasa', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2 }));
    await assertSucceeds(
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

  // ── La rutina que quedó de antes por encima del tope ──────────────────────
  //
  // Es la población más grande del día del encendido, no un caso de borde: hoy
  // `kAthletePaywallEnabled` está en `false` y la CF escribe
  // `athletePaywallEnforced: false`, así que TODAS las rutinas que existan
  // están armadas sin tope. A eso se suman los que pierden el derecho con la
  // rutina ya guardada (se termina el vínculo con el PF, o se vence el pago).
  //
  // Estos tres tests existen porque el comentario de la regla describía este
  // caso MAL: decía "se puede seguir tocando mientras no crezca", que es falso
  // —la cláusula mide el RESULTANTE— y se contradecía con su propia frase
  // siguiente. Quien lo leyera daba por cubierto un camino que rebotaba.
  // AGENTS.md §11.1. Ahora el comportamiento lo fija el emulador y no la prosa.

  it('con enforced=true: RENOMBRAR una de 4 días PASA', async () => {
    // ⚠️ Este test decía REBOTA hasta el 2026-09-11, y la historia vale.
    //
    // El comentario original de la regla daba por permitido renombrar. Era
    // FALSO —la cláusula medía el resultante— y se escribió este test para
    // fijar la verdad incómoda: no se podía ni cambiarle el nombre.
    //
    // Después se midió la población real: 5 alumnos de 18. Y "podés entrenarla
    // pero no podés renombrarla" resultó imposible de explicar. Así que se
    // cambió LA REGLA, no el comentario: `noCreceLaForma` deja pasar un update
    // que no agranda la rutina.
    //
    // O sea que el comentario viejo describía el comportamiento que hoy es
    // correcto. Se equivocaba de tiempo verbal, no de idea.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 4 }));
    await assertSucceeds(
      as(ATHLETE).collection('routines').doc(ID).update({ name: 'Renombrada' }),
    );
  });

  it('con enforced=true: RECORTAR de 5 a 4 pasa, aunque siga sobre el tope', async () => {
    // El caso que `noCreceLaForma` existe para habilitar, y que
    // `withinFreeRoutineShape` no cubre: 4 sigue siendo > 3, pero 4 < 5.
    //
    // Sin esto, el alumno con una rutina de 5 días tenía una sola salida —
    // recortar de golpe hasta 3— y nada intermedio.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 5 }));
    await assertSucceeds(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3), day(4)] }),
    );
  });

  it('EL QUE IMPORTA: agrandar una que YA estaba sobre el tope REBOTA', async () => {
    // `noCreceLaForma` compara contra lo que el documento YA TENÍA, no contra
    // el tope. Si comparara contra el tope, una rutina de 4 días sería una
    // licencia para crecer sin límite.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 4 }));
    await assertFails(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3), day(4), day(5)] }),
    );
  });

  it('con enforced=true: bajar de 8 a 4 semanas pasa, aunque siga sobre el tope', async () => {
    // El eje que de verdad muerde. Medido el 2026-09-11: de los 5 alumnos
    // afectados, 4 lo estaban por SEMANAS y sólo 2 por días.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2, numWeeks: 8 }));
    await assertSucceeds(
      as(ATHLETE).collection('routines').doc(ID).update({ numWeeks: 4 }),
    );
  });

  it('con enforced=true: subir de 2 a 3 semanas REBOTA', async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 2, numWeeks: 2 }));
    await assertFails(
      as(ATHLETE).collection('routines').doc(ID).update({ numWeeks: 3 }),
    );
  });

  it('LOS DOS EJES: recortar días pero agrandar semanas REBOTA', async () => {
    // `noCreceLaForma` exige que NINGUNO de los dos crezca. Con un `||` en vez
    // de un `&&`, recortar un día compraría semanas gratis.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 5, numWeeks: 2 }));
    await assertFails(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3), day(4)], numWeeks: 3 }),
    );
  });

  it('con enforced=true: RECORTAR una de 4 días al tope PASA', async () => {
    // La salida real, y la razón por la que el cliente puede ofrecer una
    // acción concreta ("sacá los días que sobran") en vez de sólo una
    // negativa. Con el tope en 2 esto no existía: bajar de 4 a 3 seguía
    // rebotando y el alumno no tenía nada que hacer más que archivarla.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await seedRoutine(ID, rutina(ATHLETE, { days: 4 }));
    await assertSucceeds(
      as(ATHLETE)
        .collection('routines')
        .doc(ID)
        .update({ days: [day(1), day(2), day(3)] }),
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
