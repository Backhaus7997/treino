#!/usr/bin/env node
/**
 * check_emulator_sin_produccion.js
 *
 * ¿La firebase-tools del PATH todavía respeta los dos cierres de
 * `scripts/emulator.sh` que la dejan sin acceso a producción?
 *
 *   npm --prefix functions ci     # la función de prueba usa su firebase-functions
 *   node scripts/check_emulator_sin_produccion.js
 *
 * Los dos cierres dependen de comportamiento NO documentado de firebase-tools,
 * y el job `functions-test` de CI instala la última versión en cada corrida.
 * Si una versión cambia alguno, el cierre desaparece en silencio. Esto es lo
 * que se pone rojo:
 *
 * Los dos viven en `lib/emulador_sin_produccion.sh`:
 *
 *   1. Secretos: el emulador le pide los
 *      `defineSecret` a CLOUD_SECRET_MANAGER_URL. Si la deja de leer, vuelve a
 *      traerlos de Secret Manager de treino-dev.
 *   2. Credenciales: con GOOGLE_APPLICATION_CREDENTIALS
 *      apuntando a la credencial falsa del repo, el runtime usa ésa y el CLI NO
 *      le inyecta el `firebase login`. Si la inyectara igual, FCM volvería a
 *      salir a producción con la cuenta del dev.
 *
 * Mide de punta a punta, igual que las sondas con que se encontraron: un
 * emulador de Functions REAL, puertos alternos, una función con un
 * `defineSecret` que además informa con qué credencial corre, y Secret Manager
 * apuntado a un servidor falso en 127.0.0.1 que registra cada pedido.
 *
 * El emulador arranca a través de `cerrar_produccion` de
 * `lib/emulador_sin_produccion.sh`, el MISMO helper que usa emulator.sh: lo que
 * se mide es ese código, no una copia. Lo único que se pisa después es
 * CLOUD_SECRET_MANAGER_URL, para que apunte a un servidor que registre el
 * pedido en vez de a un puerto muerto; que el helper la ponga en un puerto
 * muerto lo fija `test/emulator_secretos_locales.test.js`.
 *
 * El CLI corre con HOME en un directorio vacío, un entorno de lista blanca y un
 * `firebase login` INVENTADO en ese HOME: para que tenga un login que inyectar,
 * y para que no encuentre ninguno real. El proyecto es `demo-`: la inyección
 * pasa igual (la cuenta sale de `getProjectDefaultAccount`, sin guarda para
 * `demo-`; medido), y con `demo-` el CLI no sale a leer la config del proyecto.
 * Cuando pasa, nada sale de 127.0.0.1. (Una versión anterior de este canario
 * usaba un proyecto no-`demo-` porque decía que con `demo-` no había
 * inyección. Era falso; lo encontró el review del PR.)
 *
 * Espera a la función pegándole a su URL hasta que deja de dar 404, no a una
 * línea del log: un cambio de redacción de la CLI no tiene por qué ponerlo
 * rojo.
 */

'use strict';

const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const REPO = path.join(__dirname, '..');
const FUNCION = path.join(__dirname, 'test', 'fixtures', 'funcion_del_canario.js');
const PROYECTO = 'demo-canario-emulador';
// El client_id de la credencial falsa, ESCRITO acá y no leído del JSON: si
// alguien pegara una credencial real en ese archivo, el canario no la
// aceptaría como "la falsa".
const CLIENT_ID_FALSO = 'credencial-falsa-del-emulador.apps.googleusercontent.com';
const SECRETO = 'CANARIO_SECRETO_FALSO';
const VALOR = 'VALOR-DEL-SECRET-MANAGER-FALSO';
const EMAIL_FALSO = 'login-falso@canario.invalid';
// Lejos de los del emulador real (5001, 4400, 4500), por si hay uno corriendo.
const PUERTOS = { functions: 5181, hub: 4581, logging: 4681 };
const ESPERA_MS = 120_000;

function fallar(msg) {
  console.error(`\nFALLA: ${msg}`);
  process.exitCode = 1;
}

function puertoLibre(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once('error', () => resolve(false));
    s.listen(port, '127.0.0.1', () => s.close(() => resolve(true)));
  });
}

