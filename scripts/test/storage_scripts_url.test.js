/**
 * test/storage_scripts_url.test.js
 *
 * QUÉ URL ESTAMPAN los cuatro scripts que suben a Storage, cargándolos de
 * verdad: cada test levanta el script REAL en un subproceso con
 * `fixtures/stub_storage_captura.js`, que deja pasar la subida y cuenta qué
 * subió, qué escribió en Firestore y qué habría escrito en disco. Cero red,
 * cero archivos versionados tocados.
 *
 *   node --test scripts/test/storage_scripts_url.test.js
 *
 * Por qué existen: hasta este cambio los cuatro armaban la URL con el host de
 * producción fijo, también contra el emulador. El archivo iba al emulador y la
 * URL a Google. Medido (2026-10-14): `CachedNetworkImage` recibe 404 o 403 de
 * PRODUCCIÓN y `ExerciseAssetImage` cae en silencio al asset local — la corrida
 * "anda" y muestra otra imagen. Detalle en `lib/url_de_descarga.js`.
 *
 * `storage_scripts_destination.test.js` prueba CONTRA QUÉ BUCKET van; éste, que
 * la URL que queda escrita apunte al MISMO objeto, en el MISMO host.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { RUTA_CREDENCIAL_FALSA } = require('./fixtures/stub_firebase_admin');
const { HOST_DE_LA_NUBE } = require('../lib/url_de_descarga');

const SCRIPTS_DIR = path.join(__dirname, '..');
const CAPTURA = path.join(__dirname, 'fixtures', 'stub_storage_captura.js');
const CATALOGO = 'docs/video-catalog-audit/enriched-catalog.json';

/** Emulador en puertos que NO son los de firebase.json: el host sale del ambiente. */
const EMULADOR = { FIRESTORE_EMULATOR_HOST: 'localhost:18080', FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:19199' };
const HOST_EMULADOR = 'http://127.0.0.1:19199';
/** Nube SIN producción: ni el proyecto ni el bucket están en la lista del #826. */
const NUBE_DE_PRUEBA = ['--project=treino-otro-dev', '--bucket=bucket-de-prueba'];

/** Un `--thumbs=` con un `.jpg`: el contenido no importa, la subida es del doble. */
const THUMBS = fs.mkdtempSync(path.join(os.tmpdir(), 'treino-url-'));
fs.writeFileSync(path.join(THUMBS, 'ejercicio-de-prueba.jpg'), 'jpg');

/**
 * Los tres que estampan la URL en Firestore. `apply_catalog_video_fill.js`
 * necesita un ejercicio y un clip que matcheen por movimiento + equipo:
 * `bench-press-barbell` ↔ `female-barbell-bench-press-side.mp4` de la carpeta
 * Barbell (ver `exerciseKey` / `videoKey` del script).
 */
const ESTAMPADORES = [
  {
    script: 'extract_exercise_thumbnails.js',
    argv: ['--upload', `--thumbs=${THUMBS}`],
    campo: 'thumbnailUrl',
  },
  {
    script: 'apply_catalog_video_fill.js',
    argv: ['--add-safe', '--apply'],
    campo: 'videoUrl',
    env: {
      CAPTURA_EJERCICIOS: 'bench-press-barbell',
      CAPTURA_DRIVE_VIDEOS: JSON.stringify([
        { id: 'drive-1', folder: 'Barbell', title: 'female-barbell-bench-press-side.mp4' },
      ]),
    },
  },
  { script: 'upload_drive_exercise_videos.js', argv: ['--limit=1'], campo: 'videoUrl' },
];

function correr(script, argv, extraEnv = {}) {
  // Misma limpieza que `storage_scripts_destination.test.js`, por los mismos
  // motivos: una variable heredada de la máquina cambiaría lo que se mide.
  const env = { ...process.env, TREINO_SA_KEY: RUTA_CREDENCIAL_FALSA };
  for (const v of [
    'FIRESTORE_EMULATOR_HOST',
    'STORAGE_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
    'GOOGLE_CLOUD_PROJECT',
    'GCLOUD_PROJECT',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'FIREBASE_STORAGE_BUCKET',
    'STUB_PROJECT_ID',
    'CAPTURA_EJERCICIOS',
    'CAPTURA_DRIVE_VIDEOS',
  ]) {
    delete env[v];
  }
  Object.assign(env, extraEnv);

  const res = spawnSync(process.execPath, ['--require', CAPTURA, path.join(SCRIPTS_DIR, script), ...argv], {
    cwd: SCRIPTS_DIR,
    env,
    encoding: 'utf8',
  });
  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  const capturas = (marcador) =>
    res.stdout
      .split('\n')
      .filter((l) => l.startsWith(`${marcador} `))
      .map((l) => JSON.parse(l.slice(marcador.length + 1)));
  return { ...res, todo: res.stdout + res.stderr, code: res.status, capturas };
}

/** La URL que tiene que quedar escrita para el objeto que el script subió. */
function urlDe(host, subida) {
  return `${host}/v0/b/${subida.bucket}/o/${encodeURIComponent(subida.destino)}?alt=media&token=${subida.token}`;
}

/** Lo único que todos los casos que suben tienen que mostrar: UNA subida, completa. */
function unaSubida(r) {
  const subidas = r.capturas('CAPTURA_SUBIDA');
  // Prueba de vida del doble: sin esto, un preload que no intercepta deja los
  // asserts de abajo midiendo NADA y en verde.
  assert.strictEqual(subidas.length, 1, `esperaba una subida capturada:\n${r.todo}`);
  assert.ok(subidas[0].token, 'la subida no llevó firebaseStorageDownloadTokens');
  return subidas[0];
}

for (const e of ESTAMPADORES) {
  test(`${e.script}: contra el emulador estampa la URL DEL EMULADOR`, () => {
    // EL TEST DEL BUG: era `https://firebasestorage.googleapis.com/…` también acá.
    const r = correr(e.script, e.argv, { ...EMULADOR, ...e.env });
    assert.match(r.stdout, /destino: EMULADOR \(Firestore \+ Storage\)/, 'precondición: corrida de emulador');

    const subida = unaSubida(r);
    const [update] = r.capturas('CAPTURA_UPDATE');
    assert.ok(update, `no escribió en Firestore:\n${r.todo}`);

    const url = update.campos[e.campo];
    assert.strictEqual(url, urlDe(HOST_EMULADOR, subida), 'la URL no apunta al objeto subido en el emulador');
    assert.ok(!url.includes('googleapis'), `URL de la nube en una corrida de emulador: ${url}`);
  });

  test(`${e.script}: contra el emulador con un host ilegible, corta ANTES de la primera subida`, () => {
    // `' '` cuenta como emulador para el plan, pero no es un host. El armador
    // tira, y lo que se prueba acá es DÓNDE: si se armara recién al estampar,
    // la excepción caería en el try/catch de cada archivo y la corrida
    // terminaría "bien", con todo subido y nada patcheado.
    const r = correr(e.script, e.argv, { ...EMULADOR, FIREBASE_STORAGE_EMULATOR_HOST: ' ', ...e.env });
    assert.match(r.stdout, /destino: EMULADOR/, 'precondición: el plan lo toma como emulador');

    assert.notStrictEqual(r.code, 0, `tenía que cortar:\n${r.todo}`);
    assert.match(r.stderr, /no pude leer su host/);
    assert.deepStrictEqual(r.capturas('CAPTURA_SUBIDA'), [], 'subió antes de cortar');
    assert.deepStrictEqual(r.capturas('CAPTURA_UPDATE'), []);
  });

  test(`${e.script}: en la nube la URL sigue siendo la de siempre`, () => {
    const r = correr(e.script, [...e.argv, ...NUBE_DE_PRUEBA], e.env);
    assert.doesNotMatch(r.todo, /EMULADOR/, 'precondición: corrida contra la nube');

    const subida = unaSubida(r);
    assert.strictEqual(subida.bucket, 'bucket-de-prueba');
    const [update] = r.capturas('CAPTURA_UPDATE');
    assert.ok(update, `no escribió en Firestore:\n${r.todo}`);
    assert.strictEqual(update.campos[e.campo], urlDe(HOST_DE_LA_NUBE, subida));
  });
}

// ─── upload_enriched_videos.js: su salida es un archivo VERSIONADO ──────────
//
// Los otros tres escriben en Firestore, que contra el emulador es el local.
// Éste escribe `enriched-catalog.json`, que se commitea y se importa: contra el
// emulador no tiene dónde dejar su resultado, y aborta.
//
// `--force --only=…` no es decorativo. Los 793 ejercicios del catálogo ya
// tienen `videoUrl`, así que sin `--force` el loop no procesa ninguno. Con el
// abort BORRADO eso no importa —el `exit 1` lo agarra igual—, pero con el abort
// TARDÍO sí: medido, un abort movido después del loop sale rojo con `--force`
// ("bajó de Drive antes de abortar") y VERDE sin él, porque no había nada que
// bajar. "Antes de bajar, subir o escribir" es justo lo que se prueba acá.

const ENRIQUECIDO = {
  script: 'upload_enriched_videos.js',
  argv: ['--force', '--only=pullup-pesocorporal', '--limit=1'],
};

test('upload_enriched_videos.js: contra el emulador ABORTA antes de bajar, subir o escribir', () => {
  const r = correr(ENRIQUECIDO.script, ENRIQUECIDO.argv, EMULADOR);

  assert.strictEqual(r.code, 1, `tenía que cortar con exit 1:\n${r.todo}`);
  assert.match(r.stderr, /no escribe contra el emulador/);
  assert.ok(r.stderr.includes('enriched-catalog.json'), 'el abort tiene que nombrar el archivo que protege');
  assert.deepStrictEqual(r.capturas('CAPTURA_DESCARGA'), [], 'bajó de Drive antes de abortar');
  assert.deepStrictEqual(r.capturas('CAPTURA_SUBIDA'), [], 'subió al emulador antes de abortar');
  assert.deepStrictEqual(r.capturas('CAPTURA_ESCRITURA'), [], `escribió ${CATALOGO} con URLs del emulador`);
});

test('upload_enriched_videos.js: contra el emulador, --dry-run sigue andando', () => {
  const r = correr(ENRIQUECIDO.script, [...ENRIQUECIDO.argv, '--dry-run'], EMULADOR);

  assert.strictEqual(r.code, 0, r.todo);
  assert.match(r.stdout, /\[dry\] pullup-pesocorporal/);
  assert.deepStrictEqual(r.capturas('CAPTURA_SUBIDA'), []);
  assert.deepStrictEqual(r.capturas('CAPTURA_ESCRITURA'), []);
});

test('upload_enriched_videos.js: en la nube escribe en el catálogo la URL de siempre', () => {
  // La escritura NO llega al archivo: el preload la vuelca a un temporal.
  const r = correr(ENRIQUECIDO.script, [...ENRIQUECIDO.argv, ...NUBE_DE_PRUEBA]);

  const subida = unaSubida(r);
  const escrituras = r.capturas('CAPTURA_ESCRITURA');
  assert.ok(escrituras.length >= 1, `no escribió el catálogo:\n${r.todo}`);
  assert.ok(escrituras.every((w) => w.ruta === CATALOGO), `escribió otra cosa: ${JSON.stringify(escrituras)}`);

  const catalogo = JSON.parse(fs.readFileSync(escrituras[escrituras.length - 1].volcado, 'utf8'));
  const ej = catalogo.find((x) => x.id === 'pullup-pesocorporal');
  assert.strictEqual(ej.videoUrl, urlDe(HOST_DE_LA_NUBE, subida));
});

// ─── Lo versionado: ninguna URL de descarga que no sea de la nube ───────────
//
// El abort de arriba cubre a `upload_enriched_videos.js`. Esto cubre el resto
// de los caminos —otra versión del script, una edición a mano, un merge— por
// los que una URL que sólo sirve en una máquina puede terminar en un archivo
// que se importa a producción.

test('docs/video-catalog-audit no tiene URLs de descarga fuera de la nube', () => {
  const dir = path.join(SCRIPTS_DIR, '..', 'docs', 'video-catalog-audit');
  const archivos = fs.readdirSync(dir, { recursive: true }).filter((f) => fs.statSync(path.join(dir, f)).isFile());

  const URL_DE_DESCARGA = /(https?:\/\/[^/\s"',]+)\/v0\/b\//g;
  let vistas = 0;
  const ajenas = [];
  for (const f of archivos) {
    for (const [, host] of fs.readFileSync(path.join(dir, f), 'utf8').matchAll(URL_DE_DESCARGA)) {
      vistas++;
      if (host !== HOST_DE_LA_NUBE) ajenas.push(`${f}: ${host}`);
    }
  }

  // Control positivo: si el path o la regex se rompen, esto da 0 y el assert
  // de abajo pasaría en verde sin haber mirado nada.
  assert.ok(vistas > 0, 'no encontré ninguna URL de descarga: el barrido no está mirando');
  assert.deepStrictEqual(ajenas, [], 'URLs de descarga que no son de la nube en archivos versionados');
});
