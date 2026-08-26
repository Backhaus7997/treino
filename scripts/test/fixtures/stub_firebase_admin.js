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
const fs = require('node:fs');

const STUB_FIRESTORE_REACHED = 'STUB_FIRESTORE_REACHED';
const STUB_STORAGE_REACHED = 'STUB_STORAGE_REACHED';
const STUB_NETWORK_REACHED = 'STUB_NETWORK_REACHED';

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
    bucket() {
      throw new Error(STUB_STORAGE_REACHED);
    },
  };
}

const adminStub = {
  // `seed_workout_catalog.js` consulta `admin.apps.length` para no inicializar
  // dos veces cuando `seed_emulator_full.js` lo requiere. En el módulo real
  // arranca vacío; el stub replica eso y nunca lo llena, así que cada carga en
  // subproceso ve el mismo estado limpio. (#826)
  apps: [],
  initializeApp() {},
  credential: { cert: (serviceAccount) => serviceAccount },
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

module.exports = { STUB_FIRESTORE_REACHED, STUB_STORAGE_REACHED, STUB_NETWORK_REACHED };
