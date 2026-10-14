'use strict';

/**
 * test/capturas_solo_emulador.test.js
 *
 * La compuerta de los scripts de `scripts/capturas/`: `lib/solo_emulador.js`
 * puro, y el CABLEADO de cada script —que la llame, y antes de tocar
 * Firestore—.
 *
 *   node --test scripts/test/capturas_solo_emulador.test.js
 *
 * ─── Por qué existe ─────────────────────────────────────────────────────────
 *
 * Los siete scripts de capturas no pasan por `lib/admin.js`: inicializan con
 * `projectId: 'treino-dev'` y sin credencial, así que su compuerta "sólo
 * emulador" es lo único que separa una corrida de capturas de producción. Esa
 * compuerta era `if (!process.env.FIRESTORE_EMULATOR_HOST)`, y `' '` es
 * truthy: con la variable en blanco PASABA. Medido sin red, los siete pasaban
 * la compuerta y morían recién en `getFirestore()` ("is not a valid host"). La
 * que frenaba era una validación interna del SDK, no la compuerta.
 *
 * ─── Cómo mide el cableado ──────────────────────────────────────────────────
 *
 * Carga cada script de verdad con `fixtures/stub_firebase_admin.js` puesto, que
 * tira `STUB_FIRESTORE_REACHED` en el primer `.collection()` / `.batch()`. El
 * doble NO valida el host —no hay "is not a valid host" que salve a nadie—, así
 * que una compuerta que deja pasar el blanco se ve como lo que es: el script
 * llega a Firestore.
 *
 * Medir por AUSENCIA del marcador no distingue "la compuerta frenó" de "el doble
 * no se aplicó" (ver `subpath_stub_interception.test.js`). Por eso cada corrida
 * exige en POSITIVO `STUB_SUBPATH_INTERCEPTED`, y el caso con host es el
 * control: ahí el marcador de Firestore TIENE que aparecer.
 *
 * La lista de scripts sale del directorio, no de una enumeración: uno nuevo que
 * se saltee la compuerta entra solo a estos tests y los pone en rojo.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { veredictoSoloEmulador } = require('../lib/solo_emulador');
const { TODAS_LAS_VARIABLES } = require('../lib/target_project');
const {
  STUB_FIRESTORE_REACHED,
  STUB_SUBPATH_INTERCEPTED,
} = require('./fixtures/stub_firebase_admin');

const SCRIPTS_DIR = path.join(__dirname, '..');
const CAPTURAS_DIR = path.join(SCRIPTS_DIR, 'capturas');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');

/** El puerto real del emulador de Firestore, para no escribirlo dos veces. */
const PUERTO_FIRESTORE = JSON.parse(
  fs.readFileSync(path.join(SCRIPTS_DIR, '..', 'firebase.json'), 'utf8'),
).emulators.firestore.port;
const HOST = `localhost:${PUERTO_FIRESTORE}`;

const BLANCOS = [' ', '\t', '\n', '  \t '];

// ─── lib/solo_emulador.js, puro ─────────────────────────────────────────────

test('sin FIRESTORE_EMULATOR_HOST → SIN_EMULADOR, y nombra la variable', () => {
  const v = veredictoSoloEmulador(['firestore'], {});
  assert.strictEqual(v.ok, false);
  assert.strictEqual(v.motivo, 'SIN_EMULADOR');
  assert.match(v.mensaje, /FIRESTORE_EMULATOR_HOST {2}\(ausente\)/);
  assert.ok(v.mensaje.includes(`export FIRESTORE_EMULATOR_HOST=${HOST}`), v.mensaje);
});

test("'' es ausente, no en blanco → SIN_EMULADOR", () => {
  const v = veredictoSoloEmulador(['firestore'], { FIRESTORE_EMULATOR_HOST: '' });
  assert.strictEqual(v.motivo, 'SIN_EMULADOR');
});

