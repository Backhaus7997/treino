'use strict';

/**
 * test/fixtures/firebase_admin_subpaths.js
 *
 * LA SEGUNDA PUERTA DEL DOBLE: `firebase-admin/app`, `firebase-admin/firestore`,
 * `firebase-admin/storage` — los subpaths modulares del SDK.
 *
 * ─── Por qué existe ─────────────────────────────────────────────────────────
 *
 * `stub_firebase_admin.js` intercepta el specifier EXACTO:
 *
 *     if (request === 'firebase-admin') return adminStub;
 *
 * y el hook ESM hace lo mismo (`specifier === 'firebase-admin'`). Medido antes
 * de este archivo, parado en `scripts/`:
 *
 *     require('firebase-admin')            → stub? true
 *     require('firebase-admin/firestore')  → stub? false   ← getFirestore REAL
 *     require('firebase-admin/app')        → stub? false   ← cert REAL
 *
 * O sea que el día que un script migre a `getFirestore()` —que es el plan de
 * `openspec/changes/firebase-admin-modular/`— el doble deja de verlo.
 *
 * Y NO se rompe con un rojo: se rompe con un VERDE. Los tests de compuerta
 * (`storage_scripts_destination`, `npm_entrypoints_banner`,
 * `backfill_production_banner`, `strip_appointment_reason_gate`) prueban que el
 * guard corta antes de tocar datos afirmando la **AUSENCIA** de
 * `STUB_FIRESTORE_REACHED` / `STUB_STORAGE_REACHED`. Ese marcador también falta
 * cuando el stub nunca se aplicó. Es exactamente el punto ciego del #846, con
 * otro disfraz: allá la intercepción ESM no existía en Node 20, acá no existe
 * para los subpaths.
 *
 * ─── Por qué este archivo y no más líneas en el stub ────────────────────────
 *
 * Porque los NOMBRES que exporta cada subpath los necesitan DOS hilos:
 *
 *   · el principal, para armar el módulo que devuelve `Module._load`;
 *   · el de los hooks ESM, para generar los `export const …` del módulo
 *     sintético — un módulo ESM no puede tener exports nombrados dinámicos, así
 *     que el nombre tiene que estar en el código que se compila.
 *
 * `module.register()` corre los hooks en otro hilo y no comparte `globalThis`,
 * así que el hook no puede leer el objeto ya construido. Si cada lado escribiera
 * su propia lista, esa lista sería una TERCERA cosa que puede driftear — el
 * mismo error que este PR existe para arreglar, un nivel más adentro.
 *
 * La salida: este módulo es data pura, sin efectos. El hilo de los hooks lo
 * requiere y llama a `nombresDeSubpaths()`, que construye el mapa con stubs
 * vacíos SÓLO para enumerar las claves. Nada se ejecuta: las funciones no se
 * llaman, se cuentan.
 *
 * ─── Qué se modela y qué no ─────────────────────────────────────────────────
 *
 * Sólo las tres superficies que `adminStub` ya modela hoy: `app`, `firestore` y
 * `storage`. `auth`, `messaging` y `database` NO se modelan a propósito — el
 * doble namespaced tampoco los tiene, y agregarlos acá los volvería asimétricos.
 *
 * Pero `stub_firebase_admin.js` igual INTERCEPTA esos subpaths, y les devuelve
 * el objeto de `subpathNoModelado()`: cualquier acceso tira un error que dice
 * qué falta y dónde agregarlo. Interceptado y ruidoso. Lo que no puede pasar
 * —nunca— es que el subpath caiga en el SDK real y el test siga en verde.
 */

/**
 * Arma los módulos modulares A PARTIR de las piezas del doble namespaced.
 *
 * Que salgan del mismo objeto no es elegancia: es la propiedad que hace que las
 * dos puertas no puedan contar historias distintas. `getFirestore()` devuelve
 * literalmente lo que devuelve `admin.firestore()`, así que un script migrado y
 * uno sin migrar chocan contra el MISMO `STUB_FIRESTORE_REACHED`.
 *
 * Ojo con el contrato de esta función: **no toca sus argumentos al construir**,
 * sólo adentro de los closures. `nombresDeSubpaths()` depende de eso para poder
 * llamarla con objetos vacíos.
 *
 * @param {object}   adminStub      El doble namespaced (`apps`, `initializeApp`, `credential`, …).
 * @param {Function} firestoreStub  La función-namespace de Firestore (con `.FieldValue` y `.Timestamp`).
 */
function construirSubpaths(adminStub, firestoreStub) {
  return {
    'firebase-admin/app': {
      initializeApp: (...args) => adminStub.initializeApp(...args),
      // `admin.apps` es un array; `getApps()` devuelve EL MISMO, no una copia.
      // `lib/admin.js` usa uno de los dos para no inicializar dos veces cuando
      // `seed_emulator_full.js` requiere `seed_workout_catalog.js`, y durante la
      // migración va a haber archivos de los dos lados en el mismo proceso.
      getApps: () => adminStub.apps,
      getApp: () => adminStub.apps[0],
      cert: (serviceAccount) => adminStub.credential.cert(serviceAccount),
      applicationDefault: () => adminStub.credential.applicationDefault(),
    },

    'firebase-admin/firestore': {
      getFirestore: () => firestoreStub(),
      FieldValue: firestoreStub.FieldValue,
      Timestamp: firestoreStub.Timestamp,
    },

    'firebase-admin/storage': {
      getStorage: () => adminStub.storage(),
    },
  };
}

/**
 * `{ 'firebase-admin/app': ['initializeApp', …], … }` — sólo los NOMBRES.
 *
 * Para el hilo de los hooks ESM, que necesita los identificadores en tiempo de
 * compilación y no puede ver el objeto del hilo principal. Construye el mapa
 * con dobles vacíos: las funciones quedan sin llamar, y lo único que se lee son
 * las claves.
 */
function nombresDeSubpaths() {
  const firestoreVacio = () => {};
  const mapa = construirSubpaths({}, firestoreVacio);
  return Object.fromEntries(Object.entries(mapa).map(([sub, mod]) => [sub, Object.keys(mod)]));
}

module.exports = { construirSubpaths, nombresDeSubpaths };
