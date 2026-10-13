'use strict';

/**
 * Firestore Security Rules — forma de `trainerLocations` (#1338).
 *
 * `users/{uid}.trainerLocations` (privada) y su espejo
 * `trainerPublicProfiles/{uid}.trainerLocations` (lo lee cualquier
 * autenticado) no tenían NINGUNA validación: un cliente modificado podía
 * colgar de cada lugar el nombre o la dirección de Google, que las políticas
 * de Places no dejan guardar. Las reglas ahora exigen, por lugar, sólo las
 * claves del modelo, `type` del enum e `id` string; el espejo además el rango
 * de lat/lng. Tope de 10 lugares. Detalle y presupuesto en `ubicacionDePFOk` /
 * `ubicacionesDePFOk` de firestore.rules.
 *
 * Las dos formas que escribe la app PUBLICADA, y que estas reglas no pueden
 * rechazar (si no, un PF con una build vieja no guarda más su perfil):
 *
 *   - builds <= 53: `TrainerLocation.toJson()` con 7 claves —
 *     `git show 08a9487d:lib/features/coach/domain/trainer_location.g.dart`.
 *     Además DESCARTA `placeId`/`coordsFetchedAt`/`stale` al releer un lugar,
 *     así que reescribe como "nuevo" cada lugar que las tenía.
 *   - builds >= 54 y Coach Hub: las 10 claves (16ae0f77).
 *
 * El caso PRESUPUESTO fija el límite que no se ve leyendo: Firestore corta
 * una regla a las 1.000 expresiones, y el `allow update` de `users/{uid}` ya
 * gasta buena parte. Si un cambio futuro en esa regla (o en ésta) se come el
 * margen, ese test se pone rojo ANTES de que un PF con 10 lugares se quede sin
 * poder guardar en producción con un permission-denied sin mensaje.
 *
 * Run via: bash scripts/test_rules.sh  (trae su propio emulador; Java 21+)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const firebaseCompat = require('firebase/compat/app');
require('firebase/compat/firestore');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const UID = 'pf-ubicaciones';
const { Timestamp, FieldValue } = firebaseCompat.firestore;

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

afterEach(async () => {
  await testEnv.clearFirestore();
});

// ── Formas reales ───────────────────────────────────────────────────────────

/** Lugar `custom` del Coach Hub (build >= 54): 10 claves, con `placeId`. */
function lugarActual(i = 0, extra = {}) {
  return {
    id: `custom-${1760000000000 + i}`,
    type: 'custom',
    gymId: null,
    customLabel: `Mi estudio ${i}`,
    lat: -34.6037 + i / 1000,
    lng: -58.3816 + i / 1000,
    geohash: '69y7p',
    placeId: `ChIJ${'a'.repeat(23)}${i}`,
    coordsFetchedAt: Timestamp.fromMillis(1760000000000),
    stale: null,
    ...extra,
  };
}

/** Lugar `gym` de una build <= 53: 7 claves, null explícitos. */
function lugarBuildVieja(i = 0, extra = {}) {
  return {
    id: `gym-gimnasio-${i}`,
    type: 'gym',
    gymId: `gimnasio-${i}`,
    customLabel: null,
    lat: -31.4201 + i / 1000,
    lng: -64.1888 + i / 1000,
    geohash: '6t7sy',
    ...extra,
  };
}

/** Lo que deja el job de refresco cuando ya no puede cachear las coordenadas. */
function lugarStale(i = 0) {
  return lugarActual(i, { lat: null, lng: null, geohash: null, stale: true });
}

async function seed({ users = {}, mirror = null } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(UID).set({
      uid: UID,
      email: 'pf@treino.test',
      role: 'trainer',
      createdAt: Timestamp.fromMillis(1700000000000),
      displayName: 'PF',
      trainerBio: 'bio',
      trainerOffersOnline: true,
      trainerLocations: [],
      trainerGeohashes: [],
      ...users,
    });
    if (mirror) {
      await db.collection('trainerPublicProfiles').doc(UID).set({ uid: UID, ...mirror });
    }
  });
}

