/**
 * test/agent_ledger_release_honesto.test.js
 *
 * QUE `release <scope>` DIGA "liberado" SÓLO CUANDO BORRÓ UNA FILA.
 *
 *   cd scripts && npm test
 *
 * ─── POR QUÉ EXISTE ESTE ARCHIVO ────────────────────────────────────────────
 *
 * `cmd_release` imprimía `liberado: <scope>` desde el `END` de awk, sin mirar
 * si alguna fila había caído. Y las filas sólo caen si su cuarta columna —el
 * worktree— es el worktree actual. Así que el camino más común de limpieza
 * contestaba que sí y no hacía nada:
 *
 *   1. un agente hace `claim X` desde su worktree
 *   2. termina, mergea, y borra el worktree
 *   3. alguien corre `release X` desde la raíz del repo
 *   4. sale `liberado: X` — y `list` sigue mostrando la fila
 *
 * Medido el 2026-10-06 con `trainer-links-rol`. El mismo día había en el ledger
 * un claim de ONCE DÍAS (`checkout-token`) que se había comido varios release
 * de esa forma; lo levantó `prune`, que es lo único que lo podía levantar.
 *
 * ─── POR QUÉ IMPORTA MÁS QUE UN MENSAJE FEO ─────────────────────────────────
 *
 * El ledger existe para que un agente pueda preguntar "¿hay alguien acá?" y
 * creerle a la respuesta. Un claim fantasma hace que `check` frene a un agente
 * sobre un scope que NADIE tiene, durante horas, y el agente no tiene forma de
 * distinguirlo de un claim real. Un `liberado` que miente no es un detalle de
 * salida: es lo que deja el fantasma ahí.
 *
 * Es el criterio de `contarBorradosReales` en `cleanup_rejected_links.js`
 * —contar operaciones emitidas es contar intentos, no resultados— y la regla
 * de AGENTS.md § 11.1: un cartel tranquilizador sin verificar es peor que
 * ningún cartel.
 *
 * ─── EL INVARIANTE ──────────────────────────────────────────────────────────
 *
 *   release <scope> imprime "liberado" ⟺ el ledger tiene una fila menos.
 *
 * Y en el ⟸ que faltaba: cuando no borra, el mensaje tiene que decir DÓNDE
 * está la fila. Es el dato que necesita quien está limpiando el claim de un
 * agente muerto, y era justo el que no se imprimía.
 *
 * ─── LA DECISIÓN DE DISEÑO QUE ESTE ARCHIVO FIJA ────────────────────────────
 *
 * `release <scope>` ahora alcanza también a una fila cuyo worktree YA NO EXISTE
 * EN DISCO, porque ése es el caso legítimo más común y antes su única salida
 * eran las 8h de `prune`. No alcanza a una fila de un worktree que sigue
 * existiendo: ahí puede haber un agente vivo, y arrancarle el claim es el bug
 * que este script existe para evitar.
 *
 * `release` pelado y `release --all` NO miran el worktree muerto: siguen
 * atados a ESTE árbol, que es lo que los hace predecibles. Hay un test por cada
 * uno para que ampliarlos rompa algo en vez de pasar de largo.
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
 * El entorno del hijo se arma desde cero y NO se hereda: el
 * CLAUDE_CODE_SESSION_ID del agente que corre la suite se filtraría a las
 * filas que estos tests escriben a mano. Mismo motivo que en
 * agent_ledger_identidad.test.js.
 */
function entorno(extra = {}) {
  return { PATH: process.env.PATH, HOME: process.env.HOME, ...extra };
}

/** Un repo git descartable. Sin commits: el script no los necesita. */
function repoNuevo(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-release-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const init = spawnSync('git', ['init', '-q', '.'], { cwd: dir, env: entorno() });
  assert.strictEqual(init.status, 0, `git init falló: ${init.stderr}`);
  // El path tal como lo ve el script, no como lo devuelve mkdtemp: en macOS
  // /var es symlink a /private/var y la cuarta columna es una comparación
  // textual.
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: dir, env: entorno() });
  return {
    dir,
    worktree: top.stdout.toString().trim(),
    ledger: path.join(dir, '.git', 'agent-ledger.tsv'),
  };
}

