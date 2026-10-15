/**
 * `deploy_rules.js` tiene que subir EXACTAMENTE lo mismo que
 * `firebase deploy --only firestore:rules`: el fuente sin comentarios
 * (`stripComments` de `strip_rules.js`), nunca el `firestore.rules` crudo.
 *
 * El crudo pesa ~340 KB y el tope de un ruleset es 256 KiB: subiéndolo, la API
 * contesta un 400 que no dice el tamaño. Y como el ruleset desplegado SÍ está
 * procesado, comparar contra el crudo no daba igual nunca.
 *
 * Nada de esto sale a la red: `fixtures/stub_rules_api.js` reemplaza la REST
 * API por un cliente que anota cada request.
 */

'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const { stripComments, LIMIT, bytes } = require('../strip_rules');
const { RUTA_CREDENCIAL_FALSA } = require('./fixtures/stub_firebase_admin');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_rules_api.js');
const FUENTE = fs.readFileSync(path.join(SCRIPTS_DIR, '..', 'firestore.rules'), 'utf8');

function correr({ desplegado }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'deploy-rules-'));
  const logPath = path.join(dir, 'requests.jsonl');
  const desplegadoPath = path.join(dir, 'desplegado.rules');
  fs.writeFileSync(logPath, '');
  fs.writeFileSync(desplegadoPath, desplegado);

  const env = {
    ...process.env,
    STUB_PROJECT_ID: 'treino-dev',
    GOOGLE_APPLICATION_CREDENTIALS: RUTA_CREDENCIAL_FALSA,
    STUB_RULES_LOG: logPath,
    STUB_DEPLOYED_RULES_FILE: desplegadoPath,
    // El guard de fuente compara contra origin/develop: en un PR que toca
    // reglas frenaría antes de la red. Acá se mide QUÉ se sube, no el guard.
    TREINO_DEPLOY_FUERA_DE_DEVELOP: '1',
  };
  delete env.TREINO_SA_KEY;
  delete env.FIRESTORE_EMULATOR_HOST;

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, path.join(SCRIPTS_DIR, 'deploy_rules.js')],
    { cwd: SCRIPTS_DIR, env, encoding: 'utf8' },
  );
  const requests = fs
    .readFileSync(logPath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((l) => JSON.parse(l));
  return { ...res, requests };
}

test('el fuente crudo NO entra en un ruleset; el procesado sí', () => {
  // Si esto deja de ser cierto, el test de abajo no prueba nada nuevo.
  assert.ok(bytes(FUENTE) > LIMIT, 'firestore.rules ya entra crudo en el límite');
  assert.ok(bytes(stripComments(FUENTE)) <= LIMIT);
});

test('sube las reglas SIN comentarios, como la CLI', () => {
  const { status, stderr, requests } = correr({ desplegado: 'rules_version = "2";\n' });
  const post = requests.find((r) => r.method === 'POST');

  assert.ok(post, `no hubo POST de ruleset (status ${status})\n${stderr}`);
  assert.strictEqual(post.content, stripComments(FUENTE));
  assert.notStrictEqual(post.content, FUENTE, 'subió el archivo crudo');
  assert.ok(requests.some((r) => r.method === 'PATCH'), 'no activó el ruleset');
});

test('si lo desplegado ya es igual al procesado, no sube nada', () => {
  const { status, stdout, requests } = correr({ desplegado: stripComments(FUENTE) });

  assert.strictEqual(status, 0);
  assert.match(stdout, /ALREADY MATCH/);
  assert.ok(!requests.some((r) => r.method === 'POST' || r.method === 'PATCH'));
});
