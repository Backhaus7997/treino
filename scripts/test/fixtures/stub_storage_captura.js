'use strict';

/**
 * test/fixtures/stub_storage_captura.js
 *
 * Preload (`node --require`) que COMPONE `stub_firebase_admin.js` —lo carga
 * primero, entero— y encima deja que la SUBIDA pase, para poder leer la URL
 * que el script estampa.
 *
 * Por qué un archivo aparte y no un modo del stub base: el base no simula nada
 * a propósito —cada superficie tira un marcador en el primer contacto— y las
 * suites que lo usan miden justamente eso: SI el script llega a Storage, y
 * contra qué bucket. Éste contesta la pregunta de después: QUÉ URL escribió, y
 * si apunta a donde subió el archivo. El base dice "si hay que tocarlo, se
 * AGREGA"; acá no se toca.
 *
 * Cada intercepción imprime una línea por stdout, `<MARCADOR> <json>`:
 *
 *   CAPTURA_SUBIDA     `bucket.upload()` — bucket, destino y token de descarga
 *   CAPTURA_UPDATE     `doc.update()` — documento y campos
 *   CAPTURA_DESCARGA   `execFileSync('curl', …)` — NO sale a la red: escribe un
 *                      MP4 falso donde el script lo espera
 *   CAPTURA_ESCRITURA  `fs.writeFileSync` adentro del repo — NO escribe ahí:
 *                      vuelca a un temporal y dice cuál
 *
 * La última es la que hace seguro correr estos scripts en un test: dos de ellos
 * escriben archivos VERSIONADOS (`enriched-catalog.json`,
 * `catalog-fill-empty.csv`). Ningún test puede ensuciarlos, tampoco un control
 * negativo que saque un guard.
 *
 * `CAPTURA_EJERCICIOS` (ids separados por coma) es lo que devuelve
 * `collection('exercises').get()`. Todo `doc(id).get()` existe y viene vacío.
 *
 * `CAPTURA_DRIVE_VIDEOS` (un array JSON) es lo que devuelve el `require` de
 * `docs/video-catalog-audit/drive-videos.json`. Ese archivo es un listado local
 * de Drive y está en `.gitignore`: sin esto `apply_catalog_video_fill.js` no
 * pasa de su primera línea en ningún clon limpio, CI incluido.
 */

const Module = require('node:module');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Primero el base: credencial falsa, `firebase-admin/*` interceptado, sin red.
require('./stub_firebase_admin');

const adminStub = globalThis.__STUB_FIREBASE_ADMIN__;
if (!adminStub || !adminStub.__stubDeTest) {
  throw new Error('stub_storage_captura: no encontré el adminStub del stub base');
}

/** La raíz del repo (o del worktree): `scripts/test/fixtures/../../..`. */
const REPO = path.resolve(__dirname, '..', '..', '..');

const escribirOriginal = fs.writeFileSync;

function emitir(marcador, datos) {
  process.stdout.write(`${marcador} ${JSON.stringify(datos)}\n`);
}

// ─── Storage: `.bucket()` devuelve un bucket que acepta la subida ────────────

let bucketDeclarado = null;
const inicializarOriginal = adminStub.initializeApp;
adminStub.initializeApp = function inicializarYRecordar(opciones, ...resto) {
  if (opciones && typeof opciones.storageBucket === 'string') bucketDeclarado = opciones.storageBucket;
  return inicializarOriginal.call(this, opciones, ...resto);
};

adminStub.storage = () => ({
  bucket(nombre) {
    const bucket = nombre || bucketDeclarado;
    return {
      name: bucket,
      async upload(_local, opciones = {}) {
        const meta = (opciones.metadata && opciones.metadata.metadata) || {};
        emitir('CAPTURA_SUBIDA', {
          bucket,
          destino: opciones.destination,
          token: meta.firebaseStorageDownloadTokens,
        });
        return [{ name: opciones.destination }];
      },
    };
  },
});

// ─── Firestore: lo justo para que los tres que patchean lleguen al update ────

function docRef(coleccion, id) {
  const ref = {
    id,
    async get() {
      return { exists: true, id, ref, data: () => ({}) };
    },
    async update(campos) {
      emitir('CAPTURA_UPDATE', { doc: `${coleccion}/${id}`, campos });
    },
  };
  return ref;
}

const firestoreDoble = {
  collection(coleccion) {
    return {
      doc: (id) => docRef(coleccion, id),
      async get() {
        const ids = String(process.env.CAPTURA_EJERCICIOS || '').split(',').filter(Boolean);
        return { docs: ids.map((id) => ({ id, data: () => ({}), ref: docRef(coleccion, id) })) };
      },
    };
  },
};

// `getFirestore` del base devuelve un doble que tira en `.collection()`, y lo
// arma por clausura: no se puede reemplazar desde afuera. Se intercepta el
// subpath ANTES de que llegue al base; todo lo demás sigue su camino.
const cargaDelBase = Module._load;
Module._load = function cargaConCaptura(request, ...resto) {
  if (request === 'firebase-admin/firestore') {
    return { getFirestore: () => firestoreDoble };
  }
  if (typeof request === 'string' && request.endsWith('drive-videos.json') && process.env.CAPTURA_DRIVE_VIDEOS) {
    return JSON.parse(process.env.CAPTURA_DRIVE_VIDEOS);
  }
  return cargaDelBase.call(this, request, ...resto);
};

// ─── Red y disco ─────────────────────────────────────────────────────────────

// Los scripts hacen `const { execFileSync } = require('child_process')` al
// cargarse, o sea DESPUÉS de este preload: toman esta versión.
const execFileSyncOriginal = childProcess.execFileSync;
childProcess.execFileSync = function execFileSyncSinRed(comando, args = [], ...resto) {
  if (comando !== 'curl') return execFileSyncOriginal.call(this, comando, args, ...resto);
  const salida = args[args.indexOf('-o') + 1];
  // Lo mínimo que los scripts validan: más de 10 KB y `ftyp` en los bytes 4-8.
  const mp4 = Buffer.alloc(20000);
  mp4.write('ftyp', 4, 'ascii');
  escribirOriginal(salida, mp4);
  emitir('CAPTURA_DESCARGA', { url: args[args.length - 1] });
  return Buffer.alloc(0);
};

fs.writeFileSync = function escrituraCapturada(ruta, datos, ...resto) {
  const absoluta = typeof ruta === 'string' ? path.resolve(ruta) : null;
  if (absoluta && absoluta.startsWith(REPO + path.sep)) {
    const volcado = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'captura-')), path.basename(absoluta));
    escribirOriginal.call(this, volcado, datos, ...resto);
    emitir('CAPTURA_ESCRITURA', { ruta: path.relative(REPO, absoluta), volcado });
    return undefined;
  }
  return escribirOriginal.call(this, ruta, datos, ...resto);
};