function correr(repo, sess, args) {
  const extra = { AGENT_NAME: `agente-${sess}`, AGENT_SESSION: sess };
  const r = spawnSync('bash', [LEDGER_SH, ...args], { cwd: repo.dir, env: entorno(extra) });
  return { status: r.status, out: r.stdout.toString(), err: r.stderr.toString() };
}

const filas = (repo) =>
  fs.existsSync(repo.ledger)
    ? fs.readFileSync(repo.ledger, 'utf8').split('\n').filter(Boolean)
    : [];
const scopes = (repo) => filas(repo).map((l) => l.split('\t')[4]).sort();

/**
 * Escribe una fila cruda. Las siete columnas se arman a mano a propósito: el
 * caso que importa es el de un worktree que NO es el actual, y eso no se puede
 * producir corriendo `claim`.
 */
function filaCruda(repo, { wt, scope, agente = 'muerto', rama = 'feat/x', sess = 'sess-vieja' }) {
  const ts = Math.floor(Date.now() / 1000);
  fs.appendFileSync(repo.ledger, `${ts}\t${agente}\t${rama}\t${wt}\t${scope}\tnota\t${sess}\n`);
}

/** Un directorio que existe y que NO es el worktree del repo de prueba. */
function dirVivo(t, nombre) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), `${nombre}-`));
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  return d;
}

// ───────────────────────────────────────────────────────────────────────────
// El invariante: "liberado" ⟺ borró.
// ───────────────────────────────────────────────────────────────────────────

test('release <scope> de un worktree QUE YA NO EXISTE: borra y lo dice', (t) => {
  const repo = repoNuevo(t);
  // El caso del 2026-10-06: el agente terminó y se llevó su árbol. Antes de
  // este cambio la única salida eran las 8h de prune.
  const muerto = path.join(repo.worktree, '.claude', 'worktrees', 'wt-link-rol');
  filaCruda(repo, { wt: muerto, scope: 'trainer-links-rol' });

  const r = correr(repo, 'A', ['release', 'trainer-links-rol']);

  assert.deepStrictEqual(scopes(repo), [], 'la fila tiene que caer');
  assert.match(r.out, /^liberado: trainer-links-rol/m);
  assert.match(r.out, /ya no existe en disco/, 'y tiene que decir por qué pudo');
  assert.match(r.out, /wt-link-rol/, 'nombrando el árbol, que es el dato que ubica el claim');
});

test('release <scope> de un worktree VIVO: no borra, y dice dónde está la fila', (t) => {
  const repo = repoNuevo(t);
  const otro = dirVivo(t, 'wt-vivo');
  filaCruda(repo, { wt: otro, scope: '862', agente: 'codex', rama: 'feat/862' });

  const r = correr(repo, 'A', ['release', '862']);

  assert.deepStrictEqual(scopes(repo), ['862'], 'un agente vivo no pierde su claim');
  assert.doesNotMatch(r.out, /^liberado:/m, 'y sobre todo: NO puede decir que liberó');
  assert.match(r.out, /NO liberado/);
  assert.match(r.out, new RegExp(otro.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'el path de la fila es lo que le falta a quien está limpiando');
  assert.match(r.out, /codex/, 'con quién y en qué rama, para poder ir a preguntar');
  assert.match(r.out, /SI existe en disco/, 'y por qué no se la llevó');
});

test('release <scope> de un scope inexistente lo dice en vez de inventar', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'otra cosa']);

  const r = correr(repo, 'A', ['release', 'scope-que-no-existe']);

  assert.deepStrictEqual(scopes(repo), ['862'], 'y no toca lo que sí hay');
  assert.match(r.out, /NO liberado: no hay ningun claim/);
  assert.doesNotMatch(r.out, /^liberado:/m);
});

