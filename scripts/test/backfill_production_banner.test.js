/**
 * test/backfill_production_banner.test.js
 *
 * Los tests del CABLEADO: que los dos backfills que escriben sobre `users/` y
 * `userPublicProfiles/` efectivamente IMPRIMAN el cartel de producción, y que
 * lo impriman antes de leer un solo dato.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#826): `firebase_projects.test.js` prueba el módulo puro —
 * qué ids son producción y qué texto tiene el cartel—. Eso no alcanza. El
 * único cambio de conducta del fix son las dos líneas
 * `if (banner) console.warn(banner)` de `backfill_gym_ids.js` y
 * `backfill_gym_names.js`, y borrándolas los 12 tests del módulo seguían en
 * verde porque ninguno cargaba los backfills. Estos sí los cargan: cada test
 * levanta el script REAL en un subproceso, con `firebase-admin` y `sa-key.json`
 * stubbeados por `fixtures/stub_firebase_admin.js`.
 *
 * El stub tira `STUB_FIRESTORE_REACHED` en la primera lectura de Firestore, así
 * que el script siempre termina en 1. Eso es a propósito y no se asserta: lo
 * que se mide es QUÉ salió por stderr y EN QUÉ ORDEN.
 *
 * `node:test` + `node:assert` + `node:child_process`, sin dependencias nuevas.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');

const BACKFILLS = ['backfill_gym_ids.js', 'backfill_gym_names.js'];

/**
 * Corre un backfill con el stub puesto y devuelve su salida.
 *
 * `--dry-run` a propósito: es la invocación que un operador prueba primero, la
 * que más invita a relajarse, y el cartel tiene que estar igual. (El stub corta
 * en la primera lectura, así que ni siquiera con `--dry-run` llega a Firestore.)
 *
 * `emulador: true` fija `FIRESTORE_EMULATOR_HOST`, que es como el script
 * distingue el proyecto real del namespace local.
 */
function correrBackfill(script, { emulador = false, projectId = 'treino-dev' } = {}) {
  const env = { ...process.env, STUB_PROJECT_ID: projectId };
  if (emulador) {
    env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
  } else {
    delete env.FIRESTORE_EMULATOR_HOST;
  }

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, path.join(SCRIPTS_DIR, script), '--dry-run'],
    { cwd: SCRIPTS_DIR, env, encoding: 'utf8' },
  );

  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  return { stdout: res.stdout, stderr: res.stderr };
}

for (const script of BACKFILLS) {
  test(`${script} escupe el cartel de PRODUCCIÓN por stderr contra treino-dev`, () => {
    const { stderr } = correrBackfill(script);

    assert.match(stderr, /IS PRODUCTION/, 'esperaba el cartel de producción en stderr');
    assert.match(stderr, /treino-dev/);
    assert.match(stderr, /#826/);
    assert.match(
      stderr,
      /does NOT cover Cloud Storage or Auth users/,
      'el cartel tiene que decir QUÉ no cubre el backup — es la mitad que frena a alguien. ' +
        'Decir "no hay backup" a secas contradice AGENTS.md (hay schedule diario, 28 días) ' +
        'y un dato falso en el cartel es exactamente el bug de #826.',
    );
  });

  test(`${script} imprime el cartel ANTES de tocar Firestore`, () => {
    // Un cartel que sale después de la primera lectura no sirve de nada: para
    // cuando lo ves, el script ya está adentro de los datos.
    const { stderr } = correrBackfill(script);

    const cartel = stderr.indexOf('IS PRODUCTION');
    const firestore = stderr.indexOf('STUB_FIRESTORE_REACHED');

    assert.notStrictEqual(cartel, -1, 'no salió el cartel');
    assert.notStrictEqual(
      firestore,
      -1,
      'el script no llegó a Firestore — el stub no se aplicó, el test no mide nada',
    );
    assert.ok(
      cartel < firestore,
      'el cartel tiene que salir ANTES de la primera lectura de Firestore',
    );
  });

  test(`${script} NO grita cuando el destino es el emulador`, () => {
    // Contra emulador el script fija projectId 'treino-dev' igual, pero ahí ese
    // id es apenas un namespace local. Un cartel que aparece cuando no
    // corresponde se aprende a ignorar — y entonces tampoco se lee cuando sí.
    const { stderr } = correrBackfill(script, { emulador: true });

    assert.doesNotMatch(stderr, /IS PRODUCTION/, 'no esperaba cartel contra el emulador');
    assert.match(
      stderr,
      /STUB_FIRESTORE_REACHED/,
      'el script no llegó a Firestore — el test no mide nada',
    );
  });

  test(`${script} tampoco grita si el sa-key apunta a un proyecto que no es producción`, () => {
    // El día que exista un proyecto de dev de verdad (alcance 3 del #826), el
    // cartel tiene que callarse solo, sin tocar los scripts.
    const { stdout, stderr } = correrBackfill(script, { projectId: 'treino-otro-dev' });

    assert.doesNotMatch(stderr, /IS PRODUCTION/);
    // El `project_id` crudo se imprime SIEMPRE (stdout), haya cartel o no.
    assert.match(stdout, /Target Firebase project: treino-otro-dev/);
  });
}
