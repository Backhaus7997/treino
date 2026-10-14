#!/usr/bin/env node
/**
 * check_emulator_secret_manager.js
 *
 * ¿La firebase-tools del PATH todavía manda los secretos del emulador a
 * CLOUD_SECRET_MANAGER_URL?
 *
 *   npm --prefix functions ci     # la función de prueba usa su firebase-functions
 *   node scripts/check_emulator_secret_manager.js
 *
 * `scripts/emulator.sh` cierra el acceso a Secret Manager de producción
 * apuntando esa variable a un puerto local muerto (bloque "Secretos"). La
 * variable no está documentada: si una versión nueva de firebase-tools la deja
 * de leer, el emulador vuelve a traer los secretos de treino-dev y nada se
 * pone rojo. Esto es lo que se pone rojo. Corre en el job `functions-test` de
 * CI, que instala la firebase-tools de la última versión en cada corrida.
 *
 * Mide de punta a punta, igual que la sonda con la que se encontró el bug:
 * un emulador de Functions REAL, proyecto `demo-`, puertos alternos, una
 * función con un `defineSecret`, y Secret Manager apuntado a un servidor falso
 * en 127.0.0.1 que registra cada pedido. Pasa si, al invocar la función, el
 * pedido del secreto llega al servidor falso SIN credencial (token "owner") y
 * el valor que devolvió es el que ve la función.
 *
 * Cuando pasa, nada sale de 127.0.0.1. El emulador arranca con un entorno de
 * lista blanca (no le llega ninguna variable de credencial) y con HOME en un
 * directorio vacío, y esto falla si igual avisa que encontró ADC. Cuando la
 * variable dejó de leerse —el caso que busca—, el pedido SÍ sale a
 * secretmanager.googleapis.com: sin la credencial del dev, y por un proyecto
 * `demo-` que no existe.
 *
 * Espera a la función pegándole a su URL hasta que deja de dar 404, no a una
 * línea del log: un cambio de redacción de la CLI no tiene por qué ponerlo
 * rojo. Las dos líneas de log que sí mira son para fallar ANTES, no para pasar.
 */

'use strict';

const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const REPO = path.join(__dirname, '..');
const PROYECTO = 'demo-canario-secretos';
const SECRETO = 'CANARIO_SECRETO_FALSO';
const VALOR = 'VALOR-DEL-SECRET-MANAGER-FALSO';
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

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'canario-secretos-'));
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
  fs.writeFileSync(
    path.join(fn, 'index.js'),
    [
      "const { onRequest } = require('firebase-functions/v2/https');",
      "const { defineSecret } = require('firebase-functions/params');",
      `const S = defineSecret('${SECRETO}');`,
      'exports.canario = onRequest({ secrets: [S] }, (req, res) => res.send(JSON.stringify(S.value())));',
    ].join('\n'),
  );

  const pedidos = [];
  const sm = http.createServer((req, res) => {
    pedidos.push({ url: req.url, auth: req.headers.authorization });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ payload: { data: Buffer.from(VALOR).toString('base64') } }));
  });
  await new Promise((r) => sm.listen(0, '127.0.0.1', r));
  const smUrl = `http://127.0.0.1:${sm.address().port}`;

  // Lista blanca, no `process.env` menos lo peligroso: una variable de
  // credencial que nadie anotó acá no llega al emulador.
  const env = { CLOUD_SECRET_MANAGER_URL: smUrl };
  for (const v of ['PATH', 'TMPDIR', 'LANG', 'CI']) {
    if (process.env[v] !== undefined) env[v] = process.env[v];
  }
  // HOME también, y no sólo CLOUDSDK_CONFIG: google-auth-library busca las ADC
  // en `$HOME/.config/gcloud/application_default_credentials.json` y no mira
  // CLOUDSDK_CONFIG. Con sólo ésa, el emulador avisaba "Application Default
  // Credentials detected" (medido).
  env.HOME = path.join(dir, 'home');
  env.XDG_CONFIG_HOME = path.join(dir, 'home', '.config');
  env.CLOUDSDK_CONFIG = path.join(dir, 'home', '.config', 'gcloud');
  fs.mkdirSync(env.CLOUDSDK_CONFIG, { recursive: true });

  const logPath = path.join(dir, 'emulador.log');
  const fd = fs.openSync(logPath, 'w');
  const emu = spawn('firebase', ['emulators:start', '--only', 'functions', '--project', PROYECTO], {
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
  const conAdc = () => /Application Default Credentials detected/.test(log());
  const ADC = 'el emulador encontró credenciales reales; el aislamiento no alcanza';

  try {
    const t0 = Date.now();
    let r;
    // Antes de escuchar, ECONNREFUSED; escuchando pero sin la función cargada, 404.
    for (;;) {
      if (emu.exitCode !== null) return fallar(`el emulador terminó solo (${emu.exitCode}):\n${log()}`);
      // Si no carga la función, el emulador queda "ready" igual y esto esperaría hasta el timeout.
      if (/Failed to load function definition/.test(log())) return fallar(`no cargó la función:\n${log()}`);
      if (conAdc()) return fallar(`${ADC}:\n${log()}`);
      r = await pegar();
      if (r.status !== undefined && r.status !== 404) break;
      if (Date.now() - t0 > ESPERA_MS) {
        return fallar(`la función no respondió en ${ESPERA_MS} ms (último intento: ${JSON.stringify(r)}):\n${log()}`);
      }
      await new Promise((res) => setTimeout(res, 500));
    }
    // El aviso de ADC pudo llegar entre la última mirada al log y el GET.
    if (conAdc()) return fallar(`${ADC}:\n${log()}`);
    if (r.status !== 200) return fallar(`la función respondió ${r.status}: ${r.body}\n${log()}`);
    const visto = r.body;

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
    if (visto !== JSON.stringify(VALOR)) {
      return fallar(`la función vio ${visto}, no el valor del Secret Manager falso.\n${log()}`);
    }
    console.log(`OK: el secreto se pidió a ${smUrl}, sin credencial, y la función vio ese valor.`);
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
