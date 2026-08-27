'use strict';

/**
 * test/strip_appointment_reason_gate.test.js
 *
 * La COMPUERTA DE ESCRITURA de `scripts/migrations/strip_appointment_reason.mjs`,
 * medida corriendo el script REAL en un subproceso con `--apply`, sobre la
 * matriz completa de las cinco variables de emulador que lee el Admin SDK.
 *
 *   node --test scripts/test/
 *
 * ─── Por qué existe (#846) ──────────────────────────────────────────────────
 *
 * El script nació sin un solo test, y es el único consumidor del repo del que
 * depende que una escritura contra PRODUCCIÓN ocurra o no. La primera versión
 * decidía con `usandoEmulador()`, que hace **OR** entre `FIRESTORE_EMULATOR_HOST`
 * y `FIREBASE_AUTH_EMULATOR_HOST`. El script escribe SÓLO en Firestore.
 *
 * Medido entonces, y es la fila que este archivo custodia:
 *
 *     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099   (y Firestore NO)
 *       → "emulador: sí", sin cartel, salteando las DOS puertas del `--apply`
 *       → destino real: treino-dev, que ES producción (#826)
 *
 * Y no hace falta buscarlo: esa variable queda exportada de una sesión de
 * `emulator.sh` o la hereda una shell.
 *
 * El OR alcanzaba en #826 porque sus dos llamadores lo pasaban a
 * `bannerDeProduccion({contraEmulador})` — apagaba un CARTEL, no cambiaba una
 * decisión. Este script fue el primero en ascenderlo a compuerta, y ahí la
 * pregunta es otra: **¿está desviado el servicio que voy a ESCRIBIR?**
 *
 * ─── Qué se mide, y por qué es el destino REAL ──────────────────────────────
 *
 * `fixtures/stub_firebase_admin.js` tira `STUB_FIRESTORE_REACHED` en el primer
 * `.collection()`. O sea que el marcador es la prueba de que el proceso llegó
 * a hablarle a Firestore, y su AUSENCIA —con exit 2— es la prueba de que la
 * compuerta lo frenó antes. No se testea lo que el script IMPRIME: se testea
 * hasta dónde LLEGA.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');
const SCRIPT = path.join(SCRIPTS_DIR, 'migrations', 'strip_appointment_reason.mjs');
const { STUB_FIRESTORE_REACHED } = require('./fixtures/stub_firebase_admin');

/**
 * Las CINCO variables de emulador que mira el Admin SDK. Storage tiene dos
 * nombres —el SDK normaliza `FIREBASE_STORAGE_EMULATOR_HOST` a
 * `STORAGE_EMULATOR_HOST`— y por eso son cinco variables sobre cuatro
 * servicios. La matriz recorre las 32 combinaciones: la única que puede
 * desviar un write de este script es la primera.
 */
const VARIABLES = [
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'STORAGE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'FIREBASE_DATABASE_EMULATOR_HOST',
];

const CARTEL = /IS PRODUCTION/;

function correr(
  args,
  { emuladores = [], projectId = 'treino-dev', credenciales = true, credencialIlegible = false } = {},
) {
  const env = { ...process.env, STUB_PROJECT_ID: projectId };

  for (const v of VARIABLES) delete env[v];
  delete env.GOOGLE_CLOUD_PROJECT;
  delete env.GCLOUD_PROJECT;
  for (const v of emuladores) env[v] = '127.0.0.1:9099';

  if (credencialIlegible) {
    // La variable ESTÁ —o sea que la primera puerta del script no salta— pero
    // el archivo no existe, así que `projectIdObjetivo()` devuelve null. Es el
    // caso "no sé contra qué proyecto escribo", que NO es lo mismo que "sé que
    // no es producción". El stub sólo intercepta rutas que terminan en
    // `sa-key.json`; ésta no.
    env.GOOGLE_APPLICATION_CREDENTIALS = '/no/existe/credencial.json';
  } else if (credenciales) {
    env.GOOGLE_APPLICATION_CREDENTIALS = path.join(SCRIPTS_DIR, 'sa-key.json');
  } else {
    delete env.GOOGLE_APPLICATION_CREDENTIALS;
  }

  const res = spawnSync(process.execPath, ['--require', STUB, SCRIPT, ...args], {
    cwd: SCRIPTS_DIR,
    env,
    encoding: 'utf8',
  });
  assert.strictEqual(res.error, undefined, `no pude ejecutar el script: ${res.error}`);
  const salida = `${res.stdout}${res.stderr}`;
  return {
    stdout: res.stdout,
    stderr: res.stderr,
    salida,
    code: res.status,
    // La medición que importa: ¿el proceso llegó a hablarle a Firestore?
    tocoFirestore: salida.includes(STUB_FIRESTORE_REACHED),
  };
}

/** Las 32 combinaciones de las cinco variables. */
function combinaciones() {
  const out = [];
  for (let mascara = 0; mascara < 1 << VARIABLES.length; mascara += 1) {
    out.push(VARIABLES.filter((_, i) => (mascara & (1 << i)) !== 0));
  }
  return out;
}

// ── La matriz ──────────────────────────────────────────────────────────────

