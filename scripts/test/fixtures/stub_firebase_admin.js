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

const STUB_FIRESTORE_REACHED = 'STUB_FIRESTORE_REACHED';

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
  initializeApp() {},
  credential: { cert: (serviceAccount) => serviceAccount },
  firestore: firestoreStub,
};

const cargaOriginal = Module._load;

Module._load = function cargaInterceptada(request, parent, isMain) {
  if (request === 'firebase-admin') return adminStub;

  // El nombre real del key (#826): `sa-key.json`, no
  // `treino-dev-service-account.json`. Los backfills lo hacen `require`
  // directo, así que devolverlo acá evita tener que crear un archivo de
  // credenciales —aunque sea falso— en el árbol del repo.
  if (request.endsWith('sa-key.json')) {
    return { project_id: process.env.STUB_PROJECT_ID || 'treino-dev' };
  }

  return cargaOriginal.apply(this, arguments);
};

module.exports = { STUB_FIRESTORE_REACHED };
