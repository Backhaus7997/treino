/**
 * test/migrate_places_compliance.test.js
 *
 * Migración de la política de Places (#1338): `scripts/migrate_places_compliance.js`.
 *
 * Dos capas:
 *   - funciones puras (`parseArgs`, `planGym`, `planTrainer`): corren siempre,
 *     sin red y sin emulador, también en el job `scripts-test` de CI.
 *   - contra el emulador de Firestore: se SALTEAN si no hay
 *     `FIRESTORE_EMULATOR_HOST`. Para correrlas:
 *
 *       firebase emulators:exec --only firestore --project demo-places \
 *         "node --test scripts/test/migrate_places_compliance.test.js"
 *
 * Qué defiende: la migración corre una vez contra producción y NO se puede
 * deshacer. Los cuatro riesgos son (1) escribir sin que lo pidan, (2) pisar el
 * nombre que un usuario ya escribió, (3) no ser idempotente, (4) tocar gyms que
 * no vinieron de Google.
 */

const test = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const { Timestamp } = require('firebase-admin/firestore');

const {
  GYM_NOMBRE_PENDIENTE,
  parseArgs,
  planGym,
  planTrainer,
} = require('../migrate_places_compliance');

const EPOCH = Timestamp.fromMillis(0);

// ── parseArgs ───────────────────────────────────────────────────────────────

test('parseArgs — sin flags es dry-run', () => {
  const a = parseArgs(['node', 'x.js']);
  assert.strictEqual(a.apply, false);
});

test('parseArgs — --apply escribe', () => {
  assert.strictEqual(parseArgs(['node', 'x.js', '--apply']).apply, true);
});

test('parseArgs — --apply --dry-run gana el dry-run', () => {
  assert.strictEqual(parseArgs(['node', 'x.js', '--apply', '--dry-run']).apply, false);
});

test('parseArgs — --limit y --project', () => {
  const a = parseArgs(['node', 'x.js', '--limit=5', '--project=demo-places']);
  assert.strictEqual(a.limit, 5);
  assert.strictEqual(a.project, 'demo-places');
});

test('parseArgs — flag desconocida o limit inválido abortan', () => {
  assert.throws(() => parseArgs(['node', 'x.js', '--aplicar']));
  assert.throws(() => parseArgs(['node', 'x.js', '--limit=abc']));
  assert.throws(() => parseArgs(['node', 'x.js', '--limit=0']));
});

// ── planGym ─────────────────────────────────────────────────────────────────

test('planGym — gym de Google legado: placeholder, nameNeeded, sin address', () => {
  const p = planGym({
    source: 'google-places',
    name: 'Megatlon Belgrano',
    address: 'Av. Cabildo 1234',
    lat: 1,
    lng: 2,
    geohash: 'abcde',
  });
  assert.strictEqual(p.set.name, GYM_NOMBRE_PENDIENTE);
  assert.strictEqual(p.set.nameNeeded, true);
  assert.strictEqual(p.set.placeStatus, 'ok');
  assert.ok(p.set.coordsFetchedAt.isEqual(EPOCH));
  assert.deepStrictEqual(p.deleteFields, ['address']);
  assert.strictEqual(p.legacyName, true);
});

test('planGym — seed y self-service no se tocan', () => {
  assert.strictEqual(planGym({ source: 'seed', name: 'X', address: 'Y' }), null);
  assert.strictEqual(planGym({ source: 'self-service', name: 'X' }), null);
});

test('planGym — gym ya migrado no se toca (idempotencia)', () => {
  assert.strictEqual(
    planGym({
      source: 'google-places',
      name: GYM_NOMBRE_PENDIENTE,
      nameNeeded: true,
      coordsFetchedAt: EPOCH,
      placeStatus: 'ok',
    }),
    null,
  );
});

test('planGym — gym nuevo con nombre del usuario conserva el nombre', () => {
  assert.strictEqual(
    planGym({
      source: 'google-places',
      name: 'El gym de Juan',
      coordsFetchedAt: Timestamp.now(),
      placeStatus: 'ok',
    }),
    null,
  );
});

