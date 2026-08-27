'use strict';

/**
 * test/fixtures/stub_firebase_admin.js
 *
 * Preload (`node --require`) que le miente a un script de `scripts/` sobre lo
 * que lo conecta con el mundo —`firebase-admin`, `google-auth-library` y
 * `sa-key.json`— para poder CARGARLO de verdad en un test sin tocar ninguna
 * red ni ninguna credencial.
 *
 * Por qué existe: los tests de los módulos de `lib/` prueban funciones puras,
 * pero el único cambio de CONDUCTA de un fix como el #826 o el #838 vive en el
 * CABLEADO — la línea que llama al guard antes de escribir. Borrando esa línea,
 * los tests del módulo siguen todos en verde porque nadie carga el script. Esto
 * lo carga.
 *
 * Por qué un preload y no un mock del require normal: `scripts/node_modules/`
 * tiene el `firebase-admin` REAL, y la resolución de Node lo encuentra antes que
 * cualquier `NODE_PATH`. Interceptar `Module._load` es la única forma de ganarle
 * sin instalar nada ni tocar el árbol de dependencias.
 *
 * El stub NO simula nada: cada superficie tira un marcador en el primer
 * contacto real, a propósito.
 *
 *   `STUB_FIRESTORE_REACHED`  primera lectura/escritura de Firestore
 *   `STUB_STORAGE_REACHED`    primer `.bucket()` de Cloud Storage
 *   `STUB_NETWORK_REACHED`    primer `getClient()` de `google-auth-library`
 *
 * Y uno que NO es un contacto sino una PRUEBA DE VIDA del propio stub:
 *
 *   `STUB_ESM_INTERCEPTED`    el `import firebase-admin` de un `.mjs` cayó acá
 *
 * Esos marcadores son la mitad útil de cada test — si aparecen DESPUÉS del
 * cartel (o no aparecen nunca, porque el guard abortó), queda probado que la
 * salvaguarda actúa ANTES de que el script toque un solo dato.
 *
 * `STUB_PROJECT_ID` decide qué `project_id` devuelve el `sa-key.json` falso,
 * para poder correr el caso "no es producción" sin editar nada.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * ESTE ARCHIVO ES LA UNIÓN DE DOS PRs, Y LAS DOS MITADES SON OBLIGATORIAS.
 *
 * Nació en el #835 (issue #826) y el #838 lo extendió. Ninguna de las dos
 * versiones sueltas sirve para la suite completa:
 *
 *   Del #835 (lo consume `npm_entrypoints_banner.test.js`):
 *     · `googleAuthStub` + `STUB_NETWORK_REACHED`
 *     · la intercepción de `fs.readFileSync` sobre `sa-key.json`
 *     · `apps: []` en el adminStub
 *
 *   Del #838 (lo consume `storage_scripts_destination.test.js`):
 *     · `storageStub` + `STUB_STORAGE_REACHED`
 *
 *   Del #846 (lo consume `strip_appointment_reason_gate.test.js`):
 *     · `register()` + `fixtures/esm_stub_hooks.mjs` — la intercepción ESM
 *     · `credential.applicationDefault` y `firestore.FieldValue`
 *
 * La mitad del #846 hace falta porque `scripts/migrations/*.mjs` son MÓDULOS
 * ESM, y un `import admin from "firebase-admin"` **no pasa por `Module._load`**:
 * medido, el subproceso cargaba el `firebase-admin` REAL y el stub no veía
 * nada. `module.register()` cubre ese camino y CONVIVE con la intercepción de
 * CJS en vez de reemplazarla — los `.mjs` usan `createRequire` para los módulos
 * de `lib/`, o sea que los DOS caminos corren en el mismo proceso.
 *
 * (La primera versión de esa mitad usaba `module.registerHooks()`, que existe
 * recién desde Node 22.15. El job `scripts-test` de CI corre Node 20: ahí el
 * preload moría con `TypeError: registerHooks is not a function` y el
 * subproceso cargaba el `firebase-admin` de verdad, dejando los 42 tests de la
 * compuerta midiendo NADA. `register()` está desde Node 20.6 y sigue en 22 y
 * 26 — un solo camino para todas las versiones que corren esta suite.)
 *
 * Sacar CUALQUIERA de las dos mitades pone en rojo los tests de la otra, y en
 * el caso de la mitad del #835 el rojo es lo de MENOS: sin `googleAuthStub` y
 * sin la intercepción de `readFileSync`, el subproceso de `deploy_rules.js`
 * —que NO pasa por `firebase-admin`, usa `google-auth-library` directo— sale
 * DE VERDAD a `firebaserules.googleapis.com` y deploya el `firestore.rules`
 * del working tree a `treino-dev`, que es producción (#826). En CI no dispara
 * porque ahí no existe la credencial; en la máquina de quien tenga
 * `scripts/sa-key.json` sí. Falla silencioso donde mirás y dispara donde no.
 *
 * O sea: si algún día hay que tocar esto, se AGREGA. No se reemplaza por la
 * versión de ninguna rama.
 * ═══════════════════════════════════════════════════════════════════════════
 */

