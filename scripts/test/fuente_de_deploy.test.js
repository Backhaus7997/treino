/**
 * test/fuente_de_deploy.test.js
 *
 * El guard que frena un deploy de reglas o índices cuando lo que se va a subir
 * no es idéntico a `origin/develop`.
 *
 *   cd scripts && npm test
 *
 * Por qué existe: el 2026-10-13 se deployaron las reglas de Firestore desde un
 * checkout 58 commits atrás de `main`. Nada lo frenó y producción perdió en
 * silencio las reglas de #1387 y #1395 — un rollback sin conflicto, sin aviso y
 * con el deploy en verde. Los deploys de reglas son manuales y no salen de CI:
 * la única barrera posible está en el momento del deploy.
 *
 * Por qué contra `develop` y no "HEAD contiene `origin/main`": producción ya
 * corre reglas que `main` todavía no tiene (#1431 y #1432 se deployaron desde
 * `develop`). Un guard contra `main` dejaría pasar justo el rollback de esos
 * dos fixes.
 *
 * Todo entra por stub —`leerLocal`, `leerRemoto`, `actualizarRemoto`, `env`—:
 * ningún test toca git ni el filesystem. `node:test` y `node:assert`, sin
 * dependencias nuevas, igual que `credenciales.test.js`.
 */
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const {
  REF_FUENTE,
  VAR_OVERRIDE,
  verificarFuente,
} = require('../lib/fuente_de_deploy');

const REGLAS = "rules_version = '2';\nservice cloud.firestore {\n}\n";

// Arma las dependencias de `verificarFuente` con lo que cada test necesita.
function deps({ local = {}, remoto = {}, fetchFalla = false, env = {} } = {}) {
  return {
    actualizarRemoto: () => {
      if (fetchFalla) throw new Error('fatal: unable to access github.com');
    },
    leerLocal: (archivo) => {
      if (!(archivo in local)) throw new Error(`ENOENT: ${archivo}`);
      return local[archivo];
    },
    leerRemoto: (archivo) => {
      if (!(archivo in remoto)) {
        throw new Error(`fatal: path '${archivo}' does not exist in '${REF_FUENTE}'`);
      }
      return remoto[archivo];
    },
    env,
  };
}

// ── Pasa ───────────────────────────────────────────────────────────────────

test('pasa cuando el archivo es idéntico a origin/develop', () => {
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({ local: { 'firestore.rules': REGLAS }, remoto: { 'firestore.rules': REGLAS } }),
  });
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(r.problemas, []);
});

test('pasa con CRLF en el working tree contra LF en git', () => {
  // La trampa de AGENTS.md §11.2: con `core.autocrlf=true`, git deja el
  // working tree en CRLF y `git show` escribe LF. Comparar bytes crudos haría
  // gritar al guard en TODOS los deploys desde Windows, y un guard que grita
  // siempre se apaga el primer viernes.
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({
      local: { 'firestore.rules': REGLAS.replace(/\n/g, '\r\n') },
      remoto: { 'firestore.rules': REGLAS },
    }),
  });
  assert.strictEqual(r.ok, true);
});

// ── Frena ──────────────────────────────────────────────────────────────────

test('frena cuando el archivo difiere de origin/develop (rama vieja o cambio sin mergear)', () => {
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({
      local: { 'firestore.rules': REGLAS },
      remoto: { 'firestore.rules': REGLAS + '// #1432\n' },
    }),
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.problemas.length, 1);
  assert.strictEqual(r.problemas[0].archivo, 'firestore.rules');
});

test('reporta sólo los archivos que difieren', () => {
  const r = verificarFuente({
    archivos: ['firestore.rules', 'firestore.indexes.json'],
    ...deps({
      local: { 'firestore.rules': REGLAS, 'firestore.indexes.json': '{"indexes":[]}' },
      remoto: { 'firestore.rules': REGLAS, 'firestore.indexes.json': '{"indexes":[1]}' },
    }),
  });
  assert.strictEqual(r.ok, false);
  assert.deepStrictEqual(r.problemas.map((p) => p.archivo), ['firestore.indexes.json']);
});

