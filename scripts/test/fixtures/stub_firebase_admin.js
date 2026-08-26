'use strict';

/**
 * test/fixtures/stub_firebase_admin.js
 *
 * Preload (`node --require`) que le miente a un script de `scripts/` sobre dos
 * cosas —`firebase-admin` y `sa-key.json`— para poder CARGARLO de verdad en un
 * test sin tocar ninguna red ni ninguna credencial.
 *
 * Por qué existe (#826): los tests de `lib/firebase_projects.js` prueban el
 * módulo puro, pero el único cambio de CONDUCTA del fix vive en el cableado —
 * las dos líneas `if (banner) console.warn(banner)` de `backfill_gym_ids.js` y
 * `backfill_gym_names.js`. Borrándolas, los tests del módulo seguían todos en
 * verde: nadie cargaba los backfills. Esto los carga.
 *
 * Por qué un preload y no un mock del require normal: `scripts/node_modules/`
 * tiene el `firebase-admin` REAL, y la resolución de Node lo encuentra antes
 * que cualquier `NODE_PATH`. Interceptar `Module._load` es la única forma de
 * ganarle sin instalar nada ni tocar el árbol de dependencias.
 *
 * El stub NO simula Firestore: la primera lectura tira `STUB_FIRESTORE_REACHED`
 * a propósito. Ese marcador es la mitad útil del test — si aparece DESPUÉS del
 * cartel en stderr, queda probado que el cartel se imprime ANTES de que el
 * script toque un solo dato.
 *
 * `STUB_PROJECT_ID` decide qué `project_id` devuelve el `sa-key.json` falso,
 * para poder correr el caso "no es producción" sin editar nada.
 */

const Module = require('node:module');
const fs = require('node:fs');

const STUB_FIRESTORE_REACHED = 'STUB_FIRESTORE_REACHED';
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

const adminStub = {
  // `seed_workout_catalog.js` consulta `admin.apps.length` para no inicializar
  // dos veces cuando `seed_emulator_full.js` lo requiere. En el módulo real
  // arranca vacío; el stub replica eso y nunca lo llena, así que cada carga en
  // subproceso ve el mismo estado limpio.
  apps: [],
  initializeApp() {},
  credential: { cert: (serviceAccount) => serviceAccount },
  firestore: firestoreStub,
};

/**
 * `deploy_rules.js` no pasa por `firebase-admin`: usa `google-auth-library` y
 * pega directo contra la REST API de Firebase Rules. Sin este stub el test
 * saldría A LA RED. `getClient()` tira en vez de devolver un cliente, así que
 * el marcador prueba lo mismo que `STUB_FIRESTORE_REACHED` prueba para los
 * backfills: si aparece DESPUÉS del cartel, el cartel salió primero. (#826)
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
  // `treino-dev-service-account.json`. Los backfills lo hacen `require`
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
// jamás puede pisarlo.
const readFileSyncOriginal = fs.readFileSync;
fs.readFileSync = function lecturaInterceptada(ruta, ...resto) {
  if (typeof ruta === 'string' && ruta.endsWith('sa-key.json')) {
    return JSON.stringify({ project_id: process.env.STUB_PROJECT_ID || 'treino-dev' });
  }
  return readFileSyncOriginal.call(this, ruta, ...resto);
};

module.exports = { STUB_FIRESTORE_REACHED, STUB_NETWORK_REACHED };