function pf() {
  return testEnv.authenticatedContext(UID).firestore();
}

/** `UserRepository.update`: `set(merge:true)` sobre users/{uid}. */
function guardarPrivado(lugares, extra = {}) {
  return pf().collection('users').doc(UID).set(
    { trainerLocations: lugares, ...extra },
    { merge: true },
  );
}

/** El espejo, también `set(merge:true)` y siempre con `uid`. */
function guardarEspejo(lugares, extra = {}) {
  return pf().collection('trainerPublicProfiles').doc(UID).set(
    { uid: UID, trainerLocations: lugares, ...extra },
    { merge: true },
  );
}

/** El dual-write entero, en un solo batch, como `UserRepository.update`. */
function guardarAmbos(lugares) {
  const db = pf();
  const batch = db.batch();
  batch.set(db.collection('users').doc(UID), { trainerLocations: lugares }, { merge: true });
  batch.set(
    db.collection('trainerPublicProfiles').doc(UID),
    { uid: UID, trainerLocations: lugares },
    { merge: true },
  );
  return batch.commit();
}

// ── users/{uid}: lo que la app publicada escribe tiene que pasar ────────────

describe('users/{uid}.trainerLocations — formas legítimas', () => {
  test('forma actual (build >= 54 / Coach Hub, 10 claves) pasa', async () => {
    await seed();
    await assertSucceeds(guardarPrivado([lugarActual(0)]));
  });

  test('forma de build <= 53 (7 claves, null explícitos) pasa', async () => {
    await seed();
    await assertSucceeds(guardarPrivado([lugarBuildVieja(0)]));
  });

  test('build vieja reescribe sin placeId/coordsFetchedAt/stale lo que el job guardó con 10 claves', async () => {
    const guardados = [lugarActual(0), lugarActual(1)];
    await seed({ users: { trainerLocations: guardados } });
    const sinClavesNuevas = guardados.map(({ placeId, coordsFetchedAt, stale, ...resto }) => resto);
    await assertSucceeds(guardarPrivado(sinClavesNuevas));
  });

  test('lugar stale (lat/lng/geohash null) y etiqueta vaciada por la cuarentena pasan', async () => {
    await seed();
    await assertSucceeds(guardarPrivado([lugarStale(0), lugarActual(1, { customLabel: '' })]));
  });

  test('vaciar la lista pasa', async () => {
    await seed({ users: { trainerLocations: [lugarActual(0)] } });
    await assertSucceeds(guardarPrivado([]));
  });
});

// ── users/{uid}: lo que la regla tiene que frenar ───────────────────────────

describe('users/{uid}.trainerLocations — formas rechazadas', () => {
  test('una clave fuera del modelo (texto de Google) se rechaza', async () => {
    await seed();
    await assertFails(guardarPrivado([lugarActual(0, { formattedAddress: 'Av. Corrientes 1234, CABA' })]));
  });

  test('un type fuera del enum, o sin type, se rechaza', async () => {
    await seed();
    await assertFails(guardarPrivado([lugarActual(0, { type: 'place' })]));
    const { type, ...sinType } = lugarActual(1);
    await assertFails(guardarPrivado([sinType]));
  });

  test('un id que no es string se rechaza', async () => {
    await seed();
    await assertFails(guardarPrivado([lugarActual(0, { id: 42 })]));
  });

  test('un elemento que no es un mapa, o una lista que no es lista, se rechaza', async () => {
    await seed();
    await assertFails(guardarPrivado(['Parque Sarmiento']));
    await assertFails(guardarPrivado({ 0: lugarActual(0) }));
    await assertFails(guardarPrivado(null));
  });

  test('11 lugares se rechazan (tope de 10)', async () => {
    await seed();
    await assertFails(guardarPrivado(Array.from({ length: 11 }, (_, i) => lugarActual(i))));
  });

  test('la clave ajena en el ÚLTIMO índice también se rechaza (cada índice se mira)', async () => {
    await seed();
    const lugares = Array.from({ length: 10 }, (_, i) => lugarActual(i));
    lugares[9] = lugarActual(9, { address: 'texto de Google' });
    await assertFails(guardarPrivado(lugares));
  });

  test('el alta del documento con un lugar fuera del modelo se rechaza', async () => {
    await assertFails(
      pf().collection('users').doc(UID).set({
        uid: UID,
        email: 'pf@treino.test',
        role: 'athlete',
        createdAt: Timestamp.fromMillis(1700000000000),
        displayName: null,
        trainerLocations: [lugarActual(0, { name: 'Gimnasio X (Google)' })],
      }),
    );
  });

  test('el alta del documento con [] (lo que manda UserProfile.toJson) pasa', async () => {
    await assertSucceeds(
      pf().collection('users').doc(UID).set({
        uid: UID,
        email: 'pf@treino.test',
        role: 'athlete',
        createdAt: Timestamp.fromMillis(1700000000000),
        displayName: null,
        trainerLocations: [],
      }),
    );
  });
});

