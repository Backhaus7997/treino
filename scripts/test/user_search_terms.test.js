/**
 * test/user_search_terms.test.js — el plegado de la búsqueda de usuarios
 * (#1478) del lado de los scripts, y la compuerta del backfill.
 *
 *   node --test scripts/test/user_search_terms.test.js
 *
 * 1. PARIDAD: `lib/user_search_terms.js` contra los vectores compartidos de
 *    `test/fixtures/search/user_search_terms.json`, los mismos que leen la
 *    Cloud Function y la app. Es la única atadura entre esta copia y la CF.
 * 2. COMPUERTA: `reglasDesplegadasConocen`, lo que impide que el backfill
 *    escriba el campo antes de que las reglas desplegadas lo acepten.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const {
  SEARCH_PREFIX_MIN,
  SEARCH_PREFIX_MAX,
  SEARCH_MAX_TOKENS,
  searchTokens,
  searchPrefixesFor,
  searchPrefixesToWrite,
} = require('../lib/user_search_terms');
const { reglasDesplegadasConocen } = require('../backfill_user_search_prefixes');

const vectores = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, '..', '..', 'test', 'fixtures', 'search', 'user_search_terms.json'),
    'utf8',
  ),
);

test('usa los mismos topes que los vectores', () => {
  assert.strictEqual(SEARCH_PREFIX_MIN, vectores.minPrefixLength);
  assert.strictEqual(SEARCH_PREFIX_MAX, vectores.maxPrefixLength);
  assert.strictEqual(SEARCH_MAX_TOKENS, vectores.maxTokens);
});

for (const c of vectores.cases) {
  test(`vector ${JSON.stringify(c.input)}`, () => {
    assert.deepStrictEqual(searchTokens(c.input), c.tokens);
    assert.deepStrictEqual(searchPrefixesFor(c.input), c.prefixes);
  });
}

test('searchPrefixesToWrite: misma decisión que la CF', () => {
  assert.strictEqual(searchPrefixesToWrite(undefined), null);
  assert.deepStrictEqual(searchPrefixesToWrite({ displayName: 'Juan P.' }), ['ju', 'jua', 'juan']);
  assert.strictEqual(searchPrefixesToWrite({ displayName: null }), null);
  assert.strictEqual(
    searchPrefixesToWrite({ displayName: 'Ana', searchPrefixes: ['an', 'ana'] }),
    null,
  );
  assert.deepStrictEqual(
    searchPrefixesToWrite({ displayName: 'Ana', searchPrefixes: ['ju'] }),
    ['an', 'ana'],
  );
  assert.deepStrictEqual(searchPrefixesToWrite({ displayName: '', searchPrefixes: ['ju'] }), []);
});

// ── Compuerta del backfill ─────────────────────────────────────────────────

const credencial = { getAccessToken: async () => ({ access_token: 'tok' }) };

function fetchFalso(fuente, { statusRelease = 200, statusRuleset = 200 } = {}) {
  const pedidos = [];
  const fetchImpl = async (url, opts) => {
    pedidos.push({ url, auth: opts.headers.Authorization });
    if (url.endsWith('/releases/cloud.firestore')) {
      return {
        ok: statusRelease === 200,
        status: statusRelease,
        json: async () => ({ rulesetName: 'projects/p/rulesets/abc' }),
      };
    }
    return {
      ok: statusRuleset === 200,
      status: statusRuleset,
      json: async () => ({ source: { files: [{ name: 'firestore.rules', content: fuente }] } }),
    };
  };
  return { fetchImpl, pedidos };
}

test('compuerta: reglas desplegadas que conocen el campo → true', async () => {
  const { fetchImpl, pedidos } = fetchFalso("keys().hasOnly(['uid', 'searchPrefixes'])");
  assert.strictEqual(
    await reglasDesplegadasConocen(credencial, 'p', 'searchPrefixes', { fetchImpl }),
    true,
  );
  assert.deepStrictEqual(
    pedidos.map((p) => p.url),
    [
      'https://firebaserules.googleapis.com/v1/projects/p/releases/cloud.firestore',
      'https://firebaserules.googleapis.com/v1/projects/p/rulesets/abc',
    ],
  );
  assert.ok(pedidos.every((p) => p.auth === 'Bearer tok'));
});

test('compuerta: reglas viejas, sin el campo → false', async () => {
  const { fetchImpl } = fetchFalso("keys().hasOnly(['uid', 'deadliftRank'])");
  assert.strictEqual(
    await reglasDesplegadasConocen(credencial, 'p', 'searchPrefixes', { fetchImpl }),
    false,
  );
});

test('compuerta: si no puede leer las reglas, tira (no escribe a ciegas)', async () => {
  for (const status of [{ statusRelease: 403 }, { statusRuleset: 404 }]) {
    const { fetchImpl } = fetchFalso("'searchPrefixes'", status);
    await assert.rejects(
      reglasDesplegadasConocen(credencial, 'p', 'searchPrefixes', { fetchImpl }),
      /HTTP 40[34]/,
    );
  }
});
