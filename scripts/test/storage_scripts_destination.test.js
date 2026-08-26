/**
 * test/storage_scripts_destination.test.js
 *
 * Los tests del CABLEADO: que los cuatro scripts que escriben en Firebase
 * Storage pasen de verdad por el guard de `lib/storage_target.js` — y que lo
 * hagan ANTES de tocar un solo dato.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#838): `storage_target.test.js` prueba el módulo puro. Eso
 * no alcanza, y el issue lo dice: el arreglo entero son cuatro líneas de
 * cableado (`const DESTINO = exigirDestinoCoherente(...)`), y borrándolas los
 * tests del módulo seguirían todos en verde porque ninguno carga los scripts.
 * Éstos los cargan: cada test levanta el script REAL en un subproceso con
 * `firebase-admin` stubbeado por `fixtures/stub_firebase_admin.js`, cero I/O de
 * red y cero credenciales.
 *
 * El stub tira `STUB_STORAGE_REACHED` en el primer `.bucket()`, así que un
 * script que llega hasta Storage siempre termina en 1. Eso es a propósito y no
 * se asserta: lo que se mide es QUÉ salió y EN QUÉ ORDEN.
 *
 * `node:test` + `node:assert` + `node:child_process`, sin dependencias nuevas.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');

/** Un dir vacío para el `--thumbs=` de extract_exercise_thumbnails.js. */
const THUMBS_VACIO = fs.mkdtempSync(path.join(os.tmpdir(), 'treino-838-'));

/**
 * Los cuatro scripts que escriben en Storage, con la invocación que llega hasta
 * el punto de escritura. Los tres primeros son los del #838; el cuarto
 * (`upload_drive_exercise_videos.js`) apareció en el barrido y es el mismo bug.
 *
 * `extract_exercise_thumbnails.js` necesita el `GOOGLE_APPLICATION_CREDENTIALS`
 * falso para pasar su propio chequeo de credenciales, que corre DESPUÉS del
 * guard: la ruta no existe y no hace falta que exista — nadie la abre.
 */
const ESCRITORES = [
  {
    script: 'extract_exercise_thumbnails.js',
    argv: ['--upload', `--thumbs=${THUMBS_VACIO}`],
    envExtra: { GOOGLE_APPLICATION_CREDENTIALS: path.join(THUMBS_VACIO, 'sa-key.json') },
  },
  { script: 'apply_catalog_video_fill.js', argv: ['--add-safe'] },
  { script: 'upload_enriched_videos.js', argv: ['--limit=1'] },
  { script: 'upload_drive_exercise_videos.js', argv: ['--limit=1'] },
];

/** Levanta el script con el stub puesto y devuelve salida + exit code. */
function correr({ script, argv, envExtra }, emuladores = {}) {
  const env = { ...process.env, ...(envExtra || {}) };
  // Limpieza explícita: si la máquina que corre los tests tiene alguna de estas
  // exportada, el test mediría otra cosa que la que dice medir.
  for (const v of [
    'FIRESTORE_EMULATOR_HOST',
    'STORAGE_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
    'GOOGLE_CLOUD_PROJECT',
    'GCLOUD_PROJECT',
    'FIREBASE_STORAGE_BUCKET',
  ]) {
    delete env[v];
  }
  Object.assign(env, emuladores);

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, path.join(SCRIPTS_DIR, script), ...argv],
    { cwd: SCRIPTS_DIR, env, encoding: 'utf8' },
  );
  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  return { stdout: res.stdout, stderr: res.stderr, todo: res.stdout + res.stderr, code: res.status };
}