// ── #849: lo guardado de antes no congela el documento ──────────────────────

describe('users/{uid}.trainerLocations — datos legacy', () => {
  // Una lista que HOY se rechazaría: 11 lugares y uno con clave ajena. No la
  // puede escribir un cliente después de esta regla, pero puede existir de
  // antes, y su dueño tiene que poder seguir usando el resto del perfil.
  const legacyInvalida = [
    lugarActual(0, { formattedAddress: 'Av. Siempreviva 742' }),
    ...Array.from({ length: 10 }, (_, i) => lugarBuildVieja(i + 1)),
  ];

  test('un update que no toca la lista pasa aunque la guardada sea inválida', async () => {
    await seed({ users: { trainerLocations: legacyInvalida } });
    await assertSucceeds(pf().collection('users').doc(UID).set({ trainerBio: 'bio nueva' }, { merge: true }));
  });

  test('agregar un lugar válido a una lista con un lugar legacy inválido pasa (el viejo no se revalida)', async () => {
    const guardados = [lugarActual(0, { formattedAddress: 'Av. Siempreviva 742' }), lugarBuildVieja(1)];
    await seed({ users: { trainerLocations: guardados } });
    await assertSucceeds(guardarPrivado([...guardados, lugarActual(2)]));
  });

  test('pero MODIFICAR el lugar legacy inválido lo revalida, y se rechaza', async () => {
    const guardados = [lugarActual(0, { formattedAddress: 'Av. Siempreviva 742' })];
    await seed({ users: { trainerLocations: guardados } });
    await assertFails(guardarPrivado([{ ...guardados[0], customLabel: 'Otro nombre' }]));
  });
});

// ── trainerPublicProfiles/{uid}: el espejo público ──────────────────────────

