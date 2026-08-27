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
 * El stub tira `STUB_STORAGE_REACHED bucket=<nombre>` en el primer `.bucket()`,
 * así que un script que llega hasta Storage siempre termina en 1. Eso es a
 * propósito y no se asserta: lo que se mide es QUÉ salió, CONTRA QUÉ BUCKET y
 * EN QUÉ ORDEN.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * EL #840 LE DIO VUELTA LA PREMISA A ESTE ARCHIVO.
 *
 * La versión original tenía UN caso para la nube —`correr(escritor)` sin
 * ninguna variable— y esperaba el cartel de producción, porque hasta el #840
 * "sin variables" ERA producción: el default de `.firebaserc` decía
 * `treino-dev`, `resolverProjectId` caía ahí y de ahí se derivaba el bucket
 * real. Un `node scripts/upload_enriched_videos.js` a secas subía archivos a
 * producción; el cartel avisaba, pero el destino era ése.
 *
 * Con el #840 el default es `demo-treino`, que no existe en la nube. Ese caso
 * dejó de ser uno y pasó a ser DOS, y los dos hay que medirlos:
 *
 *   1. SIN NADA → resuelve `demo-treino`, NO sale el cartel, y sobre todo: la
 *      llamada a Storage no apunta al bucket de producción. Éste es el test que
 *      prueba que el #840 sirvió — antes esta misma corrida aterrizaba en
 *      `treino-dev.firebasestorage.app`.
 *
 *   2. NOMBRANDO PRODUCCIÓN a propósito (`--project=treino-dev`,
 *      `GCLOUD_PROJECT`, o la credencial de prod) → sale el cartel y sale ANTES
 *      de la primera escritura. Éste prueba que el guard del #838 sigue vivo:
 *      el #840 le sacó el default de encima, no la salvaguarda.
 *
 * Hacer que el caso 1 volviera a esperar el cartel sería reescribir el test
 * para que mida el mundo viejo. El cartel que no sale ahí no es una regresión:
 * es que ya no hay nada contra qué gritar.
 * ═══════════════════════════════════════════════════════════════════════════
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

/** El proyecto de producción, y el bucket que se le deriva (#826 / #838). */
const PROD = 'treino-dev';
const BUCKET_PROD = `${PROD}.firebasestorage.app`;
/** El default de `.firebaserc` desde el #840: un proyecto que NO existe. */
const DEMO = 'demo-treino';

/**
 * Los cuatro scripts que escriben en Storage, con la invocación que llega hasta
 * el punto de escritura. Los tres primeros son los del #838; el cuarto
 * (`upload_drive_exercise_videos.js`) apareció en el barrido y es el mismo bug.
 *
 * `credencial` es la ruta de un `sa-key.json` que NO existe y no hace falta que
 * exista: el stub intercepta cualquier `readFileSync` que termine en ese nombre
 * y devuelve `{ project_id: STUB_PROJECT_ID || 'treino-dev' }`. O sea que
 * setearla hace DOS cosas a la vez —satisface el chequeo de credenciales de
 * `extract_exercise_thumbnails.js`, que corre DESPUÉS del guard, y NOMBRA
 * producción— y por eso desde el #840 va sólo en los casos que apuntan a
 * producción a propósito. En el caso "sin nada" arruinaría justo lo que se
 * quiere medir.
 *
 * Sólo `extract_exercise_thumbnails.js` la necesita: es el único que exige
 * `GOOGLE_APPLICATION_CREDENTIALS` por su cuenta antes de subir.
 */
const ESCRITORES = [
  {
    script: 'extract_exercise_thumbnails.js',
    argv: ['--upload', `--thumbs=${THUMBS_VACIO}`],
    credencial: path.join(THUMBS_VACIO, 'sa-key.json'),
  },
  { script: 'apply_catalog_video_fill.js', argv: ['--add-safe'] },
  { script: 'upload_enriched_videos.js', argv: ['--limit=1'] },
  { script: 'upload_drive_exercise_videos.js', argv: ['--limit=1'] },
];

/**
 * El env de una corrida que apunta a producción a propósito: la credencial que
 * el script pida, si pide alguna. Los que no piden nada llegan a producción por
 * el `--project=` o el `GCLOUD_PROJECT` que pone cada test.
 */
function credencialDe({ credencial }) {
  return credencial ? { GOOGLE_APPLICATION_CREDENTIALS: credencial } : {};
}