const Module = require('node:module');
const { register } = require('node:module');
const { pathToFileURL } = require('node:url');
const fs = require('node:fs');

const STUB_FIRESTORE_REACHED = 'STUB_FIRESTORE_REACHED';
const STUB_STORAGE_REACHED = 'STUB_STORAGE_REACHED';
const STUB_NETWORK_REACHED = 'STUB_NETWORK_REACHED';
// #840 — el `storageBucket` que el script le declaro a `initializeApp()`. Va al
// marcador para que el test distinga "aterrizo en el bucket de demo" de
// "aterrizo en el REAL": sin el nombre, las dos cosas se ven identicas.
let bucketDeclarado = null;
// Prueba POSITIVA de que el import ESM cayó en el stub. Lo escribe el módulo
// sintético de `esm_stub_hooks.mjs` por stderr apenas se evalúa. (#846)
const STUB_ESM_INTERCEPTED = 'STUB_ESM_INTERCEPTED';

function firestoreStub() {
  return {
    collection() {
      throw new Error(STUB_FIRESTORE_REACHED);
    },
    batch() {
      throw new Error(STUB_FIRESTORE_REACHED);
    },
  };
}

function storageStub() {
  return {
    bucket(nombre) {
      throw new Error(
        `${STUB_STORAGE_REACHED} bucket=${nombre || bucketDeclarado || '(sin nombre)'}`
      );
    },
  };
}

// `admin.firestore` es función Y namespace. Los `.mjs` de `migrations/` usan
// `admin.firestore.FieldValue.delete()` / `.arrayUnion()` para armar el update,
// pero eso pasa DESPUÉS del primer `.collection()`, que tira el marcador. Están
// acá para que un cambio de orden falle con el marcador y no con un TypeError
// que no se entiende. (#846)
firestoreStub.FieldValue = {
  delete: () => ({ __stub: 'delete' }),
  arrayUnion: (...v) => ({ __stub: 'arrayUnion', v }),
};

const adminStub = {
  // Firma del stub. La usa `esm_stub_interception.test.js` para distinguir
  // "cargué el stub" de "cargué el `firebase-admin` real", que es la diferencia
  // que la suite dejó de ver cuando la intercepción ESM se rompió en CI. (#846)
  __stubDeTest: true,
  // `seed_workout_catalog.js` consulta `admin.apps.length` para no inicializar
  // dos veces cuando `seed_emulator_full.js` lo requiere. En el módulo real
  // arranca vacío; el stub replica eso y nunca lo llena, así que cada carga en
  // subproceso ve el mismo estado limpio. (#826)
  apps: [],
  // #840 — el stub recuerda el `storageBucket` que le declararon, para que los
  // tests puedan distinguir "aterrizo en el bucket de demo" de "aterrizo en el
  // real". Sin esto, `storage_scripts_destination.test.js` no puede probar que
  // el default `demo-treino` efectivamente desvia el destino.
  initializeApp(opciones) {
    if (opciones && typeof opciones.storageBucket === 'string' && opciones.storageBucket) {
      bucketDeclarado = opciones.storageBucket;
    }
  },
  // `applicationDefault` es la que usan los `.mjs` de `migrations/`: no lee
  // nada, sólo tiene que existir para llegar al `initializeApp()`. (#846)
  credential: {
    cert: (serviceAccount) => serviceAccount,
    applicationDefault: () => ({ __stub: 'applicationDefault' }),
  },
  firestore: firestoreStub,
  storage: storageStub,
};

/**
 * `deploy_rules.js` no pasa por `firebase-admin`: usa `google-auth-library` y
 * pega directo contra la REST API de Firebase Rules. Sin este stub el test
 * saldría A LA RED — y no a leer: `deploy_rules.js` hace POST de un ruleset y
 * PATCH del release `cloud.firestore`. `getClient()` tira en vez de devolver un
 * cliente, así que el marcador prueba lo mismo que `STUB_FIRESTORE_REACHED`
 * prueba para los backfills: si aparece DESPUÉS del cartel, el cartel salió
 * primero. (#826)
 */
const googleAuthStub = {
  GoogleAuth: class {
    async getClient() {
      throw new Error(STUB_NETWORK_REACHED);
    }
  },
};

const cargaOriginal = Module._load;

