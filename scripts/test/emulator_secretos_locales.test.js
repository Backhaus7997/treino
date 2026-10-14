/**
 * test/emulator_secretos_locales.test.js
 *
 * QUE EL EMULADOR DE FUNCTIONS DE `scripts/emulator.sh` NO PUEDA TRAER LOS
 * SECRETOS DE PRODUCCIÓN.
 *
 *   cd scripts && npm test
 *
 * ─── EL BUG ─────────────────────────────────────────────────────────────────
 *
 * Al invocar una función con `defineSecret`, el emulador le pide el valor a
 * Secret Manager del proyecto de `--project`, y `emulator.sh` levanta con
 * `--project treino-dev`: producción. Medido el 2026-10-14 (firebase-tools
 * 15.19.0, proyecto `demo-sonda-secretos`, Secret Manager falso en local): el
 * pedido sale al invocar, y el valor llega al proceso de la función. Que con
 * treino-dev eso sean la RESEND_API_KEY y el MP_ACCESS_TOKEN reales es
 * leído, no medido: contra producción no se invocó nada. Detalle en el bloque
 * "Secretos" de `emulator.sh`.
 *
 * El cierre es CLOUD_SECRET_MANAGER_URL apuntado a un puerto local muerto. Lo
 * que importa es el entorno con el que arranca `firebase`, así que, como en
 * `emulator_genera_reglas.test.js`, se corre el `emulator.sh` REAL en un repo
 * de juguete con `firebase` reemplazado por un stub que fotografía su entorno.
 * Un `rg` sobre el script lo cumpliría también una línea comentada, un
 * `export` en el branch que no corre o uno que va DESPUÉS del `exec`.
 *
 * Que la firebase-tools instalada respete la variable NO se mide acá: este job
 * de CI no la tiene. Eso lo hace `scripts/check_emulator_secret_manager.js` en
 * `functions-test`.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');
const COPIADOS = ['emulator.sh', 'strip_rules.js', path.join('lib', 'java21.sh')];

const STUBS = {
  // Con `exec`, lo que tenga el entorno acá es lo que tendría el emulador.
  firebase: [
    '#!/usr/bin/env bash',
    'printf "%s\\n" "$*" > "$FOTO_DIR/argv"',
    'if [ -n "${CLOUD_SECRET_MANAGER_URL+x}" ]; then',
    '  printf "%s" "$CLOUD_SECRET_MANAGER_URL" > "$FOTO_DIR/sm_url"',
    'fi',
  ].join('\n'),
  npm: '#!/usr/bin/env bash\nexit 0',
  java: '#!/usr/bin/env bash\necho \'openjdk version "21.0.8" 2025-07-15\' >&2',
};

function repoDeJuguete(t) {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'emulator-secretos-'));
  t.after(() => fs.rmSync(raiz, { recursive: true, force: true }));

  for (const rel of COPIADOS) {
    const destino = path.join(raiz, 'scripts', rel);
    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.copyFileSync(path.join(SCRIPTS_DIR, rel), destino);
  }
  fs.copyFileSync(path.join(SCRIPTS_DIR, '..', 'firebase.json'), path.join(raiz, 'firebase.json'));
  fs.writeFileSync(
    path.join(raiz, 'firestore.rules'),
    "rules_version = '2';\nservice cloud.firestore {\n  match /databases/{database}/documents {}\n}\n",
  );
  fs.mkdirSync(path.join(raiz, 'functions', 'node_modules'), { recursive: true });

  const bin = path.join(raiz, 'bin');
  fs.mkdirSync(bin);
  for (const [nombre, cuerpo] of Object.entries(STUBS)) {
    fs.writeFileSync(path.join(bin, nombre), `${cuerpo}\n`, { mode: 0o755 });
  }
  const foto = path.join(raiz, 'foto');
  fs.mkdirSync(foto);
  return { raiz, bin, foto };
}

function correr(repo, extra = {}) {
  const env = { ...process.env };
  delete env.SKIP_FUNCTIONS;
  delete env.CLOUD_SECRET_MANAGER_URL;
  Object.assign(env, extra, {
    PATH: [repo.bin, path.dirname(process.execPath), process.env.PATH].join(path.delimiter),
    FOTO_DIR: repo.foto,
  });
  const r = spawnSync('bash', [path.join(repo.raiz, 'scripts', 'emulator.sh')], {
    cwd: repo.raiz,
    env,
    encoding: 'utf8',
    timeout: 30_000,
  });
  assert.strictEqual(r.error, undefined, `no pude correr emulator.sh: ${r.error}`);
  const leer = (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null);
  return {
    code: r.status,
    salida: r.stdout + r.stderr,
    argv: leer(path.join(repo.foto, 'argv')),
    smUrl: leer(path.join(repo.foto, 'sm_url')),
  };
}

/** Resuelve con el código de error de conectarse, o 'CONECTO' si alguien atendió. */
function intentarConectar(host, port) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port });
    s.setTimeout(3000);
    s.on('connect', () => {
      s.destroy();
      resolve('CONECTO');
    });
    s.on('timeout', () => {
      s.destroy();
      resolve('TIMEOUT');
    });
    s.on('error', (e) => resolve(e.code));
  });
}