test('release <scope> del propio worktree sigue diciendo liberado', (t) => {
  const repo = repoNuevo(t);
  correr(repo, 'A', ['claim', '862', 'issue A']);

  const r = correr(repo, 'A', ['release', '862']);

  // No-regresión: el camino que ya andaba tiene que seguir andando, porque es
  // el que corre cada agente al terminar.
  assert.deepStrictEqual(scopes(repo), []);
  assert.match(r.out, /^liberado: 862$/m);
});

test('release <scope> con dos filas del mismo scope informa CUÁNTAS borró', (t) => {
  const repo = repoNuevo(t);
  // Dos sesiones en el mismo árbol sobre el mismo scope: es el estado que el
  // ledger existe para evitar, pero si llega a pasar, el número tiene que ser
  // el real y no "1 porque imprimí una línea".
  correr(repo, 'A', ['claim', '862', 'A']);
  correr(repo, 'B', ['claim', '862', 'B']);

  const r = correr(repo, 'A', ['release', '862']);

  assert.deepStrictEqual(scopes(repo), []);
  assert.match(r.out, /liberado: 862\s+\(2 filas\)/);
});

// ───────────────────────────────────────────────────────────────────────────
// Lo que el worktree muerto NO amplía. Un test por forma: si alguien las
// amplía, que rompa un test en vez de pasar de largo.
// ───────────────────────────────────────────────────────────────────────────

test('release pelado NO se lleva la fila de un worktree muerto', (t) => {
  const repo = repoNuevo(t);
  filaCruda(repo, { wt: path.join(os.tmpdir(), 'arbol-borrado-xyz'), scope: '999' });

  const r = correr(repo, 'A', ['release']);

  // El pelado se lleva lo de ESTE worktree Y ESTA sesión, y nada más. Ensancharlo
  // es el incidente del 2026-08-28 con otro disfraz: un release de rutina que se
  // lleva claims que nadie le pidió.
  assert.deepStrictEqual(scopes(repo), ['999']);
  assert.match(r.out, /liberado: 0 claim\(s\) de esta sesion/);
});

test('release --all NO se lleva la fila de un worktree muerto ajeno', (t) => {
  const repo = repoNuevo(t);
  filaCruda(repo, { wt: path.join(os.tmpdir(), 'arbol-borrado-xyz'), scope: '999' });
  correr(repo, 'A', ['claim', '862', 'propio']);

  const r = correr(repo, 'A', ['release', '--all']);

  // `--all` dice "todo lo de este worktree", no "todo". La fila huérfana sale
  // nombrándola con `release 999`, que es un acto explícito.
  assert.deepStrictEqual(scopes(repo), ['999']);
  assert.match(r.out, /liberado: 1 claim\(s\) de este worktree/);
});

// ───────────────────────────────────────────────────────────────────────────
// La forma en que se compara el worktree muerto.
// ───────────────────────────────────────────────────────────────────────────

test('un worktree muerto NO arrastra al vivo que lo tiene como prefijo', (t) => {
  const repo = repoNuevo(t);
  const base = dirVivo(t, 'bases');
  // `…/wt` está borrado; `…/wt-link-rol` existe y tiene un claim. Sin el
  // centinela de tabs alrededor del path, buscar el path vivo dentro de la
  // lista de muertos matchearía por prefijo y le arrancaríamos el claim a un
  // agente vivo — exactamente el daño que este script existe para evitar.
  const vivo = path.join(base, 'wt');
  fs.mkdirSync(vivo);
  filaCruda(repo, { wt: path.join(base, 'wt-link-rol'), scope: 'muerto' });
  filaCruda(repo, { wt: vivo, scope: 'vivo' });

  assert.match(correr(repo, 'A', ['release', 'muerto']).out, /^liberado: muerto/m);

  const r = correr(repo, 'A', ['release', 'vivo']);
  assert.deepStrictEqual(scopes(repo), ['vivo'], 'el claim del árbol vivo sigue en pie');
  assert.match(r.out, /NO liberado/);
});
