'use strict';

/**
 * test/subpath_stub_interception.test.js
 *
 * El test que custodia AL HARNESS para la SEGUNDA puerta del doble: los
 * subpaths modulares de `firebase-admin`.
 *
 * ─── Por qué existe ─────────────────────────────────────────────────────────
 *
 * Es el gemelo de `esm_stub_interception.test.js`, y nace del mismo punto ciego
 * por tercera vez. Los tests de compuerta de este directorio miden por
 * AUSENCIA: la prueba de que el guard frenó una escritura es que
 * `STUB_FIRESTORE_REACHED` / `STUB_STORAGE_REACHED` NO aparecen. Esa forma de
 * medir no distingue "el guard frenó" de "el doble nunca se aplicó".
 *
 * Ya se cobró dos rondas:
 *
 *   #838/#835 → un test decía SUPERSET y era subset.
 *   #846      → `registerHooks()` no existe en el Node 20 de CI, el subproceso
 *               cargaba el `firebase-admin` REAL y 42 tests medían nada.
 *
 * Y estaba por cobrarse una tercera. Medido antes de este PR, parado en
 * `scripts/`, con el preload puesto:
 *
 *     require('firebase-admin')            → stub? true
 *     require('firebase-admin/firestore')  → stub? FALSE  ← getFirestore REAL
 *     require('firebase-admin/app')        → stub? FALSE  ← cert REAL
 *
 * `stub_firebase_admin.js` matcheaba el specifier EXACTO. O sea que el primer
 * script que migrara a `getFirestore()` —lo que propone
 * `openspec/changes/firebase-admin-modular/`— dejaba su test de compuerta en
 * VERDE con el SDK real cargado. No hay rojo que avise: el verde ES la falla.
 *
 * ─── Qué mide ───────────────────────────────────────────────────────────────
 *
 * `fixtures/probe_admin_subpath_import.mjs` importa los subpaths por los dos
 * caminos que usa un `.mjs` real de `migrations/` —`import` y `createRequire`—
 * y contesta si lo que le llegó tira el marcador del doble. Con el preload
 * puesto, los dos tienen que decir STUB; y el CONTROL NEGATIVO —la misma sonda
 * sin preload— tiene que decir cualquier otra cosa. Sin ese control, "dice
 * STUB" no probaría nada: podría decirlo siempre.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');
const SONDA = path.join(__dirname, 'fixtures', 'probe_admin_subpath_import.mjs');
const { STUB_SUBPATH_INTERCEPTED } = require('./fixtures/stub_firebase_admin');

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

test('el `import` ESM de `firebase-admin/firestore` cae en el doble', () => {
  const r = correrSonda({ conPreload: true });

  assert.strictEqual(r.code, 0, `la sonda no corrió: ${r.stderr}`);
  assert.match(
    r.stdout,
    /ESM_FIRESTORE=STUB/,
    'un `import { getFirestore } from "firebase-admin/firestore"` cargó el módulo REAL. ' +
      'Todo test de compuerta sobre un script migrado pasa a medir nada.',
  );
});

test('el `import` ESM de `firebase-admin/app` cae en el doble', () => {
  const r = correrSonda({ conPreload: true });

  // `app` es el subpath de `cert()` y `getApps()`, o sea por donde va a pasar
  // `lib/admin.js` cuando se migre: la única puerta de inicialización (#834).
  assert.match(r.stdout, /ESM_APP=STUB/, 'el `cert` que llegó es el REAL, no el del doble');
});

test('el `require` CJS de un subpath también cae en el doble', () => {
  const r = correrSonda({ conPreload: true });

  // Las dos mitades tienen que convivir, igual que para el specifier pelado: un
  // `.mjs` de `migrations/` usa `createRequire` para `lib/` e `import` para el
  // SDK. Si una tapa a la otra, el proceso ve dos `firebase-admin` distintos.
  assert.match(
    r.stdout,
    /CJS_FIRESTORE=STUB/,
    'el `require("firebase-admin/firestore")` cargó el módulo REAL',
  );
});

test('la intercepción se ANUNCIA: el marcador es la prueba positiva', () => {
  const r = correrSonda({ conPreload: true });

  // Es lo único que distingue "el guard frenó el write" de "el doble no vio
  // este módulo". Misma función que `STUB_ESM_INTERCEPTED` para el #846.
  assert.ok(
    r.stderr.includes(STUB_SUBPATH_INTERCEPTED),
    `sin \`${STUB_SUBPATH_INTERCEPTED}\` no hay forma de saber si el doble actuó sobre el subpath`,
  );
});

test('CONTROL NEGATIVO: sin el preload, ni el doble ni el marcador aparecen', () => {
  const r = correrSonda({ conPreload: false });

  // Sin preload la sonda carga el `firebase-admin` de verdad desde
  // `scripts/node_modules`. Lo que NO puede pasar es que diga STUB: si lo
  // dijera, decir STUB no probaría nada.
  assert.doesNotMatch(
    r.stdout,
    /ESM_FIRESTORE=STUB/,
    'la sonda dice STUB sin preload: entonces decir STUB no discrimina nada',
  );
  assert.ok(
    !r.stderr.includes(STUB_SUBPATH_INTERCEPTED),
    'el marcador aparece sin preload: no discrimina nada',
  );
});

test('un subpath que el doble NO modela se intercepta igual, y grita', () => {
  // La regla del cableado es `startsWith('firebase-admin/')`, sin allowlist.
  // `auth` no está modelado a propósito (el doble namespaced tampoco lo tiene),
  // pero tiene que caer acá igual: un subpath que se escapa al SDK real es
  // exactamente el modo de falla silencioso que este archivo existe para cerrar.
  const res = spawnSync(
    process.execPath,
    [
      '--require',
      STUB,
      '-e',
      "const m = require('firebase-admin/auth');" +
        'try { m.getAuth(); console.log("SIN_ERROR"); }' +
        'catch (e) { console.log(e.message.includes("STUB_SUBPATH_NO_MODELADO") ? "GRITA" : "OTRO:" + e.message); }',
    ],
    { cwd: SCRIPTS_DIR, env: { ...process.env }, encoding: 'utf8' },
  );

  assert.match(
    res.stdout,
    /GRITA/,
    'un subpath no modelado no gritó: o se fue al SDK real, o devolvió algo usable. ' +
      `Las dos cosas son el bug. Salida: ${res.stdout}${res.stderr}`,
  );
});
