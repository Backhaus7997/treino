'use strict';

/**
 * test/esm_stub_interception.test.js
 *
 * El test que custodia AL HARNESS, no a un script.
 *
 * ─── Por qué existe (#846) ──────────────────────────────────────────────────
 *
 * `strip_appointment_reason_gate.test.js` mide la compuerta de escritura por
 * AUSENCIA: en los 21 casos que apuntan a producción, la prueba de que la
 * compuerta frenó es que `STUB_FIRESTORE_REACHED` NO aparece.
 *
 * Esa forma de medir tiene un punto ciego, y se cobró una ronda entera: el
 * marcador tampoco aparece cuando **el stub nunca se aplicó**. La primera
 * versión de la intercepción ESM usaba `module.registerHooks()`, que existe
 * desde Node 22.15. El job `scripts-test` de CI corre Node 20, así que ahí el
 * preload reventaba, el subproceso cargaba el `firebase-admin` REAL y los 42
 * tests de la matriz pasaban a medir NADA. Verde en la máquina del que lo
 * escribió, decorativo donde importaba.
 *
 * La lección no es "usá otra API": es que un harness que no puede interceptar
 * tiene que GRITAR, no degradarse a un test vacuo. Este archivo es el grito.
 *
 * ─── Qué mide ───────────────────────────────────────────────────────────────
 *
 * `fixtures/probe_admin_import.mjs` importa `firebase-admin` por los dos
 * caminos que usa un `.mjs` real de `migrations/` —`import` y `createRequire`—
 * e informa cuál de los dos módulos le llegó. Con el preload puesto los dos
 * tienen que decir STUB; y el CONTROL NEGATIVO —la misma sonda sin preload—
 * tiene que decir cualquier otra cosa. Sin ese control, "dice STUB" no probaría
 * nada: podría decirlo siempre.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');
const SONDA = path.join(__dirname, 'fixtures', 'probe_admin_import.mjs');
const { STUB_ESM_INTERCEPTED } = require('./fixtures/stub_firebase_admin');

function correrSonda({ conPreload }) {
  const args = conPreload ? ['--require', STUB, SONDA] : [SONDA];
  const res = spawnSync(process.execPath, args, {
    cwd: SCRIPTS_DIR,
    env: { ...process.env },
    encoding: 'utf8',
  });
  assert.strictEqual(res.error, undefined, `no pude ejecutar la sonda: ${res.error}`);
  return { stdout: res.stdout, stderr: res.stderr, code: res.status };
}

test('con el preload puesto, el `import` ESM de firebase-admin cae en el stub', () => {
  const r = correrSonda({ conPreload: true });

  assert.strictEqual(r.code, 0, `la sonda no corrió: ${r.stderr}`);
  assert.match(
    r.stdout,
    /ESM=STUB/,
    'el `import firebase-admin` de un .mjs cargó el módulo REAL: la intercepción ESM ' +
      'no se aplicó y TODA la matriz de la compuerta pasa a medir nada',
  );
});

test('el mismo preload sigue cubriendo el camino CJS (`createRequire`)', () => {
  const r = correrSonda({ conPreload: true });

  // Las dos mitades tienen que convivir: un `.mjs` de `migrations/` usa
  // `createRequire` para los módulos de `lib/` y `import` para `firebase-admin`.
  // Si una tapa a la otra, el proceso ve dos `firebase-admin` distintos.
  assert.match(r.stdout, /CJS=STUB/, 'el `require` de firebase-admin cargó el módulo REAL');
});

test('la intercepción se ANUNCIA: el marcador es la prueba positiva', () => {
  const r = correrSonda({ conPreload: true });

  // Este marcador es lo que los tests de compuerta exigen en cada corrida. Su
  // presencia es lo único que distingue "la compuerta frenó el write" de "el
  // stub no se aplicó y no se frenó nada".
  assert.ok(
    r.stderr.includes(STUB_ESM_INTERCEPTED),
    `sin \`${STUB_ESM_INTERCEPTED}\` no hay forma de saber si el stub actuó`,
  );
});

test('CONTROL NEGATIVO: sin el preload, ni el stub ni el marcador aparecen', () => {
  const r = correrSonda({ conPreload: false });

  // Sin `scripts/node_modules` la sonda ni siquiera arranca (MODULE_NOT_FOUND);
  // con él, importa el `firebase-admin` de verdad. Los dos desenlaces sirven:
  // lo que NO puede pasar es que diga STUB.
  assert.doesNotMatch(
    r.stdout,
    /ESM=STUB/,
    'la sonda dice STUB sin preload: entonces decir STUB no prueba nada',
  );
  assert.ok(
    !r.stderr.includes(STUB_ESM_INTERCEPTED),
    'el marcador aparece sin preload: no discrimina nada',
  );
});
