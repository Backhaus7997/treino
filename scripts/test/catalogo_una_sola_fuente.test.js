/**
 * test/catalogo_una_sola_fuente.test.js
 *
 * El test que faltaba: que las plantillas del catálogo tengan UNA fuente, y
 * que esa fuente apunte a ejercicios que existen.
 *
 *   node --test scripts/test/
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUÉ NINGÚN TEST ATRAPÓ ESTO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Había 469 tests sobre `scripts/` y los 469 eran de DESTINO: ¿a qué proyecto
 * escribo, salió el cartel de producción, pasé por la frontera de credenciales.
 * Ninguno miraba un solo CAMPO de un documento que un seeder escribe.
 *
 * Con esa red, `scripts/seed_workout_catalog.js` podía sembrar seis plantillas
 * enteras cuyos 116 `exerciseId` no existían en el catálogo vivo, y los 469
 * seguían verdes. El bug no era invisible por sutil: era invisible porque
 * nadie había escrito la clase de test que lo ve.
 *
 * Lo que hacía más fina la trampa: ese archivo TENÍA un validador de
 * referencias, `validateRoutineRefs()`, y pasaba siempre. Validaba sus rutinas
 * contra sus PROPIOS 25 ejercicios. Una burbuja auto-consistente no prueba
 * nada del mundo real, y encima daba la sensación de estar cubierto.
 *
 * De ahí sale la forma de estos tests: **cruzan archivos distintos**. Un test
 * que sólo mira un archivo contra sí mismo no puede caerse.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  QUÉ PINEA CADA UNO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   1. Que `improved-templates.json` no referencie un ejercicio que no está
 *      en `enriched-catalog.json`. Es el invariante de contenido, y el único
 *      que se pone rojo si alguien edita una plantilla a mano.
 *   2. Que `seed_workout_catalog.js` no vuelva a escribir en `/routines`.
 *      Es el invariante estructural: hay UN seeder de plantillas.
 *   3. Que `--routines` y `--all` corten fuerte en vez de degradar en
 *      silencio. Un comando que alguien tiene en la memoria muscular no puede
 *      cambiar de significado sin avisar.
 *
 * Contexto: el encabezado de `scripts/seed_workout_catalog.js`.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const RAIZ = path.resolve(__dirname, '..', '..');
const SEEDER_EJERCICIOS = path.join(RAIZ, 'scripts', 'seed_workout_catalog.js');
const SEEDER_PLANTILLAS = path.join(RAIZ, 'scripts', 'seed_templates.js');

const PLANTILLAS = require(
  path.join(RAIZ, 'docs', 'video-catalog-audit', 'improved-templates.json'),
);
const CATALOGO = require(
  path.join(RAIZ, 'docs', 'video-catalog-audit', 'enriched-catalog.json'),
);

// ── 1. Contenido: ninguna plantilla apunta a un ejercicio que no existe ──────

test('toda plantilla del catálogo referencia ejercicios que existen', () => {
  const existentes = new Set(CATALOGO.map((e) => e.id));
  assert.ok(existentes.size > 0, 'enriched-catalog.json vino vacío');

  const huerfanas = [];
  for (const p of PLANTILLAS) {
    for (const dia of p.days ?? []) {
      for (const slot of dia.slots ?? []) {
        if (!existentes.has(slot.exerciseId)) {
          huerfanas.push(`${p.id} día ${dia.dayNumber}: '${slot.exerciseId}'`);
        }
      }
    }
  }

  assert.deepEqual(
    huerfanas,
    [],
    `${huerfanas.length} referencia(s) a ejercicios que no están en el ` +
      `catálogo. Una plantilla así se siembra sin error y se rompe recién ` +
      `cuando un alumno la abre.`,
  );
});

test('las plantillas traen los campos que el paywall y la vidriera leen', () => {
  // `isPremium` decide el cobro del catálogo; `summary` es lo que el alumno
  // lee para saber qué ES la rutina (#648). Los dos se perdían enteros al
  // sembrar con el archivo equivocado, sin que nada se pusiera rojo.
  const sinCampo = [];
  for (const p of PLANTILLAS) {
    if (typeof p.isPremium !== 'boolean') sinCampo.push(`${p.id}.isPremium`);
    if (typeof p.summary !== 'string' || p.summary.length === 0) {
      sinCampo.push(`${p.id}.summary`);
    }
  }
  assert.deepEqual(sinCampo, [], 'campos ausentes en improved-templates.json');
});

// ── 2. Estructura: un solo seeder escribe /routines ──────────────────────────

test('seed_workout_catalog.js no escribe en /routines', () => {
  const src = fs.readFileSync(SEEDER_EJERCICIOS, 'utf8');
  // Se busca la escritura, no la palabra: el encabezado del archivo habla de
  // `/routines` a propósito para explicar por qué ya no la toca.
  const escrituras = [...src.matchAll(/collection\(\s*['"]([a-zA-Z_]+)['"]\s*\)/g)]
    .map((m) => m[1]);

  assert.ok(
    escrituras.includes('exercises'),
    'el seeder de ejercicios dejó de escribir /exercises — eso no es lo que ' +
      'este test cuida, pero si pasa, algo se rompió fuerte',
  );
  assert.ok(
    !escrituras.includes('routines'),
    'volvió a haber dos seeders escribiendo /routines. Los dos usan .set() ' +
      'sin merge, así que el último que corra le pisa el catálogo al otro — ' +
      'que es exactamente lo que pasó hasta el 2026-09-14.',
  );
});

test('seed_templates.js sigue siendo el que escribe /routines', () => {
  const src = fs.readFileSync(SEEDER_PLANTILLAS, 'utf8');
  assert.match(
    src,
    /collection\(\s*['"]routines['"]\s*\)/,
    'si este seeder dejó de escribir /routines, no queda ninguno',
  );
});

// ── 3. Los flags viejos cortan, no degradan ─────────────────────────────────

// El `--require` del stub NO es decoración, y la primera versión de este
// archivo no lo tenía. Sin él, el subproceso llega a Firestore de verdad: bajo
// la mutación que estos tests existen para atrapar —volver a aceptar `--all`—
// el script seguía hasta `seedExercises()` y se COLGABA reintentando contra un
// emulador que no estaba, en vez de fallar. Un test que se cuelga justo en el
// caso que cuida no es un test.
//
// `stub_firebase_admin.js` corta en el primer contacto y hace terminar el
// proceso, así que el caso malo falla rápido y con un mensaje. Es el mismo
// arnés de `npm_entrypoints_banner.test.js`.
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');
const { RUTA_CREDENCIAL_FALSA } = require('./fixtures/stub_firebase_admin');

function correrSeeder(args) {
  const env = { ...process.env, STUB_PROJECT_ID: 'treino-dev' };
  env.GOOGLE_APPLICATION_CREDENTIALS = RUTA_CREDENCIAL_FALSA;
  delete env.TREINO_SA_KEY;
  delete env.GOOGLE_CLOUD_PROJECT;
  delete env.GCLOUD_PROJECT;
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.FIREBASE_AUTH_EMULATOR_HOST;

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, SEEDER_EJERCICIOS, ...args],
    { cwd: path.join(RAIZ, 'scripts'), env, encoding: 'utf8' },
  );
  assert.equal(res.error, undefined, `no pude ejecutar el seeder: ${res.error}`);
  return res;
}

for (const flag of ['--routines', '--all']) {
  test(`seed_workout_catalog.js ${flag} corta y dice adónde ir`, () => {
    const r = correrSeeder([flag]);

    assert.notEqual(
      r.status,
      0,
      `${flag} tiene que cortar. Aceptarlo haciendo sólo los ejercicios le ` +
        `cambia el significado a un comando que la gente tiene memorizado.`,
    );
    assert.match(
      r.stderr,
      /seed_templates\.js/,
      `el mensaje de ${flag} tiene que nombrar el reemplazo: un error que ` +
        `sólo dice "no" manda a la persona a leer el código`,
    );
    // Y que corte ANTES de tocar nada: si el stub gritó, el script siguió de
    // largo hasta Firestore y el `exit 1` vino de otra cosa.
    assert.doesNotMatch(
      r.stdout + r.stderr,
      /STUB_FIRESTORE_REACHED/,
      `${flag} llegó hasta Firestore antes de cortar`,
    );
  });
}