test('matriz de las 5 variables × --apply: sólo FIRESTORE_EMULATOR_HOST desvía el write', (t) => {
  for (const emuladores of combinaciones()) {
    const firestoreDesviado = emuladores.includes('FIRESTORE_EMULATOR_HOST');
    const etiqueta = emuladores.length ? emuladores.join('+') : '(ninguna)';

    t.test(etiqueta, () => {
      const r = correr(['--apply'], { emuladores });

      // Lo que el script AFIRMA sobre Firestore tiene que coincidir con la
      // única variable que lo desvía. Ninguna combinación puede decir "sí"
      // apoyándose en el emulador de otro servicio — ése era el bug.
      assert.match(
        r.stdout,
        firestoreDesviado ? /emulador: Firestore=sí/ : /emulador: Firestore=no/,
        `el script mintió sobre Firestore con ${etiqueta}`,
      );

      if (firestoreDesviado) {
        // Destino local: la compuerta deja pasar y el proceso llega a Firestore.
        assert.ok(r.tocoFirestore, `${etiqueta}: la compuerta frenó una corrida local`);
        assert.doesNotMatch(r.salida, CARTEL, `${etiqueta}: gritó producción contra el emulador`);
      } else {
        // Destino PRODUCCIÓN: `treino-dev`. La compuerta tiene que frenar
        // ANTES del primer contacto, sin importar cuántos otros emuladores
        // haya puestos.
        assert.strictEqual(r.code, 2, `${etiqueta}: no abortó (exit ${r.code})`);
        assert.ok(
          !r.tocoFirestore,
          `${etiqueta}: LLEGÓ A FIRESTORE DE PRODUCCIÓN con --apply`,
        );
        assert.match(r.salida, CARTEL, `${etiqueta}: escribió contra producción sin cartel`);
      }
    });
  }
});

// ── La fila que motivó el issue, sola y con nombre ─────────────────────────

test('FIREBASE_AUTH_EMULATOR_HOST solo NO habilita el --apply contra producción', () => {
  const r = correr(['--apply'], { emuladores: ['FIREBASE_AUTH_EMULATOR_HOST'] });

  assert.strictEqual(r.code, 2);
  assert.ok(!r.tocoFirestore, 'le habló al Firestore de treino-dev');
  assert.match(r.stdout, /destino : treino-dev/);
  assert.match(r.salida, CARTEL);
});

test('avisa que el emulador que SÍ está puesto no desvía nada de este script', () => {
  const r = correr(['--apply'], { emuladores: ['FIREBASE_AUTH_EMULATOR_HOST'] });

  // El aviso es la mitad útil: sin él, el operador ve "Firestore=no" al lado de
  // un emulador que él mismo levantó y asume que el script está cubierto.
  assert.match(r.salida, /no desvían nada/);
  assert.match(r.salida, /auth/);
});

test('con el emulador de Firestore puesto NO pide la confirmación de producción', () => {
  const r = correr(['--apply'], { emuladores: ['FIRESTORE_EMULATOR_HOST'] });

  assert.ok(r.tocoFirestore);
  assert.doesNotMatch(r.salida, /falta la confirmación explícita/);
});

// ── Las otras dos puertas del --apply ──────────────────────────────────────

test('contra producción, --apply sin --si-escribo-en-produccion aborta', () => {
  const r = correr(['--apply']);

  assert.strictEqual(r.code, 2);
  assert.ok(!r.tocoFirestore);
  assert.match(r.salida, /falta la confirmación explícita/);
});

test('contra producción, --apply con la confirmación explícita sí escribe', () => {
  const r = correr(['--apply', '--si-escribo-en-produccion']);

  // Es la contraparte obligatoria: una compuerta que nunca deja pasar no es
  // una compuerta, es un script roto.
  assert.ok(r.tocoFirestore, 'la confirmación explícita no habilitó la corrida');
});

test('destino no resuelto + --apply aborta: no saber NO es saber que no es producción', () => {
  const r = correr(['--apply', '--si-escribo-en-produccion'], { credenciales: false });

  // Sin credenciales el script muere antes por otra puerta —la de "faltan
  // credenciales"—, que también es exit 2 y también frena el write.
  assert.strictEqual(r.code, 2);
  assert.ok(!r.tocoFirestore);
});

test('destino no resuelto + --apply aborta aunque venga la confirmación explícita', () => {
  const r = correr(['--apply', '--si-escribo-en-produccion'], { credencialIlegible: true });

  assert.strictEqual(r.code, 2);
  assert.ok(!r.tocoFirestore);
  assert.match(r.salida, /No se puede resolver contra qué proyecto/);
});

test('contra un proyecto que NO es producción, --apply corre sin flag extra', () => {
  const r = correr(['--apply'], { projectId: 'treino-otro' });

  assert.ok(r.tocoFirestore);
  assert.doesNotMatch(r.salida, CARTEL);
});

// ── DRY-RUN ────────────────────────────────────────────────────────────────

test('el DRY-RUN contra producción lee, pero anuncia el destino y grita igual', () => {
  const r = correr([]);

  assert.match(r.stdout, /modo    : DRY-RUN/);
  assert.match(r.salida, CARTEL);
  // Leer está bien: lo que la compuerta custodia son los `batch.update`.
  assert.ok(r.tocoFirestore);
});