/** Levanta el script con el stub puesto y devuelve salida + exit code. */
function correr({ script, argv }, extraEnv = {}) {
  const env = { ...process.env };
  // Limpieza explícita: si la máquina que corre los tests tiene alguna de estas
  // exportada, el test mediría otra cosa que la que dice medir.
  //
  // `GOOGLE_APPLICATION_CREDENTIALS` entró en la lista con el #840 y no es un
  // detalle: la credencial real de TREINO vive en `~/.config/treino/sa-key.json`
  // y hay máquinas que la exportan. El stub intercepta ese nombre de archivo y
  // devuelve `treino-dev`, así que una credencial heredada convertiría el caso
  // "sin nada" en el caso "producción" sin que nadie lo note — verde en CI,
  // rojo en la máquina de quien la tenga, y midiendo el mundo viejo.
  for (const v of [
    'FIRESTORE_EMULATOR_HOST',
    'STORAGE_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
    'GOOGLE_CLOUD_PROJECT',
    'GCLOUD_PROJECT',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'FIREBASE_STORAGE_BUCKET',
    'STUB_PROJECT_ID',
  ]) {
    delete env[v];
  }
  Object.assign(env, extraEnv);

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

  test(`${script}: SIN NADA cae en demo-treino y no llega al Storage de prod`, () => {
    // ÉSTE ES EL TEST DEL #840, y es el que antes decía lo contrario.
    //
    // Sin una sola variable, `resolverProjectId` agota flag, env y credencial y
    // termina en el default de `.firebaserc`. Hasta el #840 ese default era
    // `treino-dev` y esta corrida —un `node scripts/<script>` pelado— subía a
    // producción. Ahora cae en `demo-treino`, que no existe en la nube.
    const r = correr(escritor);

    assert.match(
      r.stdout,
      new RegExp(`Proyecto: ${DEMO} \\(\\.firebaserc\\)`),
      'sin variables el default de .firebaserc tiene que mandar, y decir de dónde salió',
    );
    assert.match(r.stdout, new RegExp(`bucket: ${DEMO}\\.firebasestorage\\.app`));

    // Lo que de verdad prueba el #840: en ninguna parte de la corrida aparece
    // el proyecto de producción ni su bucket. No es que el cartel no salga —es
    // que no hay contra qué gritar.
    assert.doesNotMatch(r.stderr, /IS PRODUCTION/, `${DEMO} no es producción: gritar acá enseña a ignorar el cartel`);
    assert.doesNotMatch(
      r.todo,
      new RegExp(PROD),
      'apareció el proyecto de producción en una corrida que no lo nombró',
    );
    assert.doesNotMatch(
      r.todo,
      /bucket=treino-dev/,
      'el `.bucket()` apuntó al bucket real — el default de .firebaserc no lo desvió',
    );
  });

  test(`${script}: SIN NADA, si toca Storage es contra el bucket de demo`, () => {
    // La otra mitad, y la que no se puede probar mirando sólo el texto: el
    // marcador del stub dice contra QUÉ bucket iba el `.bucket()`. Que el
    // script llegue a Storage no es el problema; el problema era a dónde.
    //
    // `extract_exercise_thumbnails.js` ni siquiera llega: exige
    // GOOGLE_APPLICATION_CREDENTIALS antes de subir, y sin credencial muere ahí.
    // Las dos salidas son correctas y ninguna toca producción.
    const r = correr(escritor);

    const llego = r.todo.includes('STUB_STORAGE_REACHED');
    if (llego) {
      assert.match(
        r.todo,
        new RegExp(`STUB_STORAGE_REACHED bucket=${DEMO}\\.firebasestorage\\.app`),
        'llegó a Storage con un bucket que no es el de demo',
      );
    } else {
      assert.match(
        r.todo,
        /GOOGLE_APPLICATION_CREDENTIALS/,
        'no llegó a Storage y tampoco explicó por qué: eso no es una salida, es un cuelgue',
      );
    }
  });

  test(`${script}: nombrando treino-dev con --project, grita el cartel de PRODUCCIÓN`, () => {
    // El guard del #838 sigue entero: lo que el #840 le sacó de encima es el
    // default que lo hacía disparar sin que nadie pidiera producción.
    const r = correr({ ...escritor, argv: [...escritor.argv, `--project=${PROD}`] }, credencialDe(escritor));

    assert.match(r.stderr, /IS PRODUCTION/, 'esperaba el cartel de producción en stderr');
    assert.match(r.stderr, new RegExp(PROD));
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

  test(`${script}: GCLOUD_PROJECT=treino-dev también dispara el cartel`, () => {
    // La otra forma de nombrar producción, y la que más se usa: exportar la
    // variable que mira el Admin SDK. Si el cartel dependiera del flag, un
    // `export GCLOUD_PROJECT=treino-dev` sería la puerta de atrás.
    const r = correr(escritor, { ...credencialDe(escritor), GCLOUD_PROJECT: PROD });

    assert.match(r.stderr, /IS PRODUCTION/);
    assert.match(r.stdout, new RegExp(`bucket: ${BUCKET_PROD.replace(/\./g, '\\.')}`));
  });

  test(`${script}: contra producción el cartel sale ANTES de tocar Storage`, () => {
    // Un cartel que sale después de la primera subida no sirve de nada: para
    // cuando lo leés, el archivo ya está en el bucket real.
    const r = correr({ ...escritor, argv: [...escritor.argv, `--project=${PROD}`] }, credencialDe(escritor));

    const cartel = r.todo.indexOf('IS PRODUCTION');
    const storage = r.todo.indexOf('STUB_STORAGE_REACHED');

    assert.notStrictEqual(cartel, -1, 'no salió el cartel');
    assert.notStrictEqual(
      storage,
      -1,
      'el script no llegó a Storage — el stub no se aplicó y el test no mide nada',
    );
    assert.ok(cartel < storage, 'el cartel tiene que salir ANTES de la primera escritura');
    assert.match(
      r.todo,
      new RegExp(`STUB_STORAGE_REACHED bucket=${BUCKET_PROD.replace(/\./g, '\\.')}`),
      'y el bucket al que iba tiene que ser el que el cartel nombra',
    );
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

// ── Los que TODAVÍA hardcodean el bucket de producción ────────────────────
//
// La pregunta que abrió el #840: con `demo-treino` como default, el PROYECTO
// cambia y el bucket hardcodeado NO. ¿Hace falta un caso por script?
//
// Se midió, y la respuesta es que no hace falta uno por script — hace falta
// UNO, estructural, que es éste. Quedan tres archivos con el literal
// `treino-dev.firebasestorage.app` adentro, y NINGUNO abre Storage:
//
//   build_catalog_proposal.js        READ-ONLY (lo dice su encabezado): lee
//   match_drive_videos_to_catalog.js `exercises` de Firestore y escribe un CSV
//                                    o un JSON en docs/. El `storageBucket:` de
//                                    su `initializeApp` es opción MUERTA: no hay
//                                    un solo `admin.storage()` en el archivo.
//
//   _video_map.js                    ni siquiera es un script: es un mapa
//                                    `exerciseId → videoUrl`. El bucket vive
//                                    adentro de una URL de DESCARGA que sus dos
//                                    consumidores (seed_workout_catalog.js,
//                                    backfill_exercise_videos.js) estampan en
//                                    Firestore. Leer de producción no es
//                                    escribir en producción, y con el emulador
//                                    esas URLs ya apuntaban al bucket real desde
//                                    antes del #840 — no es una consecuencia de
//                                    este cambio.
//
// O sea: el hardcodeo sobrevive porque hoy es inerte. Lo que hay que fijar no
// es cada caso sino esa condición — que siga inerte, y que nadie sume un cuarto
// archivo copiando el literal. Las dos cosas se rompen en silencio: un
// `admin.storage().bucket()` agregado a build_catalog_proposal.js escribiría en
// producción sin pasar por `exigirDestinoCoherente` y sin cartel, con el
// default en `demo-treino` y el operador convencido de que está offline.

/** Los archivos NO-test que pueden llevar el literal, y por qué. */
const CON_EL_LITERAL = {
  'build_catalog_proposal.js': 'read-only, el storageBucket es opción muerta',
  'match_drive_videos_to_catalog.js': 'read-only, el storageBucket es opción muerta',
  '_video_map.js': 'URL de descarga que se estampa en Firestore, no un destino',
  // Sólo en prosa: el módulo DERIVA el bucket del proyecto. Está en la lista
  // para que el barrido de abajo sea exhaustivo de verdad y no tenga excepciones
  // escondidas.
  'lib/storage_target.js': 'sólo en comentarios — acá el bucket se deriva',
};

/** Los que además tienen que seguir sin tocar Storage. */
const INERTES = ['build_catalog_proposal.js', 'match_drive_videos_to_catalog.js', '_video_map.js'];

const LITERAL = /treino-dev\.(firebasestorage\.app|appspot\.com)/;

test('nadie más copió el literal del bucket de producción', () => {
  // Un cuarto archivo con el bucket adentro es un cuarto destino que no
  // responde a `--bucket=`, ni a `FIREBASE_STORAGE_BUCKET`, ni al default de
  // `.firebaserc`. Este barrido lo agarra el día que aparece, no el día que
  // alguien lo corre.
  const archivos = [
    ...fs.readdirSync(SCRIPTS_DIR).filter((f) => f.endsWith('.js')),
    ...fs.readdirSync(path.join(SCRIPTS_DIR, 'lib'))
      .filter((f) => f.endsWith('.js'))
      .map((f) => path.join('lib', f)),
  ];

  const encontrados = archivos.filter((f) =>
    LITERAL.test(fs.readFileSync(path.join(SCRIPTS_DIR, f), 'utf8')),
  );

  assert.deepStrictEqual(
    encontrados.sort(),
    Object.keys(CON_EL_LITERAL).sort(),
    'la lista de archivos con el bucket de producción hardcodeado cambió: si ' +
      'sacaste uno, borralo de CON_EL_LITERAL; si apareció uno nuevo, o lo ' +
      'pasás por exigirDestinoCoherente o justificás acá por qué es inerte',
  );
});

for (const archivo of INERTES) {
  test(`${archivo}: hardcodea el bucket de prod, pero NO abre Storage`, () => {
    const src = fs.readFileSync(path.join(SCRIPTS_DIR, archivo), 'utf8');

    assert.match(
      src,
      LITERAL,
      'ya no hardcodea el bucket — sacalo de INERTES y de CON_EL_LITERAL',
    );
    assert.doesNotMatch(
      src,
      /admin\.storage\(\)|\.bucket\(/,
      'abrió Storage con el bucket de producción hardcodeado, sin pasar por ' +
        'exigirDestinoCoherente: ni --bucket= lo desvía ni sale cartel (#838/#840)',
    );
  });
}
