/**
 * test/target_project.test.js
 *
 * `lib/target_project.js` puro: contra qué proyecto va a escribir el proceso,
 * y si está apuntando al emulador. Sin red, sin `firebase-admin`.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#826): la revisión encontró que el barrido anterior buscaba
 * comandos de `firebase`/`gcloud` y por eso no veía `npm run seed:all`, que es
 * el camino más corto que hay hacia producción. Este módulo es lo que permite
 * que esos entrypoints —que llaman a `admin.initializeApp()` pelado— sepan a
 * dónde están escribiendo antes de escribir.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { usandoEmulador, projectIdObjetivo } = require('../lib/target_project');

/** Escribe un `sa-key.json` de mentira en un tmpdir. NUNCA en `scripts/`. */
function credencialFalsa(contenido) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'treino-826-'));
  const ruta = path.join(dir, 'sa-key.json');
  fs.writeFileSync(ruta, typeof contenido === 'string' ? contenido : JSON.stringify(contenido));
  return ruta;
}

// ── usandoEmulador ────────────────────────────────────────────────────────

test('usandoEmulador: sin variables es false', () => {
  assert.strictEqual(usandoEmulador({}), false);
});

test('usandoEmulador: cualquiera de las dos variables alcanza', () => {
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' }), true);
  assert.strictEqual(usandoEmulador({ FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099' }), true);
});

test('usandoEmulador: vacío o whitespace NO cuenta como emulador', () => {
  // Exportar la variable en blanco no desvía nada. Si esto devolviera true, el
  // cartel se apagaría exactamente cuando el proceso sí va a producción — que
  // es la clase de falsa tranquilidad que motivó #826.
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: '' }), false);
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: '   ' }), false);
});

// ── projectIdObjetivo ─────────────────────────────────────────────────────

test('projectIdObjetivo: GOOGLE_CLOUD_PROJECT gana', () => {
  assert.strictEqual(projectIdObjetivo({ GOOGLE_CLOUD_PROJECT: 'treino-dev' }), 'treino-dev');
});

test('projectIdObjetivo: GCLOUD_PROJECT como alternativa', () => {
  assert.strictEqual(projectIdObjetivo({ GCLOUD_PROJECT: 'treino-dev' }), 'treino-dev');
});

test('projectIdObjetivo: sale del project_id de GOOGLE_APPLICATION_CREDENTIALS', () => {
  const ruta = credencialFalsa({ project_id: 'treino-dev', type: 'service_account' });
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: ruta }), 'treino-dev');
});

test('projectIdObjetivo: la variable explícita gana sobre la credencial', () => {
  const ruta = credencialFalsa({ project_id: 'otro-proyecto' });
  const env = { GOOGLE_CLOUD_PROJECT: 'treino-dev', GOOGLE_APPLICATION_CREDENTIALS: ruta };
  assert.strictEqual(projectIdObjetivo(env), 'treino-dev');
});

test('projectIdObjetivo: sin nada devuelve null, no un valor inventado', () => {
  // Callar es correcto: significa que el proyecto lo resuelve el SDK por un
  // camino que este módulo no ve. Afirmar "no es producción" ahí sería peor
  // que no decir nada.
  assert.strictEqual(projectIdObjetivo({}), null);
});

test('projectIdObjetivo: credencial inexistente o ilegible devuelve null', () => {
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: '/no/existe.json' }), null);
  const roto = credencialFalsa('{ esto no es json');
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: roto }), null);
});

test('projectIdObjetivo: credencial sin project_id devuelve null', () => {
  const ruta = credencialFalsa({ type: 'service_account' });
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: ruta }), null);
});
