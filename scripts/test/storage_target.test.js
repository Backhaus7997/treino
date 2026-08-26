/**
 * test/storage_target.test.js
 *
 * Los tests de `lib/storage_target.js` — cómo se resuelve el bucket y cuándo el
 * destino es INCOHERENTE.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#838): el bug no fue que faltara una advertencia, fue que la
 * que había decía lo contrario de la verdad. Así que lo que hay que fijar con
 * tests es la relación entre lo que el módulo REPORTA y lo que el SDK va a
 * hacer: si Firestore está redirigido y Storage no, no puede existir ninguna
 * etiqueta que imprimir.
 *
 * `node:test` y `node:assert`, sin dependencias nuevas — mismo criterio que
 * `dedupe_setlogs_plan.test.js`.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const {
  bucketDeProyecto,
  emuladoresActivos,
  exigirDestinoCoherente,
  planDeStorage,
  resolverBucket,
  resolverProjectId,
} = require('../lib/storage_target');

/** Ruta que no existe: fuerza a que `.firebaserc` NO participe de la decisión. */
const SIN_FIREBASERC = path.join(__dirname, 'fixtures', 'no-existe.firebaserc');
/** El `.firebaserc` real del repo. */
const FIREBASERC_REAL = path.join(__dirname, '..', '..', '.firebaserc');

/** Un env limpio: sin nada de Firebase heredado de la máquina que corre el test. */
const ENV_LIMPIO = Object.freeze({});

// ── resolverProjectId ─────────────────────────────────────────────────────

test('--project= le gana a todo — lo que el operador pidió explícitamente', () => {
  const r = resolverProjectId({
    argv: ['--project=otro-proyecto'],
    env: { GOOGLE_CLOUD_PROJECT: 'treino-dev' },
    rutaFirebaserc: SIN_FIREBASERC,
  });
  assert.strictEqual(r.projectId, 'otro-proyecto');
  assert.strictEqual(r.origen, '--project=');
});

