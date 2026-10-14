/**
 * test/guard_fuente_de_deploy_fetch.test.js
 *
 * QUE EL GUARD DE #1433 COMPARE CONTRA UN `origin/develop` DE VERDAD FRESCO, Y
 * QUE UNA CONEXIÓN TRABADA NO CUELGUE EL DEPLOY.
 *
 *   cd scripts && node --test test/guard_fuente_de_deploy_fetch.test.js
 *
 * `fuente_de_deploy.test.js` prueba la lógica con git stubeado. Lo que se rompe
 * acá es el CABLEADO —qué fetch corre el CLI de verdad—, y eso un stub no lo
 * puede ver: por eso estos tests corren git real contra repos sandbox.
 *
 * Cada test arma un remoto bare en un tmpdir y copia el guard ADENTRO del clon:
 * el guard resuelve la raíz por su `__dirname`, así que corre contra el sandbox
 * igual que contra el repo, sin una variable que exista sólo para los tests.
 * Git corre aislado de la configuración de quien corre la suite.
 *
 * El test del servidor trabado tarda ~30 s: es el `http.lowSpeedTime` real del
 * guard. Bajarlo sólo para el test sería probar otro fetch. Y usa http, no
 * https: no cubre el handshake TLS, que `lowSpeedTime` tampoco acota (ver el
 * comentario de `FETCH_DEVELOP`).
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const GUARD = path.join(__dirname, '..', 'guard_fuente_de_deploy.js');
const LIB = path.join(__dirname, '..', 'lib', 'fuente_de_deploy.js');

/** Sin herencia: un `TREINO_DEPLOY_FUERA_DE_DEVELOP=1` exportado pondría todo en verde. */
function entorno(base) {
  const gitconfig = path.join(base, 'gitconfig-vacio');
  if (!fs.existsSync(gitconfig)) fs.writeFileSync(gitconfig, '');
  return {
    PATH: process.env.PATH,
    HOME: base,
    GIT_CONFIG_GLOBAL: gitconfig,
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_AUTHOR_NAME: 'sandbox',
    GIT_AUTHOR_EMAIL: 'sandbox@example.invalid',
    GIT_COMMITTER_NAME: 'sandbox',
    GIT_COMMITTER_EMAIL: 'sandbox@example.invalid',
  };
}

function git(cwd, base, ...args) {
  const r = spawnSync('git', args, { cwd, env: entorno(base), encoding: 'utf8' });
  assert.strictEqual(r.status, 0, `git ${args.join(' ')} falló en ${cwd}:\n${r.stderr}`);
  return r.stdout.trim();
}

/**
 * Un remoto con `main` y `develop` iguales, y un clon `semilla` desde el que
 * se empujan cambios. El guard va commiteado, así que llega a todo clon.
 */
function sandbox(t) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-fuente-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));

  git(base, base, 'init', '--quiet', '--bare', '-b', 'main', 'origin.git');
  git(base, base, 'clone', '--quiet', 'origin.git', 'semilla');
  const semilla = path.join(base, 'semilla');
  fs.mkdirSync(path.join(semilla, 'scripts', 'lib'), { recursive: true });
  fs.copyFileSync(GUARD, path.join(semilla, 'scripts', 'guard_fuente_de_deploy.js'));
  fs.copyFileSync(LIB, path.join(semilla, 'scripts', 'lib', 'fuente_de_deploy.js'));
  fs.writeFileSync(path.join(semilla, 'firestore.rules'), 'regla v1\n');
  git(semilla, base, 'add', '-A');
  git(semilla, base, 'commit', '--quiet', '-m', 'inicial');
  git(semilla, base, 'push', '--quiet', 'origin', 'main', 'main:develop');

  return { base, semilla };
}

/** Corre el guard copiado en `clon`, async: el test del servidor trabado necesita el event loop. */
function correrGuard(clon, base) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const hijo = spawn(
      process.execPath,
      [path.join(clon, 'scripts', 'guard_fuente_de_deploy.js'), 'firestore.rules'],
      { cwd: clon, env: entorno(base) },
    );
    let salida = '';
    hijo.stdout.on('data', (d) => (salida += d));
    hijo.stderr.on('data', (d) => (salida += d));
    // Red de seguridad del TEST, no del guard: sin esto, un guard colgado
    // colgaría la suite entera en vez de ponerla en rojo.
    const matar = setTimeout(() => hijo.kill('SIGKILL'), 60_000);
    hijo.on('exit', (status) => {
      clearTimeout(matar);
      resolve({ status, salida, segundos: (Date.now() - t0) / 1000 });
    });
  });
}

