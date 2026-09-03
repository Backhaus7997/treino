/**
 * test/agent_ledger_identidad.test.js
 *
 * QUE LA IDENTIDAD DE UN AGENTE SEA LA SESIÓN Y NO EL ÁRBOL DE TRABAJO.
 *
 *   cd scripts && npm test
 *
 * ─── POR QUÉ EXISTE ESTE ARCHIVO ────────────────────────────────────────────
 *
 * `agent-ledger.sh` se rompió dos veces por el mismo motivo, y ninguna de las
 * dos se vio leyendo el diff.
 *
 * La primera (#875 / #877) fueron siete formas de romperlo con valores que el
 * script no controla. La segunda salió DESPUÉS de ese merge, mirando el ledger
 * real: `release` sin scope se llevaba los claims de las sesiones hermanas, y
 * `check` contestaba `libre` sobre un scope que ya tenía dueño. Las dos veces
 * el código se leía bien. Las dos veces el bug estaba en una suposición que no
 * está escrita en ninguna línea:
 *
 *   "un worktree = un agente"
 *
 * Es falsa. Varias sesiones de la misma herramienta comparten árbol todo el
 * tiempo. Pasó el 2026-08-28: tres claims (`862`, `863`, `agent-ledger-
 * hardening`) con `wt=/Users/martinbackhaus/treino`, una sesión corrió
 * `release` y se llevó los tres. Las otras dos siguieron creyendo que tenían
 * el claim mientras el ledger decía que el scope estaba libre — o sea, el
 * estado exacto que el script existe para evitar.
 *
 * Una suposición implícita no la ve ni un diff ni una revisión por líneas. Lo
 * único que la ve es CORRER EL SCRIPT CON DOS SESIONES Y MIRAR LA SALIDA.
 *
 * ─── EL INVARIANTE ──────────────────────────────────────────────────────────
 *
 *   Ninguna sesión pierde su claim sin haberlo pedido, y ninguna arranca sobre
 *   un scope que otra ya tiene.
 *
 * Formalmente, para dos sesiones A y B en el MISMO worktree:
 *
 *   claim(A, s)  ⟹  check(B, s) frena       ∧  release(B) deja s en pie
 *
 * Cada test de abajo levanta el script REAL en un subproceso, sobre un repo
 * git descartable, con el entorno limpiado de toda variable de sesión heredada
 * — si el proceso de test filtrara su CLAUDE_CODE_SESSION_ID, los casos "sin
 * id" medirían otra cosa.
 *
 * ─── LO QUE ESTE ARCHIVO TAMBIÉN FIJA ───────────────────────────────────────
 *
 * Dos degradaciones deliberadas, acá por escrito para que cambiarlas rompa un
 * test en vez de pasar de largo:
 *
 *   - Dos sesiones SIN id (herramienta que no publica ninguna y sin
 *     AGENT_SESSION) siguen siendo indistinguibles entre sí. No es un
 *     descuido: es el peor caso honesto, igual de malo que antes de este
 *     cambio y no peor. La salida es exportar AGENT_SESSION.
 *   - Una fila SIN columna de sesión (escrita por la versión anterior del
 *     script) no se puede atribuir. `check` se calla —el falso positivo contra
 *     tu propia fila es lo caro, AGENTS.md § 11.1— y `release` pelado no se la
 *     lleva —no borrar lo que no podés probar que es tuyo—. Muere por `prune`.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const LEDGER_SH = path.join(__dirname, '..', 'agent-ledger.sh');

/**
 * El entorno del hijo se arma desde cero y NO se hereda.
 *
 * Si pasara `process.env`, el CLAUDE_CODE_SESSION_ID del agente que corre la
 * suite se filtraría a los casos que prueban justamente qué pasa SIN id de
 * sesión, y esos tests pasarían por el motivo equivocado. PATH es lo único que
 * hace falta: el script sólo llama a git, awk, sed, tr y date.
 */
function entorno(extra = {}) {
  return { PATH: process.env.PATH, HOME: process.env.HOME, ...extra };
}

/** Un repo git descartable. Sin commits: el script no los necesita. */
function repoNuevo(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-ledger-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const init = spawnSync('git', ['init', '-q', '.'], { cwd: dir, env: entorno() });
  assert.strictEqual(init.status, 0, `git init falló: ${init.stderr}`);
  // El path tal como lo ve el script: en macOS /var es symlink a /private/var,
  // así que el mkdtemp de node y el rev-parse del script NO coinciden como
  // texto — y el campo del worktree es una comparación textual.
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: dir, env: entorno() });
  return { dir, worktree: top.stdout.toString().trim(), ledger: path.join(dir, '.git', 'agent-ledger.tsv') };
}

