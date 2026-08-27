/**
 * test/storage_target.test.js
 *
 * Los tests de `lib/storage_target.js` — cómo se resuelve el bucket y cuándo el
 * destino es INCOHERENTE.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#838): el bug no fue que faltara una advertencia, fue que la
 * que había decía lo contrario de la verdad. Así que lo que hay que fijar con
 * tests es la relación entre lo que el módulo REPORTA y lo que el SDK va a
 * hacer: si Firestore está redirigido y Storage no, no puede existir ninguna
 * etiqueta que imprimir.
 *
 * El #840 le dio vuelta la premisa a los tres tests que leen el `.firebaserc`
 * REAL (los que usan `FIREBASERC_REAL` con `ENV_LIMPIO`). Antes el default era
 * `treino-dev`, así que "sin ninguna variable" significaba PRODUCCIÓN y esos
 * tests esperaban el cartel. Ahora el default es `demo-treino` —un proyecto que
 * no existe en la nube— y el mismo caso significa lo contrario. Donde había un
 * caso ahora hay dos, y los dos están escritos abajo: el que prueba que el
 * default ya no lleva a producción, y el que prueba que nombrarla explícitamente
 * sigue disparando el cartel del #838.
 *
 * `node:test` y `node:assert`, sin dependencias nuevas — mismo criterio que
 * `dedupe_setlogs_plan.test.js`.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const {
  bucketDeProyecto,
  emuladoresActivos,
  esBucketDeProduccion,
  exigirDestinoCoherente,
  planDeStorage,
  resolverBucket,
  resolverProjectId,
} = require('../lib/storage_target');

/** Ruta que no existe: fuerza a que `.firebaserc` NO participe de la decisión. */
const SIN_FIREBASERC = path.join(__dirname, 'fixtures', 'no-existe.firebaserc');
/** El `.firebaserc` real del repo. */
const FIREBASERC_REAL = path.join(__dirname, '..', '..', '.firebaserc');

/** Un env limpio: sin nada de Firebase heredado de la máquina que corre el test. */
const ENV_LIMPIO = Object.freeze({});

// ── resolverProjectId ─────────────────────────────────────────────────────

test('--project= le gana a todo — lo que el operador pidió explícitamente', () => {
  const r = resolverProjectId({
    argv: ['--project=otro-proyecto'],
    env: { GOOGLE_CLOUD_PROJECT: 'treino-dev' },
    rutaFirebaserc: SIN_FIREBASERC,
  });
  assert.strictEqual(r.projectId, 'otro-proyecto');
  assert.strictEqual(r.origen, '--project=');
});