test('sin flag manda GOOGLE_CLOUD_PROJECT — es la que mira el Admin SDK', () => {
  const r = resolverProjectId({
    argv: [],
    env: { GOOGLE_CLOUD_PROJECT: 'treino-otro-dev' },
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(r.projectId, 'treino-otro-dev');
});

test('sin nada cae en .firebaserc, que hoy declara treino-dev', () => {
  // Si algún día se crea un proyecto de dev de verdad (alcance 3 del #826) y
  // cambia el default del .firebaserc, este test cambia con el hecho.
  const r = resolverProjectId({ argv: [], env: ENV_LIMPIO, rutaFirebaserc: FIREBASERC_REAL });
  assert.strictEqual(r.projectId, 'treino-dev');
  assert.strictEqual(r.origen, '.firebaserc');
});

test('sin .firebaserc legible no inventa un proyecto', () => {
  const r = resolverProjectId({ argv: [], env: ENV_LIMPIO, rutaFirebaserc: SIN_FIREBASERC });
  assert.strictEqual(r.projectId, null);
});

// ── resolverBucket ────────────────────────────────────────────────────────

test('el bucket se DERIVA del proyecto — ya no hay literal hardcodeado', () => {
  assert.strictEqual(bucketDeProyecto('treino-dev'), 'treino-dev.firebasestorage.app');
  assert.strictEqual(bucketDeProyecto('treino-otro-dev'), 'treino-otro-dev.firebasestorage.app');
});

test('--bucket= y FIREBASE_STORAGE_BUCKET dan salida sin editar código', () => {
  const porFlag = resolverBucket({ argv: ['--bucket=mi-bucket'], env: ENV_LIMPIO, projectId: 'treino-dev' });
  assert.strictEqual(porFlag.bucket, 'mi-bucket');

  const porEnv = resolverBucket({ argv: [], env: { FIREBASE_STORAGE_BUCKET: 'otro' }, projectId: 'treino-dev' });
  assert.strictEqual(porEnv.bucket, 'otro');
});

test('sin proyecto no hay bucket derivado (y el llamador aborta)', () => {
  assert.strictEqual(bucketDeProyecto(null), null);
  assert.strictEqual(bucketDeProyecto('   '), null);
  assert.strictEqual(resolverBucket({ argv: [], env: ENV_LIMPIO, projectId: null }).bucket, null);
});

// ── emuladoresActivos ─────────────────────────────────────────────────────

test('Storage cuenta como redirigido con CUALQUIERA de las dos variables', () => {
  // firebase-admin normaliza FIREBASE_STORAGE_EMULATOR_HOST a
  // STORAGE_EMULATOR_HOST adentro de admin.storage(). Mirar sólo una daría un
  // falso negativo y abortaría una corrida que estaba perfectamente bien.
  assert.strictEqual(emuladoresActivos({ STORAGE_EMULATOR_HOST: 'http://localhost:9199' }).storage, true);
  assert.strictEqual(emuladoresActivos({ FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' }).storage, true);
  assert.strictEqual(emuladoresActivos(ENV_LIMPIO).storage, false);
});

// ── planDeStorage: la regla que motivó el issue ───────────────────────────

const plan = (env) => planDeStorage({ argv: [], env, rutaFirebaserc: FIREBASERC_REAL });

test('EL CASO DEL #838: Firestore en el emulador y Storage no → incoherente', () => {
  // Esto es exactamente lo que pasaba en extract_exercise_thumbnails.js: el
  // script leía FIRESTORE_EMULATOR_HOST, imprimía "destino: EMULADOR" y subía
  // los .jpg al bucket real.
  const p = plan({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });

  assert.strictEqual(p.coherente, false);
  assert.match(p.motivo, /Firestore apunta al EMULADOR/);
});

test('con el destino incoherente NO existe etiqueta que imprimir', () => {
  // La mitad del arreglo. El bug no fue que faltara un aviso: fue que había una
  // etiqueta para todos los casos y el script elegía la equivocada. Si no hay
  // verdad que contar, `etiquetaDestino` es null y no hay nada que mentir.
  const p = plan({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.strictEqual(p.etiquetaDestino, null);
});

test('el caso simétrico también aborta: Storage local con Firestore en la nube', () => {
  // Escribiría URLs de localhost en el Firestore de producción — que ningún
  // cliente puede abrir, y que quedan ahí hasta que alguien las note.
  const p = plan({ STORAGE_EMULATOR_HOST: 'http://localhost:9199' });
  assert.strictEqual(p.coherente, false);
  assert.match(p.motivo, /Storage apunta al EMULADOR/);
});

test('los dos en el emulador: coherente, etiqueta EMULADOR y sin cartel', () => {
  const p = plan({
    FIRESTORE_EMULATOR_HOST: 'localhost:8080',
    FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199',
  });
  assert.strictEqual(p.coherente, true);
  assert.strictEqual(p.contraEmulador, true);
  assert.match(p.etiquetaDestino, /EMULADOR/);
  assert.strictEqual(p.banner, null, 'contra emulador no se grita — el cartel que grita de más se ignora');
  assert.strictEqual(p.esProduccion, false);
});

test('los dos en la nube: coherente, etiqueta con el bucket real y CARTEL', () => {
  const p = plan(ENV_LIMPIO);
  assert.strictEqual(p.coherente, true);
  assert.strictEqual(p.bucket, 'treino-dev.firebasestorage.app');
  assert.strictEqual(p.etiquetaDestino, 'prod (treino-dev.firebasestorage.app)');
  assert.ok(p.banner, 'treino-dev ES producción (#826) — tiene que salir el cartel');
  assert.match(p.banner, /IS PRODUCTION/);
});

test('contra un proyecto que no es producción no hay cartel', () => {
  // El día que exista un dev de verdad, el cartel se calla solo.
  const p = planDeStorage({
    argv: ['--project=treino-otro-dev'],
    env: ENV_LIMPIO,
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(p.banner, null);
  assert.strictEqual(p.etiquetaDestino, 'prod (treino-otro-dev.firebasestorage.app)');
});

// ── exigirDestinoCoherente: que efectivamente corte ───────────────────────

/** Corre el guard capturando salida y exit code, sin matar el proceso del test. */
function correrGuard(env, argv = []) {
  const stdout = [];
  const stderr = [];
  const codigos = [];
  const plan = exigirDestinoCoherente({
    argv,
    env,
    rutaFirebaserc: FIREBASERC_REAL,
    salida: {
      log: (m) => stdout.push(String(m)),
      warn: (m) => stderr.push(String(m)),
      error: (m) => stderr.push(String(m)),
    },
    morir: (c) => codigos.push(c),
  });
  return { plan, stdout: stdout.join('\n'), stderr: stderr.join('\n'), codigos };
}

test('el guard mata la corrida cuando el destino es incoherente', () => {
  const r = correrGuard({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.deepStrictEqual(r.codigos, [1], 'esperaba exit(1)');
  assert.match(r.stderr, /ABORTADO/);
  assert.doesNotMatch(r.stdout + r.stderr, /EMULADOR \(Firestore \+ Storage\)/,
    'jamás puede decir EMULADOR cuando Storage no está redirigido — ése ES el bug');
});

test('el abort explica que emulator.sh no levanta Storage', () => {
  // Sin ese dato el operador prueba `FIREBASE_STORAGE_EMULATOR_HOST=...`, el
  // emulador no está escuchando en 9199, y se come un ECONNREFUSED opaco.
  const r = correrGuard({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.match(r.stderr, /emulator\.sh NO levanta Storage/);
});

test('el guard deja pasar y grita el cartel cuando el destino es producción', () => {
  const r = correrGuard(ENV_LIMPIO);
  assert.deepStrictEqual(r.codigos, [], 'no tenía que abortar');
  assert.match(r.stderr, /IS PRODUCTION/);
  assert.match(r.stdout, /bucket: treino-dev\.firebasestorage\.app/);
});

test('el guard aborta si no puede resolver el proyecto — no adivina', () => {
  const stderr = [];
  const codigos = [];
  exigirDestinoCoherente({
    argv: [],
    env: ENV_LIMPIO,
    rutaFirebaserc: SIN_FIREBASERC,
    salida: { log: () => {}, warn: () => {}, error: (m) => stderr.push(String(m)) },
    morir: (c) => codigos.push(c),
  });
  assert.deepStrictEqual(codigos, [1]);
  assert.match(stderr.join('\n'), /no pude resolver/);
});