test('clon normal al día con develop → pasa (el refspec explícito no rompe el caso común)', async (t) => {
  const { base } = sandbox(t);
  git(base, base, 'clone', '--quiet', '-b', 'develop', 'origin.git', 'deploy');
  const r = await correrGuard(path.join(base, 'deploy'), base);
  assert.strictEqual(r.status, 0, r.salida);
});

test('clon --single-branch de main con un origin/develop viejo → frena, no compara contra la copia', async (t) => {
  const { base, semilla } = sandbox(t);

  // Un clon que sigue sólo main y que alguna vez trajo develop a mano: tiene
  // `origin/develop`, pero su `remote.origin.fetch` no lo mapea.
  git(base, base, 'clone', '--quiet', '--single-branch', '-b', 'main', 'origin.git', 'deploy');
  const deploy = path.join(base, 'deploy');
  git(deploy, base, 'fetch', '--quiet', 'origin', 'develop:refs/remotes/origin/develop');
  const viejo = git(deploy, base, 'rev-parse', 'origin/develop');

  // develop avanza con una regla nueva —en la vida real, ya deployada—.
  fs.writeFileSync(path.join(semilla, 'firestore.rules'), 'regla v2 (fix)\n');
  git(semilla, base, 'commit', '--quiet', '-am', 'fix de reglas');
  git(semilla, base, 'push', '--quiet', 'origin', 'HEAD:develop');

  const r = await correrGuard(deploy, base);
  assert.strictEqual(r.status, 1, r.salida);
  assert.match(r.salida, /firestore\.rules: difiere de origin\/develop/);
  assert.notStrictEqual(
    git(deploy, base, 'rev-parse', 'origin/develop'),
    viejo,
    'el fetch del guard tiene que mover origin/develop',
  );
});

test('un remoto que acepta la conexión y no manda nada → el guard frena solo, no se cuelga', async (t) => {
  const { base } = sandbox(t);
  git(base, base, 'clone', '--quiet', '-b', 'develop', 'origin.git', 'deploy');
  const deploy = path.join(base, 'deploy');

  const sockets = new Set();
  const mudo = net.createServer((s) => sockets.add(s));
  await new Promise((r) => mudo.listen(0, '127.0.0.1', r));
  t.after(() => {
    for (const s of sockets) s.destroy();
    mudo.close();
  });
  git(deploy, base, 'remote', 'set-url', 'origin', `http://127.0.0.1:${mudo.address().port}/treino.git`);

  const r = await correrGuard(deploy, base);
  assert.strictEqual(r.status, 1, `el guard no terminó solo (${r.segundos}s):\n${r.salida}`);
  assert.match(r.salida, /no pude actualizar origin\/develop/);
  // La causa tiene que llegar al mensaje, y el tiempo tiene que ser el del
  // corte: sin la cota de abajo, un fetch que falla por CUALQUIER otra cosa
  // en medio segundo también pasaba este test.
  assert.match(r.salida, /Operation too slow/);
  assert.ok(r.segundos >= 25 && r.segundos < 50, `tardó ${r.segundos}s; el corte es a los 30`);
});

test('develop reescrita con force-push → el guard la trae igual (el + del refspec)', async (t) => {
  const { base, semilla } = sandbox(t);
  git(base, base, 'clone', '--quiet', '-b', 'develop', 'origin.git', 'deploy');
  const deploy = path.join(base, 'deploy');
  const viejo = git(deploy, base, 'rev-parse', 'origin/develop');

  // Misma regla, otra historia: un `commit --amend` + force-push sobre develop.
  fs.writeFileSync(path.join(semilla, 'LEEME'), 'otra historia\n');
  git(semilla, base, 'add', 'LEEME');
  git(semilla, base, 'commit', '--quiet', '--amend', '-m', 'inicial reescrito');
  git(semilla, base, 'push', '--quiet', '--force', 'origin', 'HEAD:develop');

  // Sin el `+`, el fetch se rechaza por non-fast-forward y el guard frena
  // todo deploy hasta que alguien arregle los refs a mano.
  const r = await correrGuard(deploy, base);
  assert.strictEqual(r.status, 0, r.salida);
  assert.notStrictEqual(git(deploy, base, 'rev-parse', 'origin/develop'), viejo);
});