for (const escritor of ESCRITORES) {
  const { script } = escritor;

  test(`${script}: con el emulador de Firestore y Storage sin redirigir, ABORTA`, () => {
    // ESTE ES EL TEST DEL ISSUE. Es la combinación que en extract_exercise_
    // thumbnails.js imprimía "destino: EMULADOR" y subía a producción igual.
    const r = correr(escritor, { FIRESTORE_EMULATOR_HOST: 'localhost:8080' });

    assert.strictEqual(r.code, 1, 'tenía que cortar con exit 1');
    assert.match(r.stderr, /ABORTADO/, 'esperaba el abort del guard');
    assert.doesNotMatch(
      r.todo,
      /STUB_STORAGE_REACHED/,
      'llegó a Storage — el guard corre tarde, o no corre',
    );
    assert.doesNotMatch(
      r.todo,
      /STUB_FIRESTORE_REACHED/,
      'llegó a Firestore — el guard corre tarde, o no corre',
    );
  });

  test(`${script}: en esa corrida NUNCA dice EMULADOR`, () => {
    // La mentira es el bug, no la escritura. Un script que aborta pero antes
    // imprime EMULADOR seguiría enseñándole al operador a confiar en la palabra.
    const r = correr(escritor, { FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
    assert.doesNotMatch(r.todo, /destino: EMULADOR/);
    assert.doesNotMatch(r.todo, /EMULADOR \(Firestore \+ Storage\)/);
  });

  test(`${script}: contra la nube grita el cartel de PRODUCCIÓN`, () => {
    const r = correr(escritor);

    assert.match(r.stderr, /IS PRODUCTION/, 'esperaba el cartel de producción en stderr');
    assert.match(r.stderr, /treino-dev/);
    assert.match(r.stderr, /#826/);
    // La frase que se asserta es la del #826 sobre STORAGE, no una genérica
    // sobre backups: el cartel lo escribe `lib/firebase_projects.js`, que es
    // copia literal del PR #835 y al mergear se reemplaza por la de allá. Si
    // acá se assertea una frase que sólo existe en la copia del #838, el
    // merge que el propio PR indica ("quedarse con la del #835") pone estos
    // cuatro tests en rojo. Ésta vive en las dos, y además es la mitad del
    // cartel que importa para un script que sube archivos: el backup diario
    // de Firestore NO cubre Cloud Storage.
    assert.match(
      r.stderr,
      /does NOT cover Cloud Storage/,
      'el cartel tiene que decir que el backup no cubre Storage — lo que este ' +
        'script escribe no se recupera',
    );
  });

  test(`${script}: el cartel sale ANTES de tocar Storage`, () => {
    // Un cartel que sale después de la primera subida no sirve de nada: para
    // cuando lo leés, el archivo ya está en el bucket real.
    const r = correr(escritor);

    const cartel = r.todo.indexOf('IS PRODUCTION');
    const storage = r.todo.indexOf('STUB_STORAGE_REACHED');

    assert.notStrictEqual(cartel, -1, 'no salió el cartel');
    assert.notStrictEqual(
      storage,
      -1,
      'el script no llegó a Storage — el stub no se aplicó y el test no mide nada',
    );
    assert.ok(cartel < storage, 'el cartel tiene que salir ANTES de la primera escritura');
  });

  test(`${script}: --bucket= manda, y sin proyecto de producción no hay cartel`, () => {
    // La otra mitad del #838: sacar el hardcodeo. Si el bucket no se puede
    // cambiar sin editar el archivo, el script no tiene salida ninguna.
    const r = correr(
      { ...escritor, argv: [...escritor.argv, '--project=treino-otro-dev', '--bucket=bucket-de-prueba'] },
    );

    assert.match(r.stdout, /bucket: bucket-de-prueba/);
    assert.doesNotMatch(r.stderr, /IS PRODUCTION/, 'treino-otro-dev no es producción');
    assert.doesNotMatch(r.todo, /treino-dev\.firebasestorage\.app/, 'quedó un bucket hardcodeado vivo');
  });

  test(`${script}: INVARIANTE — con el emulador puesto no puede terminar en el bucket de prod`, () => {
    // El invariante del issue, escrito como tal: con FIRESTORE_EMULATOR_HOST
    // seteado, o el script muere, o Storage está redirigido. Nunca las dos
    // cosas juntas, y nunca ninguna.
    const soloFirestore = correr(escritor, { FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
    assert.strictEqual(soloFirestore.code, 1, 'sin redirigir Storage tiene que morir');

    const completo = correr(escritor, {
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199',
    });
    assert.doesNotMatch(completo.stderr, /ABORTADO/, 'con los dos redirigidos tiene que dejar pasar');
    assert.doesNotMatch(completo.stderr, /IS PRODUCTION/, 'contra emulador no se grita');
    assert.match(completo.todo, /EMULADOR \(Firestore \+ Storage\)/, 'esperaba la etiqueta de emulador');
  });
}