/** Corre el script como la sesión `sess`. `sess: null` = herramienta sin id. */
function correr(repo, sess, args) {
  const extra = { AGENT_NAME: sess === null ? 'sin-id' : `agente-${sess}` };
  if (sess !== null) extra.AGENT_SESSION = sess;
  const r = spawnSync('bash', [LEDGER_SH, ...args], { cwd: repo.dir, env: entorno(extra) });
  return { status: r.status, out: r.stdout.toString(), err: r.stderr.toString() };
}

const filas = (repo) =>
  fs.existsSync(repo.ledger)
    ? fs.readFileSync(repo.ledger, 'utf8').split('\n').filter(Boolean)
    : [];
const scopes = (repo) => filas(repo).map((l) => l.split('\t')[4]).sort();

// ───────────────────────────────────────────────────────────────────────────
// El invariante, que es el motivo de todo el archivo.
// ───────────────────────────────────────────────────────────────────────────

test('check frena sobre el scope de otra sesión del MISMO worktree', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'issue A']);

  const r = correr(repo, 'B', ['check', '862']);

  assert.notStrictEqual(r.status, 0, 'B tiene que frenar: 862 ya es de A');
  assert.match(r.err, /YA HAY ALGUIEN EN '862'/);
  assert.match(r.err, /ESTE MISMO worktree/, 'y tiene que decir que es un árbol compartido');
});

test('check NO avisa sobre el claim propio', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'issue A']);

  const r = correr(repo, 'A', ['check', '862']);

  assert.strictEqual(r.status, 0, 'avisarle a A sobre A es la advertencia falsa de § 11.1');
  assert.match(r.out, /libre: 862/);
});

test('CODEX_THREAD_ID alcanza como id: dos sesiones de Codex NO se pisan', (t) => {
  const repo = repoNuevo(t);
  // Este caso salió de la review de Codex sobre el PR que trajo `session()`:
  // `detect_agent` ya reconocía a Codex por CODEX_HOME, pero `session()` lo
  // dejaba en '?', así que dos hilos de Codex en el mismo árbol seguían siendo
  // el bug original. El id lo publica Codex; acá se prueba que el script lo
  // LEE, que es lo único que este repo controla.
  const codex = (hilo, args) =>
    spawnSync('bash', [LEDGER_SH, ...args], {
      cwd: repo.dir,
      env: entorno({ AGENT_NAME: 'codex', CODEX_HOME: '/tmp/codex', CODEX_THREAD_ID: hilo }),
    });

  codex('hilo-1', ['claim', '862', 'issue del hilo 1']);
  assert.strictEqual(filas(repo)[0].split('\t')[6], 'hilo-1', 'el id tiene que llegar al TSV');

  assert.notStrictEqual(codex('hilo-2', ['check', '862']).status, 0, 'el hilo 2 tiene que frenar');

  codex('hilo-2', ['release']);
  assert.deepStrictEqual(scopes(repo), ['862'], 'y no llevarse el claim del hilo 1');
});

test('AGENT_SESSION le gana a cualquier id detectado', (t) => {
  const repo = repoNuevo(t);
  spawnSync('bash', [LEDGER_SH, 'claim', '862', 'x'], {
    cwd: repo.dir,
    env: entorno({ AGENT_NAME: 'codex', CODEX_THREAD_ID: 'hilo-1', AGENT_SESSION: 'a-mano' }),
  });

  // El override manual es la salida documentada para toda herramienta que no
  // publique un id propio. Si un detectado le ganara, esa salida no existiría.
  assert.strictEqual(filas(repo)[0].split('\t')[6], 'a-mano');
});

test('release sin scope se lleva lo propio y deja en pie lo ajeno', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'issue A']);
  correr(repo, 'B', ['claim', '863', 'issue B']);

  const r = correr(repo, 'B', ['release']);

  assert.deepStrictEqual(scopes(repo), ['862'], 'el claim de A tiene que sobrevivir');
  assert.match(r.out, /quedan 1 claim/, 'y B tiene que enterarse de que dejó algo atrás');
  assert.match(r.out, /release --all/, 'con la salida para barrerlo si de verdad quiere');
});