test('frena si el archivo no existe en origin/develop', () => {
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({ local: { 'firestore.rules': REGLAS }, remoto: {} }),
  });
  assert.strictEqual(r.ok, false);
  assert.match(r.problemas[0].motivo, /no existe|no pude leer/i);
});

test('frena si no puede actualizar origin/develop (falla cerrado)', () => {
  // Con un `origin/develop` local viejo, comparar contra él es comparar contra
  // una mentira: justo el caso que el guard existe para atrapar.
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({
      local: { 'firestore.rules': REGLAS },
      remoto: { 'firestore.rules': REGLAS },
      fetchFalla: true,
    }),
  });
  assert.strictEqual(r.ok, false);
  assert.match(r.problemas[0].motivo, /actualizar/i);
});

// ── Override ───────────────────────────────────────────────────────────────

test(`${VAR_OVERRIDE}=1 deja pasar, pero marcado como override`, () => {
  const r = verificarFuente({
    archivos: ['firestore.rules'],
    ...deps({
      local: { 'firestore.rules': REGLAS },
      remoto: { 'firestore.rules': REGLAS + '// otra cosa\n' },
      env: { [VAR_OVERRIDE]: '1' },
    }),
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.override, true);
  // Los problemas se siguen informando: el override no los esconde.
  assert.strictEqual(r.problemas.length, 1);
});

test('el override sólo se activa con "1" exacto', () => {
  for (const valor of ['true', 'yes', '0', '']) {
    const r = verificarFuente({
      archivos: ['firestore.rules'],
      ...deps({
        local: { 'firestore.rules': REGLAS },
        remoto: { 'firestore.rules': REGLAS + '// x\n' },
        env: { [VAR_OVERRIDE]: valor },
      }),
    });
    assert.strictEqual(r.ok, false, `"${valor}" no debería activar el override`);
  }
});

// ── Cableado: que el guard corra de verdad ─────────────────────────────────
// Un guard que existe pero que nadie llama es peor que ninguno: da la misma
// tranquilidad sin hacer nada (AGENTS.md §11.1).

const ROOT = path.join(__dirname, '..', '..');
const firebaseJson = JSON.parse(fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8'));
const GUARD = 'node scripts/guard_fuente_de_deploy.js';

test('el predeploy de firestore corre el guard sobre reglas e índices, antes que nada', () => {
  const hooks = firebaseJson.firestore.predeploy;
  assert.ok(Array.isArray(hooks), 'firestore.predeploy tiene que ser una lista');
  assert.ok(hooks[0].startsWith(GUARD), `el primer hook tiene que ser el guard, es: ${hooks[0]}`);
  assert.match(hooks[0], /\bfirestore\.rules\b/);
  assert.match(hooks[0], /\bfirestore\.indexes\.json\b/);
});

test('el predeploy de storage corre el guard sobre storage.rules', () => {
  const hooks = firebaseJson.storage.predeploy;
  assert.ok(Array.isArray(hooks), 'storage.predeploy tiene que ser una lista');
  assert.ok(hooks[0].startsWith(GUARD), `el primer hook tiene que ser el guard, es: ${hooks?.[0]}`);
  assert.match(hooks[0], /\bstorage\.rules\b/);
});

test('deploy_rules.js, que no pasa por firebase.json, también corre el guard', () => {
  // Es el camino que ningún default frena (scripts/README.md): sube
  // `firestore.rules` por la API, sin hooks. Si no llama al guard, es la
  // puerta de atrás exacta para repetir el rollback.
  const fuente = fs.readFileSync(path.join(ROOT, 'scripts', 'deploy_rules.js'), 'utf8');
  assert.match(fuente, /require\(['"]\.\/guard_fuente_de_deploy['"]\)/);
  assert.match(fuente, /guardFuente\(\[\s*['"]firestore\.rules['"]\s*\]\)/);
});