describe('trainerPublicProfiles/{uid}.trainerLocations', () => {
  test('forma actual y forma de build <= 53 pasan', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarEspejo([lugarActual(0), lugarBuildVieja(1)]));
  });

  test('una build <= 53 espeja también lugares stale (no filtra publicables): pasa', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarEspejo([lugarStale(0)]));
  });

  test('el create del espejo (primer dual-write / primer consentimiento) valida igual', async () => {
    await seed();
    await assertSucceeds(guardarEspejo([lugarActual(0)]));
    await testEnv.clearFirestore();
    await seed();
    await assertFails(guardarEspejo([lugarActual(0, { formattedAddress: 'texto de Google' })]));
  });

  test('una clave fuera del modelo se rechaza', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertFails(guardarEspejo([lugarActual(0, { formattedAddress: 'Av. Corrientes 1234' })]));
  });

  test('lat o lng fuera de rango se rechazan', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertFails(guardarEspejo([lugarActual(0, { lat: 91 })]));
    await assertFails(guardarEspejo([lugarActual(0, { lat: -90.5 })]));
    await assertFails(guardarEspejo([lugarActual(0, { lng: 180.01 })]));
  });

  test('lat que no es número se rechaza', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertFails(guardarEspejo([lugarActual(0, { lat: '-34.6' })]));
  });

  test('los bordes del rango pasan', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarEspejo([lugarActual(0, { lat: -90, lng: 180 })]));
  });

  test('11 lugares se rechazan', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertFails(guardarEspejo(Array.from({ length: 11 }, (_, i) => lugarActual(i))));
  });

  test('un update del espejo que no toca la lista pasa aunque la publicada sea inválida', async () => {
    await seed({ mirror: { trainerLocations: [lugarActual(0, { lat: 500, address: 'x' })] } });
    await assertSucceeds(
      pf().collection('trainerPublicProfiles').doc(UID).set({ uid: UID, trainerBio: 'bio' }, { merge: true }),
    );
  });

  test('el revoke (vacía la lista) pasa', async () => {
    await seed({ mirror: { trainerLocations: [lugarActual(0)] } });
    await assertSucceeds(
      guardarEspejo([], { trainerGeohashes: [], trainerLatitude: null, trainerLongitude: null, trainerGeohash: null }),
    );
  });

  test('en el dual-write, un lat fuera de rango tumba también la escritura privada', async () => {
    await seed({ mirror: { trainerLocations: [] } });
    await assertFails(guardarAmbos([lugarActual(0, { lat: 1000 })]));
    let guardados;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      guardados = (await ctx.firestore().collection('users').doc(UID).get()).data().trainerLocations;
    });
    expect(guardados).toEqual([]);
  });
});

// ── PRESUPUESTO: el peor caso legítimo tiene que entrar ─────────────────────
//
// 10 lugares, TODOS nuevos para las dos reglas: es lo que pasa la primera vez
// que se guardan, o en cada guardado de una build <= 53 sobre lugares con
// `placeId` (los reescribe sin esa clave). Si alguno de estos se pone rojo sin
// que hayas tocado las ubicaciones, es que la regla de `users/{uid}` o la de
// `trainerPublicProfiles/{uid}` creció y se comió el margen del límite de
// 1.000 expresiones — ver el comentario de `ubicacionDePFOk`.

describe('presupuesto de expresiones', () => {
  test('10 lugares nuevos con la forma actual pasan en users, en el espejo y en el dual-write', async () => {
    const diez = Array.from({ length: 10 }, (_, i) => lugarActual(i));
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarPrivado(diez));
    await testEnv.clearFirestore();
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarEspejo(diez));
    await testEnv.clearFirestore();
    await seed({ mirror: { trainerLocations: [] } });
    await assertSucceeds(guardarAmbos(diez));
  });

  test('10 lugares de build <= 53 pisando 10 guardados con 10 claves pasan en el dual-write', async () => {
    const guardados = Array.from({ length: 10 }, (_, i) => lugarActual(i));
    await seed({ users: { trainerLocations: guardados }, mirror: { trainerLocations: guardados } });
    const reescritos = guardados.map(({ placeId, coordsFetchedAt, stale, ...resto }) => resto);
    await assertSucceeds(guardarAmbos(reescritos));
  });

  test('el create del espejo con 10 lugares nuevos pasa', async () => {
    await seed();
    await assertSucceeds(guardarEspejo(Array.from({ length: 10 }, (_, i) => lugarActual(i))));
  });
});

// Borrar el campo entero (deleteField) deja la lista "vacía" para la regla.
describe('users/{uid}.trainerLocations — borrar el campo', () => {
  test('deleteField pasa', async () => {
    await seed({ users: { trainerLocations: [lugarActual(0)] } });
    await assertSucceeds(
      pf().collection('users').doc(UID).update({ trainerLocations: FieldValue.delete() }),
    );
  });
});