test('release --all sí barre todo el worktree', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'a']);
  correr(repo, 'B', ['claim', '863', 'b']);

  const r = correr(repo, 'B', ['release', '--all']);

  assert.deepStrictEqual(scopes(repo), []);
  assert.match(r.out, /no eran de esta sesion/, 'y avisa cuántos no eran suyos');
});

test('release <scope> libera lo ajeno pero lo dice', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'issue A']);

  // Es la única salida manual para limpiar el claim de un agente que murió,
  // así que sigue funcionando entre sesiones. Lo que no puede es ser silencioso.
  const r = correr(repo, 'B', ['release', '862']);

  assert.deepStrictEqual(scopes(repo), []);
  assert.match(r.out, /no era de esta sesion/);
});

test('otro worktree sigue avisando', (t) => {
  const repo = repoNuevo(t);
  fs.writeFileSync(repo.ledger, `${Math.floor(Date.now() / 1000)}\tlejano\tfeat\t/otro/arbol\t888\tlejos\tsess-X\n`);

  const r = correr(repo, 'A', ['check', '888']);

  assert.notStrictEqual(r.status, 0, 'no-regresión: esto ya andaba y tiene que seguir andando');
  assert.doesNotMatch(r.err, /ESTE MISMO worktree/);
});

// ───────────────────────────────────────────────────────────────────────────
// El formato del TSV. Estos dos fallan si alguien agrega una columna octava
// detrás de un campo que puede venir vacío.
// ───────────────────────────────────────────────────────────────────────────

test('una nota vacía no corre la columna de sesión', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862']); // sin nota

  const campos = filas(repo)[0].split('\t');
  assert.strictEqual(campos.length, 7, 'siete columnas siempre');
  assert.strictEqual(campos[5], '?', 'la nota vacía se escribe ?: read con IFS=tab colapsa tabs seguidos');
  assert.strictEqual(campos[6], 'A', 'y por eso la sesión sigue en su columna');

  // La prueba de que importa: si la sesión se hubiera leído como nota, B no la
  // vería y `check` volvería a contestar "libre" sobre un scope con dueño.
  assert.notStrictEqual(correr(repo, 'B', ['check', '862']).status, 0);
});

test('el ? de una nota vacía no se muestra como si fuera una nota', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862']);

  assert.doesNotMatch(correr(repo, 'A', ['list']).out, /^\s+\?$/m);
});

// ───────────────────────────────────────────────────────────────────────────
// Las dos degradaciones deliberadas. Fijadas a propósito: si alguien las
// cambia, que sea rompiendo un test y no sin enterarse.
// ───────────────────────────────────────────────────────────────────────────

test("sesión '?' con sesión propia conocida: avisa, y no es un falso positivo", (t) => {
  const repo = repoNuevo(t);
  correr(repo, null, ['claim', '555', 'de una herramienta sin id']);

  // A escribe su id real en cada claim. Si la fila dice '?', A puede PROBAR
  // que no es suya. Callarse acá sería el bug original con otro disfraz.
  assert.notStrictEqual(correr(repo, 'A', ['check', '555']).status, 0);
});

test("dos sesiones sin id siguen siendo indistinguibles (degradación aceptada)", (t) => {
  const repo = repoNuevo(t);
  correr(repo, null, ['claim', '555', 'sin id']);

  // Documentado, no accidental: sin un id no hay con qué separarlas, y esto es
  // exactamente lo que hacía el script antes del cambio. La salida es
  // AGENT_SESSION, no un heurístico que adivine.
  assert.strictEqual(correr(repo, null, ['check', '555']).status, 0);
});

test('fila sin columna de sesión: check se calla, release pelado no la toca', (t) => {
  const repo = repoNuevo(t);
  // Seis columnas: el formato que escribía la versión anterior del script.
  fs.writeFileSync(repo.ledger, `${Math.floor(Date.now() / 1000)}\tviejo\tmain\t${repo.worktree}\t777\tnota vieja\n`);

  assert.match(correr(repo, 'A', ['list']).out, /777/, 'se sigue parseando');
  assert.strictEqual(correr(repo, 'A', ['check', '777']).status, 0, 'puede ser propia: § 11.1');

  correr(repo, 'A', ['release']);
  assert.deepStrictEqual(scopes(repo), ['777'], 'no borrar lo que no podés probar que es tuyo');

  correr(repo, 'A', ['release', '777']);
  assert.deepStrictEqual(scopes(repo), [], 'pero a mano sí sale');
});