async function main() {
  const modulos = path.join(REPO, 'functions', 'node_modules');
  if (!fs.existsSync(path.join(modulos, 'firebase-functions'))) {
    return fallar(`falta functions/node_modules. Corré: npm --prefix functions ci`);
  }
  const version = spawnSync('firebase', ['--version'], { encoding: 'utf8' });
  if (version.status !== 0) return fallar('no hay `firebase` en el PATH.');
  console.log(`firebase-tools ${version.stdout.trim()}`);

  for (const [nombre, port] of Object.entries(PUERTOS)) {
    if (!(await puertoLibre(port))) return fallar(`el puerto ${port} (${nombre}) está ocupado.`);
  }

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'canario-emulador-'));
  const fn = path.join(dir, 'fn');
  fs.mkdirSync(fn);
  fs.symlinkSync(modulos, path.join(fn, 'node_modules'));
  fs.writeFileSync(
    path.join(dir, 'firebase.json'),
    JSON.stringify({
      functions: { source: 'fn' },
      emulators: {
        functions: { port: PUERTOS.functions },
        hub: { port: PUERTOS.hub },
        logging: { port: PUERTOS.logging },
        ui: { enabled: false },
      },
    }),
  );
  fs.writeFileSync(
    path.join(fn, 'package.json'),
    // El engine de functions/, no el del `node` que corre esto: pueden no ser
    // el mismo (el `firebase` de nvm en 22 y otro `node` antes en el PATH).
    JSON.stringify({ name: 'canario', main: 'index.js', engines: require(path.join(REPO, 'functions', 'package.json')).engines }),
  );
  // La función vive en un fixture y no en un string de este archivo: corre en
  // el emulador, no acá, y su `initializeApp()` es del runtime.
  const funcion = fs.readFileSync(FUNCION, 'utf8');
  if (!funcion.includes(`defineSecret('${SECRETO}')`)) {
    return fallar(`${FUNCION} no declara el secreto ${SECRETO}: el canario no mediría nada.`);
  }
  fs.writeFileSync(path.join(fn, 'index.js'), funcion);

  const pedidos = [];
  const sm = http.createServer((req, res) => {
    pedidos.push({ url: req.url, auth: req.headers.authorization });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ payload: { data: Buffer.from(VALOR).toString('base64') } }));
  });
  await new Promise((r) => sm.listen(0, '127.0.0.1', r));
  const smUrl = `http://127.0.0.1:${sm.address().port}`;

  // Lista blanca, no `process.env` menos lo peligroso: una variable de
  // credencial que nadie anotó acá no llega al emulador. La credencial la pone
  // el helper, no este archivo.
  const env = {};
  for (const v of ['PATH', 'TMPDIR', 'LANG', 'CI']) {
    if (process.env[v] !== undefined) env[v] = process.env[v];
  }
  // HOME, y no sólo CLOUDSDK_CONFIG: google-auth-library busca las ADC en
  // `$HOME/.config/gcloud/` y no mira CLOUDSDK_CONFIG (medido). Y en ese HOME,
  // un `firebase login` inventado, para que el CLI TENGA un login que inyectar.
  env.HOME = path.join(dir, 'home');
  const configstore = path.join(env.HOME, '.config', 'configstore');
  fs.mkdirSync(configstore, { recursive: true });
  fs.writeFileSync(
    path.join(configstore, 'firebase-tools.json'),
    JSON.stringify({
      user: { email: EMAIL_FALSO },
      tokens: { refresh_token: 'refresh-token-falso', access_token: 'access-token-falso', expires_at: Date.now() + 3600e3 },
    }),
  );

  const logPath = path.join(dir, 'emulador.log');
  const fd = fs.openSync(logPath, 'w');
  const helper = path.join(__dirname, 'lib', 'emulador_sin_produccion.sh');
  const arranque =
    'source "$1" && cerrar_produccion "$4" && export CLOUD_SECRET_MANAGER_URL="$2" && ' +
    'exec firebase emulators:start --only functions --project "$3"';
  const emu = spawn('bash', ['-c', arranque, '_', helper, smUrl, PROYECTO, fn], {
    cwd: dir,
    env,
    detached: true,
    stdio: ['ignore', fd, fd],
  });
  const log = () => fs.readFileSync(logPath, 'utf8');

  const url = `http://127.0.0.1:${PUERTOS.functions}/${PROYECTO}/us-central1/canario`;
  /** Un GET con timeout propio: `{ status, body }` o `{ error }`, nunca cuelga. */
  const pegar = () =>
    new Promise((resolve) => {
      const req = http.get(url, { timeout: 30_000 }, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ status: res.statusCode, body }));
      });
      req.on('timeout', () => req.destroy(new Error('sin respuesta en 30 s')));
      req.on('error', (e) => resolve({ error: e.message }));
    });

  try {
    const t0 = Date.now();
    let r;
    // Antes de escuchar, ECONNREFUSED; escuchando pero sin la función cargada, 404.
    for (;;) {
      if (emu.exitCode !== null) return fallar(`el emulador terminó solo (${emu.exitCode}):\n${log()}`);
      // Si no carga la función, el emulador queda "ready" igual y esto esperaría hasta el timeout.
      if (/Failed to load function definition/.test(log())) return fallar(`no cargó la función:\n${log()}`);
      r = await pegar();
      if (r.status !== undefined && r.status !== 404) break;
      if (Date.now() - t0 > ESPERA_MS) {
        return fallar(`la función no respondió en ${ESPERA_MS} ms (último intento: ${JSON.stringify(r)}):\n${log()}`);
      }
      await new Promise((res) => setTimeout(res, 500));
    }
    if (r.status !== 200) return fallar(`la función respondió ${r.status}: ${r.body}\n${log()}`);
    const visto = JSON.parse(r.body);

    // ── 1. Secretos ──
    const esperado = `/v1/projects/${PROYECTO}/secrets/${SECRETO}/versions/latest:access`;
    const delSecreto = pedidos.filter((p) => p.url === esperado);
    if (delSecreto.length === 0) {
      return fallar(
        `el secreto NO se le pidió a CLOUD_SECRET_MANAGER_URL (${smUrl}).\n` +
          'Esta firebase-tools resuelve los defineSecret por otro lado: el cierre de\n' +
          '`scripts/emulator.sh` ya no cierra nada y el emulador vuelve a traer los\n' +
          'secretos de treino-dev. Pedidos que sí llegaron: ' +
          `${JSON.stringify(pedidos)}\nLog del emulador:\n${log()}`,
      );
    }
    const auth = delSecreto.map((p) => p.auth);
    if (auth.some((a) => a !== 'Bearer owner')) {
      return fallar(
        `el pedido llevó una credencial: ${JSON.stringify(auth)}.\n` +
          'emulator.sh confía en que un origin http: no cargue ninguna.',
      );
    }
    if (visto.secreto !== VALOR) {
      return fallar(`la función vio ${JSON.stringify(visto.secreto)}, no el valor del Secret Manager falso.\n${log()}`);
    }

    // ── 2. Credenciales ──
    if (visto.clientId !== CLIENT_ID_FALSO) {
      return fallar(
        `el runtime corre con otra credencial (${visto.credencial}, client_id ` +
          `${JSON.stringify(visto.clientId)}), no con la falsa del repo.\n` +
          'Si es el del cliente OAuth de firebase-tools, el CLI le inyectó el `firebase login`\n' +
          'aunque el helper le pasó una credencial: el cierre de `scripts/emulator.sh` ya no\n' +
          `cierra nada y FCM vuelve a salir a producción con la cuenta del dev.\n${log()}`,
      );
    }
    console.log(`OK: el secreto se pidió a ${smUrl}, sin credencial, y la función vio ese valor.`);
    console.log('OK: el runtime corre con la credencial falsa del repo, aunque el CLI tenía un login para inyectarle.');
  } finally {
    try {
      process.kill(-emu.pid, 'SIGINT');
    } catch {}
    await new Promise((r) => setTimeout(r, 3000));
    try {
      process.kill(-emu.pid, 'SIGKILL');
    } catch {}
    sm.close();
    // El symlink primero: que el borrado del directorio no tenga cómo llegar
    // a functions/node_modules.
    fs.unlinkSync(path.join(fn, 'node_modules'));
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

main().catch((e) => fallar(e.stack || String(e)));