test('planGym — gym nuevo pero con address residual: solo borra address', () => {
  const p = planGym({
    source: 'google-places',
    name: 'El gym de Juan',
    address: 'Dirección de Google',
    coordsFetchedAt: Timestamp.now(),
    placeStatus: 'ok',
  });
  assert.deepStrictEqual(p.deleteFields, ['address']);
  assert.deepStrictEqual(p.set, {});
  assert.strictEqual(p.legacyName, false);
});

// ── planTrainer ─────────────────────────────────────────────────────────────

const GOOGLE_IDS = new Set(['ChIJgym1']);

test('planTrainer — loc de gym de Google: placeId y coordsFetchedAt 1970; min recalculado', () => {
  const p = planTrainer(
    {
      trainerLocations: [
        { id: 'a', type: 'gym', gymId: 'ChIJgym1', lat: 1, lng: 2, geohash: 'g' },
        { id: 'b', type: 'gym', gymId: 'seed-gym', lat: 1, lng: 2, geohash: 'h' },
      ],
    },
    GOOGLE_IDS,
  );
  assert.strictEqual(p.changed, true);
  assert.strictEqual(p.locations[0].placeId, 'ChIJgym1');
  assert.ok(p.locations[0].coordsFetchedAt.isEqual(EPOCH));
  assert.strictEqual(p.locations[1].placeId, undefined);
  assert.ok(p.min.isEqual(EPOCH));
});

test('planTrainer — idempotente: segunda pasada no cambia', () => {
  const first = planTrainer(
    { trainerLocations: [{ id: 'a', type: 'gym', gymId: 'ChIJgym1', lat: 1, lng: 2 }] },
    GOOGLE_IDS,
  );
  const second = planTrainer({ trainerLocations: first.locations }, GOOGLE_IDS);
  assert.strictEqual(second.changed, false);
});

test('planTrainer — custom sin placeId: se reporta, NO se toca', () => {
  const p = planTrainer(
    {
      trainerLocations: [
        { id: 'custom-1700000000000', type: 'custom', customLabel: 'Parque X', lat: 1, lng: 2 },
      ],
    },
    GOOGLE_IDS,
  );
  assert.strictEqual(p.changed, false);
  assert.strictEqual(p.customSinPlaceId, 1);
  assert.strictEqual(p.locations[0].customLabel, 'Parque X');
});

