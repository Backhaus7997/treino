/**
 * test/emulador_namespace.test.js
 *
 * Que el emulador, la app y los scripts hablen del MISMO namespace.
 *
 *   cd scripts && node --test test/emulador_namespace.test.js
 *
 * `PROJECT_ID_EMULADOR` (`lib/target_project.js`) es el id que usan
 * `lib/admin.js` —la semilla y todo script contra el emulador— y
 * `lib/storage_target.js` —los cuatro scripts que suben a Storage—. Pero el
 * emulador no lo lee: lo levanta `emulator.sh` con su propio `--project`, y la
 * app se inicializa con el `projectId` y el `storageBucket` de
 * `lib/firebase_options.dart`. Son tres textos que tienen que decir lo mismo y
 * nada los ataba.
 *
 * En ese hueco vivió el bug que motivó este archivo: con las dos variables de
 * emulador puestas, los scripts de Storage resolvían `demo-treino` (el default
 * de `.firebaserc`) mientras el emulador, la app y la semilla vivían en
 * `treino-dev`. Medido el 2026-10-14: `extract_exercise_thumbnails.js --upload`
 * contra un ejercicio sembrado terminó en «subidos + patcheados: 0 · fallas: 1»
 * con exit 0. Nadie lo veía porque cada lado, mirado solo, estaba bien.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { PROJECT_ID_EMULADOR } = require('../lib/target_project');
const { bucketDeProyecto, planDeStorage } = require('../lib/storage_target');

const EMULATOR_SH = path.join(__dirname, '..', 'emulator.sh');
const FIREBASE_OPTIONS = path.join(__dirname, '..', '..', 'lib', 'firebase_options.dart');
const FIREBASERC_REAL = path.join(__dirname, '..', '..', '.firebaserc');

/**
 * Las líneas de CÓDIGO de emulator.sh que levantan el emulador.
 *
 * Se busca `emulators:start` solo, sin exigir `firebase` adelante. La primera
 * versión de este filtro pedía `firebase\s+emulators:start`, y el control
 * negativo la agarró: reescribir UNA de las dos líneas como
 * `exec "$FIREBASE" emulators:start … --project demo-treino` la sacaba del
 * filtro, la otra seguía matcheando, y el test daba verde con un modo del
 * emulador en otro namespace. Mejor un falso positivo ruidoso (un `echo` que
 * nombre el comando) que ese verde.
 */
function arranquesDelEmulador() {
  return fs
    .readFileSync(EMULATOR_SH, 'utf8')
    .split('\n')
    .filter((l) => !/^\s*#/.test(l) && /\bemulators:start\b/.test(l));
}

test('emulator.sh levanta el emulador con el --project de PROJECT_ID_EMULADOR', () => {
  const arranques = arranquesDelEmulador();
  // Que no encuentre nada que comparar NO puede ser verde.
  assert.ok(arranques.length > 0, 'no encontré ningún `emulators:start` en emulator.sh');

  for (const linea of arranques) {
    const m = linea.match(/--project[=\s]+(\S+)/);
    assert.ok(m, `un emulators:start sin --project resuelve el default de .firebaserc: «${linea.trim()}»`);
    assert.strictEqual(
      m[1],
      PROJECT_ID_EMULADOR,
      `emulator.sh levanta "${m[1]}" y los scripts escriben en "${PROJECT_ID_EMULADOR}": ` +
        'namespaces distintos, y el emulador sólo lo anota en firestore-debug.log',
    );
  }
});

test('la app (firebase_options.dart) vive en ese namespace y en su bucket', () => {
  const dart = fs.readFileSync(FIREBASE_OPTIONS, 'utf8');
  const proyectos = [...dart.matchAll(/projectId:\s*'([^']+)'/g)].map((m) => m[1]);
  const buckets = [...dart.matchAll(/storageBucket:\s*'([^']+)'/g)].map((m) => m[1]);

  assert.ok(proyectos.length > 0, 'no encontré ningún projectId en firebase_options.dart');
  assert.ok(buckets.length > 0, 'no encontré ningún storageBucket en firebase_options.dart');
  for (const p of proyectos) assert.strictEqual(p, PROJECT_ID_EMULADOR, `projectId de la app: ${p}`);
  for (const b of buckets) {
    assert.strictEqual(b, bucketDeProyecto(PROJECT_ID_EMULADOR), `storageBucket de la app: ${b}`);
  }
});

test('con las dos variables, los scripts de Storage escriben en el bucket de la app', () => {
  // El cierre de la cadena: no alcanza con que el id coincida, el bucket que
  // DERIVA `storage_target` tiene que ser el que la app usa contra el emulador
  // de Storage. Si no, los archivos subidos quedan en un bucket que la app no
  // mira — mismo síntoma, otra capa.
  const dart = fs.readFileSync(FIREBASE_OPTIONS, 'utf8');
  const [, bucketDeLaApp] = dart.match(/storageBucket:\s*'([^']+)'/);

  const p = planDeStorage({
    argv: [],
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080', FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' },
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(p.contraEmulador, true);
  assert.strictEqual(p.bucket, bucketDeLaApp);
});