test('sin flag manda GOOGLE_CLOUD_PROJECT — es la que mira el Admin SDK', () => {
  const r = resolverProjectId({
    argv: [],
    env: { GOOGLE_CLOUD_PROJECT: 'treino-otro-dev' },
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(r.projectId, 'treino-otro-dev');
});

test('sin nada cae en .firebaserc, que desde el #840 declara demo-treino', () => {
  // Este test cambió con el hecho, que es para lo que estaba.
  //
  // Hasta el #840 el default de `.firebaserc` era `treino-dev` y esta línea
  // decía `assert.strictEqual(r.projectId, 'treino-dev')`. O sea: el último
  // eslabón de la cadena de resolución —el que atrapa al que no pasó flag, ni
  // env, ni credencial— apuntaba a producción. El #840 lo movió a
  // `demo-treino`, el proyecto del emulador, que no existe en la nube.
  //
  // Sigue siendo el ÚLTIMO recurso y sigue sin ser un permiso: quien nombra
  // producción a propósito la sigue teniendo, con cartel (ver más abajo).
  const r = resolverProjectId({ argv: [], env: ENV_LIMPIO, rutaFirebaserc: FIREBASERC_REAL });
  assert.strictEqual(r.projectId, 'demo-treino');
  assert.strictEqual(r.origen, '.firebaserc');
});

test('sin .firebaserc legible no inventa un proyecto', () => {
  const r = resolverProjectId({ argv: [], env: ENV_LIMPIO, rutaFirebaserc: SIN_FIREBASERC });
  assert.strictEqual(r.projectId, null);
});

// ── resolverBucket ────────────────────────────────────────────────────────

test('el bucket se DERIVA del proyecto — ya no hay literal hardcodeado', () => {
  assert.strictEqual(bucketDeProyecto('treino-dev'), 'treino-dev.firebasestorage.app');
  assert.strictEqual(bucketDeProyecto('treino-otro-dev'), 'treino-otro-dev.firebasestorage.app');
});

test('--bucket= y FIREBASE_STORAGE_BUCKET dan salida sin editar código', () => {
  const porFlag = resolverBucket({ argv: ['--bucket=mi-bucket'], env: ENV_LIMPIO, projectId: 'treino-dev' });
  assert.strictEqual(porFlag.bucket, 'mi-bucket');

  const porEnv = resolverBucket({ argv: [], env: { FIREBASE_STORAGE_BUCKET: 'otro' }, projectId: 'treino-dev' });
  assert.strictEqual(porEnv.bucket, 'otro');
});

test('sin proyecto no hay bucket derivado (y el llamador aborta)', () => {
  assert.strictEqual(bucketDeProyecto(null), null);
  assert.strictEqual(bucketDeProyecto('   '), null);
  assert.strictEqual(resolverBucket({ argv: [], env: ENV_LIMPIO, projectId: null }).bucket, null);
});

// ── emuladoresActivos ─────────────────────────────────────────────────────

test('Storage cuenta como redirigido con CUALQUIERA de las dos variables', () => {
  // firebase-admin normaliza FIREBASE_STORAGE_EMULATOR_HOST a
  // STORAGE_EMULATOR_HOST adentro de admin.storage(). Mirar sólo una daría un
  // falso negativo y abortaría una corrida que estaba perfectamente bien.
  assert.strictEqual(emuladoresActivos({ STORAGE_EMULATOR_HOST: 'http://localhost:9199' }).storage, true);
  assert.strictEqual(emuladoresActivos({ FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' }).storage, true);
  assert.strictEqual(emuladoresActivos(ENV_LIMPIO).storage, false);
});

// ── planDeStorage: la regla que motivó el issue ───────────────────────────

const plan = (env) => planDeStorage({ argv: [], env, rutaFirebaserc: FIREBASERC_REAL });

test('EL CASO DEL #838: Firestore en el emulador y Storage no → incoherente', () => {
  // Esto es exactamente lo que pasaba en extract_exercise_thumbnails.js: el
  // script leía FIRESTORE_EMULATOR_HOST, imprimía "destino: EMULADOR" y subía
  // los .jpg al bucket real.
  const p = plan({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });

  assert.strictEqual(p.coherente, false);
  assert.match(p.motivo, /Firestore apunta al EMULADOR/);
});

test('con el destino incoherente NO existe etiqueta que imprimir', () => {
  // La mitad del arreglo. El bug no fue que faltara un aviso: fue que había una
  // etiqueta para todos los casos y el script elegía la equivocada. Si no hay
  // verdad que contar, `etiquetaDestino` es null y no hay nada que mentir.
  const p = plan({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.strictEqual(p.etiquetaDestino, null);
});

test('el caso simétrico también aborta: Storage local con Firestore en la nube', () => {
  // Escribiría URLs de localhost en el Firestore de producción — que ningún
  // cliente puede abrir, y que quedan ahí hasta que alguien las note.
  const p = plan({ STORAGE_EMULATOR_HOST: 'http://localhost:9199' });
  assert.strictEqual(p.coherente, false);
  assert.match(p.motivo, /Storage apunta al EMULADOR/);
});

test('los dos en el emulador: coherente, etiqueta EMULADOR y sin cartel', () => {
  const p = plan({
    FIRESTORE_EMULATOR_HOST: 'localhost:8080',
    FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199',
  });
  assert.strictEqual(p.coherente, true);
  assert.strictEqual(p.contraEmulador, true);
  assert.match(p.etiquetaDestino, /EMULADOR/);
  assert.strictEqual(p.banner, null, 'contra emulador no se grita — el cartel que grita de más se ignora');
  assert.strictEqual(p.esProduccion, false);
});

test('los dos en la nube SIN NADA: coherente, bucket de demo y SIN cartel', () => {
  // El caso que el #840 dio vuelta. Antes esta corrida —sin una sola variable—
  // derivaba `treino-dev.firebasestorage.app` y sacaba el cartel; el cartel
  // avisaba, pero el destino ERA producción. Ahora el destino es un bucket que
  // no existe, y por eso no hay nada que gritar.
  const p = plan(ENV_LIMPIO);
  assert.strictEqual(p.coherente, true);
  assert.strictEqual(p.bucket, 'demo-treino.firebasestorage.app');
  assert.strictEqual(p.esProduccion, false);
  assert.strictEqual(p.banner, null, 'demo-treino no es producción: gritar acá enseña a ignorar el cartel');
});

test('los dos en la nube NOMBRANDO treino-dev: bucket real y CARTEL', () => {
  // Y el guard del #838 intacto: quien pide producción la recibe, con cartel.
  // Alcanza con nombrarla por cualquiera de los caminos que mira el SDK.
  for (const [comoSeNombra, args] of [
    ['--project=', { argv: ['--project=treino-dev'], env: ENV_LIMPIO }],
    ['GCLOUD_PROJECT', { argv: [], env: { GCLOUD_PROJECT: 'treino-dev' } }],
  ]) {
    const p = planDeStorage({ ...args, rutaFirebaserc: FIREBASERC_REAL });
    assert.strictEqual(p.coherente, true, comoSeNombra);
    assert.strictEqual(p.bucket, 'treino-dev.firebasestorage.app', comoSeNombra);
    assert.strictEqual(p.etiquetaDestino, 'prod (treino-dev.firebasestorage.app)', comoSeNombra);
    assert.ok(p.banner, `treino-dev ES producción (#826) — tiene que salir el cartel por ${comoSeNombra}`);
    assert.match(p.banner, /IS PRODUCTION/, comoSeNombra);
  }
});

test('contra un proyecto que no es producción no hay cartel', () => {
  // El día que exista un dev de verdad, el cartel se calla solo.
  const p = planDeStorage({
    argv: ['--project=treino-otro-dev'],
    env: ENV_LIMPIO,
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(p.banner, null);
  assert.strictEqual(p.etiquetaDestino, 'prod (treino-otro-dev.firebasestorage.app)');
});

// ── el bucket también decide si esto es producción ────────────────────────
//
// El agujero que estos tests cierran: `esProduccion` de `firebase_projects.js`
// mira el PROJECT ID, y para un script que sube archivos el project id no es
// el destino. Antes de `esBucketDeProduccion`, la corrida de abajo pasaba sin
// cartel y los archivos aterrizaban igual en el bucket real.

test('esBucketDeProduccion reconoce los tres nombres del mismo bucket', () => {
  // El sufijo nuevo, el viejo, y el id pelado —que el SDK acepta y resuelve al
  // bucket default—. Reconocer sólo uno deja los otros dos como escape hatch.
  assert.strictEqual(esBucketDeProduccion('treino-dev.firebasestorage.app'), true);
  assert.strictEqual(esBucketDeProduccion('treino-dev.appspot.com'), true);
  assert.strictEqual(esBucketDeProduccion('treino-dev'), true);

  // Y tolera el ruido que el SDK igual acepta.
  assert.strictEqual(esBucketDeProduccion('  GS://Treino-Dev.firebasestorage.app/  '), true);

  // Sin falsos positivos: el prefijo compartido no alcanza.
  assert.strictEqual(esBucketDeProduccion('treino-dev-scratch.firebasestorage.app'), false);
  assert.strictEqual(esBucketDeProduccion('bucket-de-prueba'), false);
  assert.strictEqual(esBucketDeProduccion(''), false);
  assert.strictEqual(esBucketDeProduccion(null), false);
});

test('proyecto de prueba + bucket de producción: ES producción y grita', () => {
  // La invocación exacta que reportó el revisor.
  const p = planDeStorage({
    argv: ['--project=treino-scratch', '--bucket=treino-dev.firebasestorage.app'],
    env: ENV_LIMPIO,
    rutaFirebaserc: FIREBASERC_REAL,
  });

  assert.strictEqual(p.proyectoEsProduccion, false, 'treino-scratch no está en la lista');
  assert.strictEqual(p.bucketEsProduccion, true);
  assert.strictEqual(p.esProduccion, true, 'el destino de las subidas ES producción');

  assert.ok(p.banner, 'tenía que salir un cartel');
  assert.match(p.banner, /IS PRODUCTION STORAGE/);
  assert.match(p.banner, /treino-dev\.firebasestorage\.app/);
  // Y NO puede decir que treino-scratch es producción: nombrar mal lo que está
  // en riesgo es el bug del #838 con otra cara.
  assert.doesNotMatch(p.banner, /"treino-scratch" IS PRODUCTION\b/);
  assert.match(p.banner, /does NOT cover Cloud Storage/);
});

test('cuando el proyecto ya es producción sale UN cartel, el del #826', () => {
  // Dos paredes de emojis seguidas se saltean las dos.
  const p = planDeStorage({
    argv: ['--project=treino-dev', '--bucket=treino-dev.firebasestorage.app'],
    env: ENV_LIMPIO,
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(p.proyectoEsProduccion, true);
  assert.strictEqual(p.bucketEsProduccion, true);
  assert.match(p.banner, /IS PRODUCTION\./, 'esperaba el cartel de proyecto (#826)');
  assert.doesNotMatch(p.banner, /IS PRODUCTION STORAGE/, 'el del bucket sobra acá');
});

test('contra el emulador el bucket de prod no grita — es un namespace local', () => {
  const p = planDeStorage({
    argv: ['--project=treino-scratch', '--bucket=treino-dev.firebasestorage.app'],
    env: {
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199',
    },
    rutaFirebaserc: FIREBASERC_REAL,
  });
  assert.strictEqual(p.contraEmulador, true);
  assert.strictEqual(p.bucketEsProduccion, false, 'el SDK enruta por la env var, no por el nombre');
  assert.strictEqual(p.esProduccion, false);
  assert.strictEqual(p.banner, null);
});

test('el guard imprime el cartel del bucket antes de devolver el plan', () => {
  const r = correrGuard(ENV_LIMPIO, [
    '--project=treino-scratch',
    '--bucket=treino-dev.firebasestorage.app',
  ]);
  assert.deepStrictEqual(r.codigos, [], 'el destino es coherente: no aborta, advierte');
  assert.match(r.stderr, /IS PRODUCTION STORAGE/);
  assert.match(r.stderr, /este script escribe en Storage/, 'la coletilla del #838 también');
});

// ── exigirDestinoCoherente: que efectivamente corte ───────────────────────

/** Corre el guard capturando salida y exit code, sin matar el proceso del test. */
function correrGuard(env, argv = []) {
  const stdout = [];
  const stderr = [];
  const codigos = [];
  const plan = exigirDestinoCoherente({
    argv,
    env,
    rutaFirebaserc: FIREBASERC_REAL,
    salida: {
      log: (m) => stdout.push(String(m)),
      warn: (m) => stderr.push(String(m)),
      error: (m) => stderr.push(String(m)),
    },
    morir: (c) => codigos.push(c),
  });
  return { plan, stdout: stdout.join('\n'), stderr: stderr.join('\n'), codigos };
}

test('el guard mata la corrida cuando el destino es incoherente', () => {
  const r = correrGuard({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.deepStrictEqual(r.codigos, [1], 'esperaba exit(1)');
  assert.match(r.stderr, /ABORTADO/);
  assert.doesNotMatch(r.stdout + r.stderr, /EMULADOR \(Firestore \+ Storage\)/,
    'jamás puede decir EMULADOR cuando Storage no está redirigido — ése ES el bug');
});

test('el abort explica que emulator.sh no levanta Storage', () => {
  // Sin ese dato el operador prueba `FIREBASE_STORAGE_EMULATOR_HOST=...`, el
  // emulador no está escuchando en 9199, y se come un ECONNREFUSED opaco.
  const r = correrGuard({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' });
  assert.match(r.stderr, /emulator\.sh NO levanta Storage/);
});

test('el guard deja pasar y grita el cartel cuando el destino es producción', () => {
  // Ojo con el env: desde el #840 hay que NOMBRAR producción para llegar acá.
  // Con `ENV_LIMPIO` y sin flag el guard cae en el default de `.firebaserc`,
  // que es `demo-treino`, y no grita — ver el test de abajo.
  const r = correrGuard(ENV_LIMPIO, ['--project=treino-dev']);
  assert.deepStrictEqual(r.codigos, [], 'no tenía que abortar');
  assert.match(r.stderr, /IS PRODUCTION/);
  assert.match(r.stdout, /bucket: treino-dev\.firebasestorage\.app/);
});

test('el guard deja pasar SIN gritar cuando nadie nombró producción', () => {
  // El #840 en una línea: la corrida por default deja de ser una corrida contra
  // producción. Que no salga el cartel acá no es una salvaguarda perdida —es
  // que el default dejó de necesitarla, y un cartel que sale siempre es un
  // cartel que no se lee.
  const r = correrGuard(ENV_LIMPIO);
  assert.deepStrictEqual(r.codigos, [], 'no tenía que abortar');
  assert.doesNotMatch(r.stderr, /IS PRODUCTION/);
  assert.match(r.stdout, /bucket: demo-treino\.firebasestorage\.app/);
});

test('el guard aborta si no puede resolver el proyecto — no adivina', () => {
  const stderr = [];
  const codigos = [];
  exigirDestinoCoherente({
    argv: [],
    env: ENV_LIMPIO,
    rutaFirebaserc: SIN_FIREBASERC,
    salida: { log: () => {}, warn: () => {}, error: (m) => stderr.push(String(m)) },
    morir: (c) => codigos.push(c),
  });
  assert.deepStrictEqual(codigos, [1]);
  assert.match(stderr.join('\n'), /no pude resolver/);
});
