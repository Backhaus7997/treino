/**
 * test/firebase_projects.test.js
 *
 * Los tests de `lib/firebase_projects.js` — qué project ids son PRODUCCIÓN.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#826): el módulo no calcula nada, DECLARA un hecho —
 * `treino-dev` es el único proyecto Firebase de TREINO y tiene usuarios
 * reales—. El riesgo no es que el código se rompa, es que alguien "arregle"
 * la lista más adelante viendo el sufijo `-dev` y asumiendo que fue un typo.
 * El test de `treino-dev` está para que ese cambio salga en ROJO y obligue a
 * leer el porqué antes de tocarlo.
 *
 * `node:test` y `node:assert`, sin dependencias nuevas: `scripts/` sólo tiene
 * `firebase-admin` — mismo criterio que `dedupe_setlogs_plan.test.js`.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  PROYECTOS_DE_PRODUCCION,
  esProduccion,
  bannerDeProduccion,
} = require('../lib/firebase_projects');

// ── esProduccion ──────────────────────────────────────────────────────────

test('treino-dev ES producción — el nombre miente, ver #826', () => {
  assert.strictEqual(esProduccion('treino-dev'), true);
});

test('treino-prod no existe todavía, así que no está en la lista', () => {
  // Verificado con `firebase projects:list`: la cuenta tiene fertas-e7b88,
  // gymrankios y treino-dev, nada más. Si algún día se crea, se agrega a
  // PROYECTOS_DE_PRODUCCION y este test cambia junto con el hecho.
  assert.strictEqual(PROYECTOS_DE_PRODUCCION.includes('treino-prod'), false);
});

test('el proyecto de los rules tests NO es producción', () => {
  // `treino-test-rules` (scripts/rules_test/) corre siempre contra emulador.
  assert.strictEqual(esProduccion('treino-test-rules'), false);
});

test('no decide por heurística de nombre: cualquier id con "dev" no alcanza', () => {
  // Esta es la trampa que motivó el módulo: el guard viejo de los backfills
  // hacía /dev/i.test(id), que da true para treino-dev. La lista es explícita
  // justamente para no repetir ese razonamiento.
  assert.strictEqual(esProduccion('otra-app-dev'), false);
  assert.strictEqual(esProduccion('dev'), false);
});

test('tolera espacios y mayúsculas — el id llega de sa-key.json o de --project=', () => {
  assert.strictEqual(esProduccion('  TREINO-DEV \n'), true);
});

test('lo que no es string no es producción (y el llamador igual imprime el id crudo)', () => {
  for (const v of [undefined, null, 42, {}, ['treino-dev']]) {
    assert.strictEqual(esProduccion(v), false);
  }
});

test('la lista está congelada — nadie la muta en runtime', () => {
  assert.throws(() => PROYECTOS_DE_PRODUCCION.push('lo-que-sea'));
});

// ── bannerDeProduccion ────────────────────────────────────────────────────

test('contra producción devuelve un cartel que nombra el proyecto', () => {
  const banner = bannerDeProduccion('treino-dev');
  assert.ok(banner, 'esperaba cartel');
  assert.match(banner, /treino-dev/);
  assert.match(banner, /IS PRODUCTION/);
  assert.match(banner, /#826/);
});

test('contra un proyecto que no es producción no dice nada', () => {
  assert.strictEqual(bannerDeProduccion('treino-test-rules'), null);
});

test('NO grita si el destino es el emulador aunque el id sea treino-dev', () => {
  // Los backfills fijan projectId: 'treino-dev' también en modo emulador; ahí
  // ese id es apenas un namespace local. Un cartel que aparece cuando no
  // corresponde se aprende a ignorar — y entonces tampoco se lee cuando sí.
  assert.strictEqual(
    bannerDeProduccion('treino-dev', { contraEmulador: true }),
    null,
  );
});

test('sin opciones asume que NO es emulador — el default es el lado seguro', () => {
  assert.ok(bannerDeProduccion('treino-dev', {}));
});