test('planTrainer — conserva el coordsFetchedAt que ya tiene', () => {
  const t = Timestamp.fromMillis(1_700_000_000_000);
  const p = planTrainer(
    {
      trainerLocations: [
        { id: 'a', type: 'gym', gymId: 'ChIJgym1', placeId: 'ChIJgym1', coordsFetchedAt: t },
      ],
    },
    GOOGLE_IDS,
  );
  assert.strictEqual(p.changed, false);
  assert.ok(p.min.isEqual(t));
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const EMU = process.env.FIRESTORE_EMULATOR_HOST;
const PROJECT = 'demo-places';
const SCRIPT = path.join(__dirname, '..', 'migrate_places_compliance.js');

function skipSinEmulador(nombre, fn) {
  test(nombre, { skip: EMU ? false : 'sin FIRESTORE_EMULATOR_HOST' }, fn);
}

let _db;
function db() {
  if (!_db) {
    const { initializeApp, getApps, getApp } = require('firebase-admin/app');
    const { getFirestore } = require('firebase-admin/firestore');
    const app = getApps().length ? getApp() : initializeApp({ projectId: PROJECT });
    _db = getFirestore(app);
  }
  return _db;
}

async function limpiar() {
  for (const col of ['gyms', 'users', 'userPublicProfiles', 'trainerPublicProfiles']) {
    const snap = await db().collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function sembrar() {
  const d = db();
  await d.doc('gyms/ChIJgym1').set({
    source: 'google-places',
    name: 'Megatlon Belgrano',
    address: 'Av. Cabildo 1234',
    lat: -34.5,
    lng: -58.4,
    geohash: 'abcde',
  });
  await d.doc('gyms/seed-1').set({
    source: 'seed',
    name: 'Gym Seed',
    address: 'Calle seed 1',
    lat: 0,
    lng: 0,
    geohash: 'zzzzz',
  });
  await d.doc('gyms/ChIJnew').set({
    source: 'google-places',
    name: 'Nombre del usuario',
    lat: 1,
    lng: 1,
    geohash: 'qqqqq',
    coordsFetchedAt: Timestamp.now(),
    placeStatus: 'ok',
  });
  await d.doc('userPublicProfiles/u1').set({ gymId: 'ChIJgym1', gymName: 'Megatlon Belgrano' });
  await d.doc('userPublicProfiles/u2').set({ gymId: 'seed-1', gymName: 'Gym Seed' });

  const locs = [
    { id: 'l1', type: 'gym', gymId: 'ChIJgym1', customLabel: null, lat: -34.5, lng: -58.4, geohash: 'abcde' },
    { id: 'custom-1700000000000', type: 'custom', gymId: null, customLabel: 'Parque X', lat: 3, lng: 4, geohash: 'c' },
  ];
  await d.doc('users/t1').set({
    role: 'trainer',
    trainerLocations: locs,
    trainerLocationConsentAt: Timestamp.now(),
  });
  await d.doc('trainerPublicProfiles/t1').set({ trainerLocations: locs, trainerGeohashes: ['abcde', 'c'] });
  // Sin consentimiento: el espejo público NO se toca.
  await d.doc('users/t2').set({ role: 'trainer', trainerLocations: [locs[0]], trainerLocationConsentAt: null });
  await d.doc('trainerPublicProfiles/t2').set({ trainerLocations: [] });
}

async function snapshotTodo() {
  const out = {};
  for (const col of ['gyms', 'users', 'userPublicProfiles', 'trainerPublicProfiles']) {
    const snap = await db().collection(col).get();
    for (const doc of snap.docs) out[`${col}/${doc.id}`] = JSON.stringify(doc.data());
  }
  return out;
}

function silencio() {
  const lineas = [];
  return { log: (...a) => lineas.push(a.join(' ')), warn: (...a) => lineas.push(a.join(' ')), lineas };
}

skipSinEmulador('emulador — dry-run no escribe nada', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const antes = await snapshotTodo();
  const r = await run(db(), { apply: false, limit: null }, silencio());
  assert.deepStrictEqual(await snapshotTodo(), antes);
  assert.strictEqual(r.gyms.legacy, 1);
  assert.strictEqual(r.gyms.cambiados, 1);
  assert.strictEqual(r.trainers.cambiados, 2);
  assert.strictEqual(r.applied, false);
});

skipSinEmulador('emulador — CLI sin --apply es dry-run', async () => {
  await limpiar();
  await sembrar();
  const antes = await snapshotTodo();
  const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`], {
    env: { ...process.env },
    encoding: 'utf8',
  });
  assert.strictEqual(res.status, 0, res.stderr + res.stdout);
  assert.deepStrictEqual(await snapshotTodo(), antes);
  assert.match(res.stdout, /DRY-RUN/);
});

skipSinEmulador('emulador — apply transforma gyms de Google y respeta el resto', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(db(), { apply: true, limit: null }, silencio());
  assert.strictEqual(r.applied, true);

  const g = (await db().doc('gyms/ChIJgym1').get()).data();
  assert.strictEqual(g.name, GYM_NOMBRE_PENDIENTE);
  assert.strictEqual(g.nameNeeded, true);
  assert.strictEqual('address' in g, false);
  assert.strictEqual(g.placeStatus, 'ok');
  assert.ok(g.coordsFetchedAt.isEqual(EPOCH));

  // Seed y gym ya nombrado por un usuario: intactos.
  const seed = (await db().doc('gyms/seed-1').get()).data();
  assert.strictEqual(seed.name, 'Gym Seed');
  assert.strictEqual(seed.address, 'Calle seed 1');
  const nuevo = (await db().doc('gyms/ChIJnew').get()).data();
  assert.strictEqual(nuevo.name, 'Nombre del usuario');
  assert.strictEqual(nuevo.nameNeeded, undefined);
});

skipSinEmulador('emulador — apply: lugares de PF, min y espejo con consentimiento', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(db(), { apply: true, limit: null }, silencio());

  const t1 = (await db().doc('users/t1').get()).data();
  assert.strictEqual(t1.trainerLocations[0].placeId, 'ChIJgym1');
  assert.ok(t1.trainerLocations[0].coordsFetchedAt.isEqual(EPOCH));
  assert.ok(t1.trainerLocationsCoordsFetchedAt.isEqual(EPOCH));
  // El custom no se identifica con certeza: no se toca.
  assert.strictEqual(t1.trainerLocations[1].customLabel, 'Parque X');
  assert.strictEqual(t1.trainerLocations[1].placeId, undefined);
  assert.strictEqual(r.trainers.customSinPlaceId, 1);

  const pub1 = (await db().doc('trainerPublicProfiles/t1').get()).data();
  assert.strictEqual(pub1.trainerLocations[0].placeId, 'ChIJgym1');

  // t2 sin consentimiento: se actualiza users, el espejo público queda igual.
  const t2 = (await db().doc('users/t2').get()).data();
  assert.strictEqual(t2.trainerLocations[0].placeId, 'ChIJgym1');
  const pub2 = (await db().doc('trainerPublicProfiles/t2').get()).data();
  assert.deepStrictEqual(pub2.trainerLocations, []);
});

skipSinEmulador('emulador — idempotente: segundo apply no cambia nada', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  await run(db(), { apply: true, limit: null }, silencio());
  const antes = await snapshotTodo();
  const r2 = await run(db(), { apply: true, limit: null }, silencio());
  assert.strictEqual(r2.gyms.cambiados, 0);
  assert.strictEqual(r2.trainers.cambiados, 0);
  assert.deepStrictEqual(await snapshotTodo(), antes);
});

skipSinEmulador('emulador — no duplica la propagación a perfiles salvo --clear-profile-names', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(db(), { apply: true, limit: null }, silencio());
  assert.strictEqual(r.profiles.afectados, 1);
  // El trigger propagateGymNameToProfiles es el que lo limpia; el script no.
  assert.strictEqual((await db().doc('userPublicProfiles/u1').get()).data().gymName, 'Megatlon Belgrano');

  await limpiar();
  await sembrar();
  await run(db(), { apply: true, limit: null, clearProfileNames: true }, silencio());
  assert.strictEqual((await db().doc('userPublicProfiles/u1').get()).data().gymName, null);
  assert.strictEqual((await db().doc('userPublicProfiles/u2').get()).data().gymName, 'Gym Seed');
});

skipSinEmulador('emulador — --limit acota los gyms cambiados', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  await db().doc('gyms/ChIJgym2').set({ source: 'google-places', name: 'Otro', address: 'x', lat: 1, lng: 1, geohash: 'k' });
  const r = await run(db(), { apply: true, limit: 1 }, silencio());
  assert.strictEqual(r.gyms.cambiados, 1);
});

// ── Hallazgos de la revisión del PR #1362 ───────────────────────────────────

test('planTrainer — coordsFetchedAt null explícito en un lugar stale se respeta (no se resetea a 1970)', () => {
  const stale = {
    id: 'a', type: 'gym', gymId: 'ChIJgym1', placeId: 'ChIJgym1',
    stale: true, lat: null, lng: null, coordsFetchedAt: null,
  };
  const p = planTrainer({ trainerLocations: [stale] }, GOOGLE_IDS);
  assert.strictEqual(p.changed, false);
  assert.strictEqual(p.locations[0].coordsFetchedAt, null);
});

test('planTrainer — null explícito se respeta aunque no esté stale; ausente + stale tampoco se completa', () => {
  const a = planTrainer(
    { trainerLocations: [{ id: 'a', type: 'gym', gymId: 'ChIJgym1', placeId: 'ChIJgym1', coordsFetchedAt: null }] },
    GOOGLE_IDS,
  );
  assert.strictEqual(a.changed, false);
  const b = planTrainer(
    { trainerLocations: [{ id: 'a', type: 'gym', gymId: 'ChIJgym1', placeId: 'ChIJgym1', stale: true }] },
    GOOGLE_IDS,
  );
  assert.strictEqual(b.changed, false);
});

skipSinEmulador('emulador — lugar stale con coordsFetchedAt null: intacto y segundo apply = 0 cambios', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await db().doc('gyms/ChIJgym1').set({ source: 'google-places', name: 'X', lat: 1, lng: 1, geohash: 'k', coordsFetchedAt: Timestamp.now(), placeStatus: 'ok' });
  const loc = { id: 'l1', type: 'gym', gymId: 'ChIJgym1', placeId: 'ChIJgym1', stale: true, lat: null, lng: null, coordsFetchedAt: null };
  await db().doc('users/t1').set({ role: 'trainer', trainerLocations: [loc], trainerLocationConsentAt: null });
  const antes = await snapshotTodo();
  const r = await run(db(), { apply: true, limit: null }, silencio());
  assert.strictEqual(r.trainers.cambiados, 0);
  assert.deepStrictEqual(await snapshotTodo(), antes);
  const r2 = await run(db(), { apply: true, limit: null }, silencio());
  assert.strictEqual(r2.trainers.cambiados, 0);
});

skipSinEmulador('emulador — gym borrado entre lectura y escritura (NOT_FOUND) cuenta como conflicto y no aborta', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(
    db(),
    { apply: true, limit: null, antesDeCommit: async () => { await db().doc('gyms/ChIJgym1').delete(); } },
    silencio(),
  );
  assert.strictEqual(r.gyms.conflictos, 1);
  assert.strictEqual(r.gyms.cambiados, 0);
});

skipSinEmulador('emulador — espejo público modificado entre lectura y commit: se saltea y cuenta como conflicto', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(
    db(),
    {
      apply: true,
      limit: null,
      antesDeCommit: async (fase) => {
        if (fase === 'entrenadores') await db().doc('trainerPublicProfiles/t1').update({ marca: 'concurrente' });
      },
    },
    silencio(),
  );
  assert.strictEqual(r.trainers.conflictos, 1);
  assert.strictEqual(r.trainers.espejados, 0);
  const pub = (await db().doc('trainerPublicProfiles/t1').get()).data();
  assert.strictEqual(pub.marca, 'concurrente');
  assert.strictEqual(pub.trainerLocations[0].placeId, undefined);
  // El grupo es atómico: users/t1 tampoco se tocó; re-correr lo resuelve.
  const t1 = (await db().doc('users/t1').get()).data();
  assert.strictEqual(t1.trainerLocations[0].placeId, undefined);
});

skipSinEmulador('emulador — --clear-profile-names no limpia perfiles de gyms que terminaron en conflicto', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(
    db(),
    {
      apply: true,
      limit: null,
      clearProfileNames: true,
      antesDeCommit: async () => { await db().doc('gyms/ChIJgym1').update({ marca: 'concurrente' }); },
    },
    silencio(),
  );
  assert.strictEqual(r.gyms.conflictos, 1);
  assert.strictEqual((await db().doc('gyms/ChIJgym1').get()).data().name, 'Megatlon Belgrano');
  assert.strictEqual((await db().doc('userPublicProfiles/u1').get()).data().gymName, 'Megatlon Belgrano');
});

skipSinEmulador('emulador — --limit también acota la limpieza de perfiles', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  await db().doc('userPublicProfiles/u3').set({ gymId: 'ChIJgym1', gymName: 'Megatlon Belgrano' });
  await db().doc('userPublicProfiles/u4').set({ gymId: 'ChIJgym1', gymName: 'Megatlon Belgrano' });
  const r = await run(db(), { apply: true, limit: 2, clearProfileNames: true }, silencio());
  assert.strictEqual(r.profiles.escritos, 2);
  assert.strictEqual(r.profiles.omitidosPorLimit, 1);
});

skipSinEmulador('emulador — --limit acota PF y espejos', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  const r = await run(db(), { apply: true, limit: 1 }, silencio());
  assert.strictEqual(r.trainers.cambiados, 1);
  assert.ok(r.trainers.espejados <= 1);
  assert.strictEqual(r.trainers.omitidosPorLimit, 1);
});

skipSinEmulador('emulador — usuarios con trainerLocations se migran sin importar el rol', async () => {
  const { run } = require('../migrate_places_compliance');
  await limpiar();
  await sembrar();
  await db().doc('users/a1').set({
    role: 'athlete',
    trainerLocations: [{ id: 'l1', type: 'gym', gymId: 'ChIJgym1', lat: 1, lng: 2, geohash: 'g' }],
  });
  await db().doc('users/a2').set({ role: 'athlete' });
  await run(db(), { apply: true, limit: null }, silencio());
  const a1 = (await db().doc('users/a1').get()).data();
  assert.strictEqual(a1.trainerLocations[0].placeId, 'ChIJgym1');
});