// El modo liviano hoy no levanta Functions, y se mide igual: el día que las
// sume, el cierre tiene que estar. `only` distingue qué branch arrancó.
const MODOS = [
  { nombre: 'SKIP_FUNCTIONS=1', env: { SKIP_FUNCTIONS: '1' }, only: 'firestore,auth,storage' },
  { nombre: 'modo completo', env: {}, only: 'firestore,auth,functions,storage' },
];

function arranco(r, modo) {
  assert.strictEqual(r.code, 0, `emulator.sh salió con ${r.code}.\nSALIDA:\n${r.salida}`);
  assert.ok(r.argv, `no llamó a \`firebase\` — el test no mide nada.\nSALIDA:\n${r.salida}`);
  assert.ok(
    r.argv.includes('emulators:start') && r.argv.includes(`--only ${modo.only} `),
    `arrancó otra cosa: ${r.argv}`,
  );
}

for (const modo of MODOS) {
  test(`${modo.nombre}: el emulador arranca con Secret Manager en un puerto local donde no escucha nadie`, async (t) => {
    const r = correr(repoDeJuguete(t), modo.env);
    arranco(r, modo);

    assert.notStrictEqual(
      r.smUrl,
      null,
      'el emulador arrancó SIN CLOUD_SECRET_MANAGER_URL: con Functions, cada defineSecret\n' +
        'que se invoque sale a Secret Manager de treino-dev, o sea PRODUCCIÓN.\n' +
        `SALIDA:\n${r.salida}`,
    );
    const u = new URL(r.smUrl);
    // `http:` es lo que hace que el CLI no cargue credencial (token "owner").
    assert.strictEqual(u.protocol, 'http:', `con ${u.protocol} el CLI manda una credencial real: ${r.smUrl}`);
    const host = u.hostname.replace(/^\[|\]$/g, '');
    assert.ok(['127.0.0.1', '::1', 'localhost'].includes(host), `no es loopback: ${r.smUrl}`);

    // Que nadie atienda se mide, no se supone: si algo escuchara ahí, recibiría
    // los pedidos de secretos y podría contestarlos.
    const resultado = await intentarConectar(host, Number(u.port || 80));
    assert.strictEqual(resultado, 'ECONNREFUSED', `${r.smUrl} no está muerto: ${resultado}`);
  });

  test(`${modo.nombre}: un CLOUD_SECRET_MANAGER_URL heredado del entorno se pisa`, (t) => {
    const r = correr(repoDeJuguete(t), {
      ...modo.env,
      CLOUD_SECRET_MANAGER_URL: 'https://secretmanager.googleapis.com',
    });
    arranco(r, modo);
    assert.ok(r.smUrl, `no llegó CLOUD_SECRET_MANAGER_URL a firebase.\nSALIDA:\n${r.salida}`);
    assert.ok(
      !r.smUrl.includes('googleapis.com'),
      `el emulador arrancó con el Secret Manager de verdad: ${r.smUrl}`,
    );
  });
}