for (const blanco of BLANCOS) {
  test(`FIRESTORE_EMULATOR_HOST=${JSON.stringify(blanco)} → EN_BLANCO, no "sin emulador"`, () => {
    const v = veredictoSoloEmulador(['firestore'], { FIRESTORE_EMULATOR_HOST: blanco });
    assert.strictEqual(v.ok, false);
    assert.strictEqual(v.motivo, 'EN_BLANCO');
    assert.match(v.mensaje, /FIRESTORE_EMULATOR_HOST {2}\(en blanco\)/);
    assert.match(v.mensaje, /unset FIRESTORE_EMULATOR_HOST\n/);
  });
}

test('con host de Firestore → pasa', () => {
  assert.deepStrictEqual(veredictoSoloEmulador(['firestore'], { FIRESTORE_EMULATOR_HOST: HOST }), {
    ok: true,
  });
});

for (const variable of TODAS_LAS_VARIABLES.filter((v) => v !== 'FIRESTORE_EMULATOR_HOST')) {
  test(`Firestore con host y ${variable} en blanco → EN_BLANCO igual`, () => {
    // Es el caso que `contraEmuladorDe(['firestore'])` sola deja pasar: el
    // servicio que el script toca SÍ está desviado. Se aborta porque el
    // ambiente se contradice, con el mismo criterio que `credenciales.js`.
    const v = veredictoSoloEmulador(['firestore'], {
      FIRESTORE_EMULATOR_HOST: HOST,
      [variable]: ' ',
    });
    assert.strictEqual(v.motivo, 'EN_BLANCO');
    assert.ok(v.mensaje.includes(`${variable}  (en blanco)`), v.mensaje);
    assert.ok(v.mensaje.includes(`unset ${variable}\n`), 'el unset nombra sólo la que está en blanco');
  });
}