Module._load = function cargaInterceptada(request, parent, isMain) {
  if (request === 'firebase-admin') return adminStub;
  if (request === 'google-auth-library') return googleAuthStub;

  // El nombre real del key (#826): `sa-key.json`, no
  // `treino-dev-service-account.json`. Varios scripts lo hacen `require`
  // directo, así que devolverlo acá evita tener que crear un archivo de
  // credenciales —aunque sea falso— en el árbol del repo.
  if (request.endsWith('sa-key.json')) {
    return { project_id: process.env.STUB_PROJECT_ID || 'treino-dev' };
  }

  return cargaOriginal.apply(this, arguments);
};

// `deploy_rules.js` NO hace `require` del key: lo lee con `fs.readFileSync`.
// Interceptar la lectura (en vez de escribir un `sa-key.json` de mentira en
// `scripts/`) es lo único seguro: ese archivo es gitignored justamente porque
// puede existir de verdad en la máquina de quien corre los tests, y un test
// jamás puede pisarlo. (#826)
const readFileSyncOriginal = fs.readFileSync;
fs.readFileSync = function lecturaInterceptada(ruta, ...resto) {
  if (typeof ruta === 'string' && ruta.endsWith('sa-key.json')) {
    return JSON.stringify({ project_id: process.env.STUB_PROJECT_ID || 'treino-dev' });
  }
  return readFileSyncOriginal.call(this, ruta, ...resto);
};

// ─── La mitad ESM (#846) ────────────────────────────────────────────────────
//
// `Module._load` cubre `require()`. Los scripts de `scripts/migrations/` son
// `.mjs`, y su `import admin from "firebase-admin"` se resuelve por el loader
// de ESM, que NO pasa por ahí — medido: sin esto el subproceso carga el
// `firebase-admin` de verdad.
//
// Los hooks viven en `esm_stub_hooks.mjs` porque `register()` los corre en otro
// hilo y exige un módulo aparte. El `source` que devuelven, en cambio, se
// evalúa en ESTE hilo: por eso el módulo sintético puede agarrar por
// `globalThis` el MISMO `adminStub` que ve el lado CJS. Un `.mjs` mezcla los
// dos caminos (`createRequire` para `lib/`, `import` para `firebase-admin`) y
// los dos tienen que contar la misma historia.
globalThis.__STUB_FIREBASE_ADMIN__ = adminStub;

// Si este Node no puede interceptar el import ESM, el preload MUERE acá, y el
// error dice por qué. NO se sigue de largo con la mitad CJS puesta.
//
// Es la lección del rojo de CI. `registerHooks` (Node 22.15+) no existe en el
// Node 20 del job, así que el preload tiraba `TypeError` y se llevaba puesto
// cada subproceso — eso fue ruidoso y por eso se vio. Lo que NO se habría visto
// es el modo de al lado: que la intercepción de CJS ande y la de ESM no. Ahí
// los tests de compuerta —que prueban la AUSENCIA de `STUB_FIRESTORE_REACHED`—
// quedan en verde midiendo el `firebase-admin` REAL, porque el marcador falta
// tanto cuando la compuerta frenó como cuando el stub nunca existió.
//
// Contra ese modo hay DOS defensas y las dos son obligatorias: este throw, y el
// marcador `STUB_ESM_INTERCEPTED` que los tests exigen en cada corrida. Un stub
// que no puede interceptar tiene que ser un ERROR RUIDOSO, nunca un test vacuo.
if (typeof register !== 'function') {
  throw new Error(
    `stub_firebase_admin: este Node (${process.version}) no tiene module.register() ` +
      '(hace falta >= 20.6). Sin él, el `import` de un .mjs carga el firebase-admin ' +
      'REAL y los tests de compuerta dejan de medir. Actualizá Node en vez de ' +
      'ignorar esto.',
  );
}

// Node 26 marca `register()` como deprecada en favor de `registerHooks()`, y
// avisa por stderr. Se queda `register()` igual: es la ÚNICA de las dos que
// existe en Node 20, que es la versión de CI, y un solo camino para todas las
// versiones vale más que ahorrarse un warning. El día que el piso de Node del
// repo suba a >= 22.15 en todos lados, esto pasa a `registerHooks(hooks)` con
// los MISMOS hooks de `esm_stub_hooks.mjs` — y `STUB_ESM_INTERCEPTED` va a ser
// la prueba de que esa migración no rompió nada.
register('./esm_stub_hooks.mjs', pathToFileURL(__filename));

module.exports = {
  STUB_FIRESTORE_REACHED,
  STUB_STORAGE_REACHED,
  STUB_NETWORK_REACHED,
  STUB_ESM_INTERCEPTED,
};
