/**
 * test/npm_entrypoints_banner.test.js
 *
 * El CABLEADO de los entrypoints que se invocan por `npm run`, más
 * `deploy_rules.js`. Cada test levanta el script REAL en un subproceso con
 * `firebase-admin`, `google-auth-library` y la lectura de `sa-key.json`
 * stubbeados por `fixtures/stub_firebase_admin.js`. Cero red, cero credenciales.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#826): el barrido de la pasada anterior buscaba comandos de
 * `firebase` y `gcloud`, así que no veía `npm run seed:all` — el camino más
 * corto que hay hacia producción, y el que el propio PR declara como riesgo
 * MAYOR (39 de 43 scripts escriben por Admin SDK, salteándose las rules).
 * Borrá el `if (bannerProd) console.warn(bannerProd)` de cualquiera de estos
 * cuatro archivos y el test correspondiente se pone en rojo.
 *
 * El orden es la mitad útil del assert: los stubs tiran un marcador
 * (`STUB_FIRESTORE_REACHED` / `STUB_NETWORK_REACHED`) en el primer contacto
 * real, así que si el cartel aparece ANTES en stderr queda probado que se
 * imprime antes de que el script toque un solo dato.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');
const { STUB_FIRESTORE_REACHED, STUB_NETWORK_REACHED } = require('./fixtures/stub_firebase_admin');

/**
 * Corre un script con el stub puesto.
 *
 * `credenciales: true` fija `GOOGLE_APPLICATION_CREDENTIALS`, que es como
 * resuelven el proyecto los entrypoints que llaman a `admin.initializeApp()`
 * pelado. La ruta apunta a `scripts/sa-key.json`, pero el stub intercepta la
 * lectura: el archivo real no se abre nunca (y puede no existir).
 */
function correr(script, args = [], { emulador = false, projectId = 'treino-dev', credenciales = true } = {}) {
  const env = { ...process.env, STUB_PROJECT_ID: projectId };

  if (credenciales) {
    env.GOOGLE_APPLICATION_CREDENTIALS = path.join(SCRIPTS_DIR, 'sa-key.json');
  } else {
    delete env.GOOGLE_APPLICATION_CREDENTIALS;
  }
  delete env.GOOGLE_CLOUD_PROJECT;
  delete env.GCLOUD_PROJECT;

  if (emulador) {
    env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
  } else {
    delete env.FIRESTORE_EMULATOR_HOST;
    delete env.FIREBASE_AUTH_EMULATOR_HOST;
  }

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, path.join(SCRIPTS_DIR, script), ...args],
    { cwd: SCRIPTS_DIR, env, encoding: 'utf8' },
  );
  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  return { stdout: res.stdout, stderr: res.stderr };
}

const CARTEL = /IS PRODUCTION/;

// ── npm run seed:exercises / seed:routines / seed:all ─────────────────────