test('el emulador de OTRO servicio no cuenta como el de Firestore (#846)', () => {
  const v = veredictoSoloEmulador(['firestore'], { FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099' });
  assert.strictEqual(v.motivo, 'SIN_EMULADOR');
});

test('con varios servicios exige TODOS, y nombra sólo los que faltan', () => {
  const v = veredictoSoloEmulador(['firestore', 'auth'], { FIRESTORE_EMULATOR_HOST: HOST });
  assert.strictEqual(v.motivo, 'SIN_EMULADOR');
  assert.match(v.mensaje, /FIREBASE_AUTH_EMULATOR_HOST {2}\(ausente\)/);
  assert.doesNotMatch(v.mensaje, /FIRESTORE_EMULATOR_HOST {2}\(/);
});

test('una lista vacía o un servicio desconocido tiran, aunque el ambiente esté en blanco', () => {
  const enBlanco = { FIRESTORE_EMULATOR_HOST: ' ' };
  assert.throws(() => veredictoSoloEmulador([], enBlanco), TypeError);
  assert.throws(() => veredictoSoloEmulador(undefined, enBlanco), TypeError);
  assert.throws(() => veredictoSoloEmulador(['firestor'], enBlanco), /servicio desconocido/);
});

// ─── El cableado de cada script ─────────────────────────────────────────────

const SCRIPTS = fs
  .readdirSync(CAPTURAS_DIR)
  .filter((f) => f.endsWith('.js'))
  .sort();

test('el directorio de capturas tiene scripts (si no, el resto mide nada)', () => {
  assert.ok(SCRIPTS.length > 0, `no encontré scripts en ${CAPTURAS_DIR}`);
});

/**
 * Corre un script de capturas con el doble puesto. El ambiente arranca SIN
 * ninguna variable de emulador ni de credencial: si la máquina que corre los
 * tests tiene alguna exportada (una sesión de `emulator.sh`, `$TREINO_SA_KEY`
 * en `~/.zshrc`), el test mediría esa máquina y no el caso que dice medir.
 */
function correr(script, extraEnv) {
  const env = { ...process.env };
  for (const v of [
    ...TODAS_LAS_VARIABLES,
    'GOOGLE_APPLICATION_CREDENTIALS',
    'TREINO_SA_KEY',
    'GOOGLE_CLOUD_PROJECT',
    'GCLOUD_PROJECT',
    'STUB_PROJECT_ID',
  ]) {
    delete env[v];
  }
  Object.assign(env, extraEnv);

  const res = spawnSync(process.execPath, ['--require', STUB, path.join(CAPTURAS_DIR, script)], {
    cwd: CAPTURAS_DIR,
    env,
    encoding: 'utf8',
    timeout: 30_000,
  });
  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  const todo = `${res.stdout}${res.stderr}`;
  assert.ok(
    todo.includes(STUB_SUBPATH_INTERCEPTED),
    `${script}: el doble no interceptó firebase-admin — el test mediría el SDK real:\n${todo}`,
  );
  return { code: res.status, stderr: res.stderr, todo };
}

function noLlegoAFirestore(r, script) {
  assert.ok(
    !r.todo.includes(STUB_FIRESTORE_REACHED),
    `${script} llegó a Firestore: la compuerta no corre, o corre tarde:\n${r.todo}`,
  );
}

for (const script of SCRIPTS) {
  test(`${script}: con FIRESTORE_EMULATOR_HOST en blanco ABORTA por el blanco, antes de Firestore`, () => {
    const r = correr(script, { FIRESTORE_EMULATOR_HOST: ' ' });
    // Primero el marcador: un script que llega a Firestore también sale con 1
    // (el doble tira), y el rojo tiene que decir eso, no "otro mensaje".
    noLlegoAFirestore(r, script);
    assert.strictEqual(r.code, 1, r.todo);
    assert.match(r.stderr, /ABORTADO: hay variables de emulador exportadas EN BLANCO/);
    assert.match(r.stderr, /FIRESTORE_EMULATOR_HOST {2}\(en blanco\)/);
  });

  test(`${script}: con Firestore desviado y Auth en blanco ABORTA igual`, () => {
    // El que distingue `variablesEnBlanco` de `contraEmuladorDe` sola: con
    // Firestore puesto, la segunda deja pasar.
    const r = correr(script, {
      FIRESTORE_EMULATOR_HOST: HOST,
      FIREBASE_AUTH_EMULATOR_HOST: ' ',
    });
    noLlegoAFirestore(r, script);
    assert.strictEqual(r.code, 1, r.todo);
    assert.match(r.stderr, /FIREBASE_AUTH_EMULATOR_HOST {2}\(en blanco\)/);
  });

  test(`${script}: sin FIRESTORE_EMULATOR_HOST ABORTA, antes de Firestore`, () => {
    const r = correr(script, {});
    noLlegoAFirestore(r, script);
    assert.strictEqual(r.code, 1, r.todo);
    assert.match(r.stderr, /ABORTADO: este script es SOLO para el emulador/);
  });

  test(`${script}: CONTROL — con el emulador puesto pasa la compuerta y llega a Firestore`, () => {
    // Sin este caso, los tres de arriba no prueban nada: "no llegó a Firestore"
    // también sería cierto de un script que muere antes por otra razón.
    const r = correr(script, { FIRESTORE_EMULATOR_HOST: HOST });
    assert.doesNotMatch(r.todo, /ABORTADO/, r.todo);
    assert.ok(r.todo.includes(STUB_FIRESTORE_REACHED), `${script} no llegó a Firestore:\n${r.todo}`);
  });

  test(`${script}: la compuerta va antes de initializeApp()`, () => {
    const fuente = fs.readFileSync(path.join(CAPTURAS_DIR, script), 'utf8');
    const compuerta = fuente.indexOf("exigirSoloEmulador(['firestore'])");
    const inicializa = fuente.indexOf('initializeApp(');
    assert.ok(compuerta >= 0, `${script} no llama a exigirSoloEmulador(['firestore'])`);
    assert.ok(inicializa >= 0, `${script} no llama a initializeApp() — ¿cambió la forma del script?`);
    assert.ok(compuerta < inicializa, `${script}: la compuerta corre después de initializeApp()`);
  });
}