test('seed_workout_catalog.js (npm run seed:all) escupe el cartel contra treino-dev', () => {
  const { stderr } = correr('seed_workout_catalog.js', ['--all']);
  assert.match(stderr, CARTEL);
  assert.match(stderr, /treino-dev/);
  assert.match(stderr, /#826/);
});

test('seed_workout_catalog.js imprime el cartel ANTES de tocar Firestore', () => {
  const { stderr } = correr('seed_workout_catalog.js', ['--all']);
  const cartel = stderr.search(CARTEL);
  const firestore = stderr.indexOf(STUB_FIRESTORE_REACHED);
  assert.ok(cartel >= 0, 'no salió el cartel');
  assert.ok(firestore >= 0, 'el stub nunca cortó: el test no probó nada');
  assert.ok(cartel < firestore, 'el cartel salió DESPUÉS de la primera escritura');
});

test('seed_workout_catalog.js con el emulador seteado no grita', () => {
  const { stderr } = correr('seed_workout_catalog.js', ['--all'], { emulador: true });
  assert.doesNotMatch(stderr, CARTEL);
});

test('seed_workout_catalog.js contra otro proyecto no grita', () => {
  const { stderr } = correr('seed_workout_catalog.js', ['--all'], { projectId: 'treino-otro-dev' });
  assert.doesNotMatch(stderr, CARTEL);
});

test('seed_workout_catalog.js sin credenciales calla en vez de inventar', () => {
  // `projectIdObjetivo()` devuelve null: el SDK va a resolver el proyecto por
  // un camino que no vemos. Callar es correcto; afirmar "no es producción"
  // sería la misma falsa tranquilidad que motivó #826.
  const { stderr } = correr('seed_workout_catalog.js', ['--all'], { credenciales: false });
  assert.doesNotMatch(stderr, CARTEL);
});

// ── npm run seed:trainers / seed:trainers:clear ───────────────────────────

test('seed_trainer_profiles.js --clear (el que BORRA) escupe el cartel', () => {
  const { stderr } = correr('seed_trainer_profiles.js', ['--clear']);
  assert.match(stderr, CARTEL);
  assert.match(stderr, /treino-dev/);
});

test('seed_trainer_profiles.js --clear imprime el cartel ANTES de borrar', () => {
  const { stderr } = correr('seed_trainer_profiles.js', ['--clear']);
  const cartel = stderr.search(CARTEL);
  const firestore = stderr.indexOf(STUB_FIRESTORE_REACHED);
  assert.ok(cartel >= 0 && firestore >= 0);
  assert.ok(cartel < firestore, 'el cartel salió DESPUÉS del primer delete');
});

test('seed_trainer_profiles.js con el emulador seteado no grita', () => {
  const { stderr } = correr('seed_trainer_profiles.js', ['--clear'], { emulador: true });
  assert.doesNotMatch(stderr, CARTEL);
});

// ── npm run promote:trainer ───────────────────────────────────────────────

test('promote_user_to_trainer.js escupe el cartel contra treino-dev', () => {
  const { stderr } = correr('promote_user_to_trainer.js', ['algun-uid']);
  assert.match(stderr, CARTEL);
});

test('promote_user_to_trainer.js imprime el cartel ANTES de tocar Firestore', () => {
  const { stderr } = correr('promote_user_to_trainer.js', ['algun-uid']);
  const cartel = stderr.search(CARTEL);
  const firestore = stderr.indexOf(STUB_FIRESTORE_REACHED);
  assert.ok(cartel >= 0 && firestore >= 0);
  assert.ok(cartel < firestore);
});

test('promote_user_to_trainer.js con el emulador seteado no grita', () => {
  const { stderr } = correr('promote_user_to_trainer.js', ['algun-uid'], { emulador: true });
  assert.doesNotMatch(stderr, CARTEL);
});

// ── deploy_rules.js (no pasa por npm, y tampoco por .firebaserc) ──────────

test('deploy_rules.js escupe el cartel contra treino-dev', () => {
  const { stderr } = correr('deploy_rules.js');
  assert.match(stderr, CARTEL);
  assert.match(stderr, /treino-dev/);
});

test('deploy_rules.js imprime el cartel ANTES de salir a la red', () => {
  const { stderr } = correr('deploy_rules.js');
  const cartel = stderr.search(CARTEL);
  const red = stderr.indexOf(STUB_NETWORK_REACHED);
  assert.ok(cartel >= 0, 'no salió el cartel');
  assert.ok(red >= 0, 'el stub nunca cortó la red: el test no probó nada');
  assert.ok(cartel < red, 'el cartel salió DESPUÉS del primer request');
});

test('deploy_rules.js grita IGUAL con el emulador seteado', () => {
  // No es un olvido: `deploy_rules.js` pega contra la REST API de Firebase
  // Rules con el service account. `FIRESTORE_EMULATOR_HOST` no lo desvía, ni
  // `.firebaserc`, ni `firebase use`, ni `--project`. Acá no existe el modo
  // emulador, así que apagar el cartel sería mentir. (#826)
  const { stderr } = correr('deploy_rules.js', [], { emulador: true });
  assert.match(stderr, CARTEL);
});
