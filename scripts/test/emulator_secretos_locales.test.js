/**
 * test/emulator_secretos_locales.test.js
 *
 * QUE EL EMULADOR DE FUNCTIONS DE `scripts/emulator.sh` NO PUEDA TRAER LOS
 * SECRETOS DE PRODUCCIÓN NI USAR LAS CREDENCIALES REALES DEL DEV.
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
 * de CI no la tiene. Eso lo hace `scripts/check_emulator_sin_produccion.js` en
 * `functions-test`, y lo mismo para la credencial de abajo.
 *
 * ─── Y LAS CREDENCIALES ─────────────────────────────────────────────────────
 *
 * Las APIs sin emulador (FCM) salían con las ADC o el `firebase login` del dev
 * (`lib/emulador_sin_produccion.sh`). El cierre es exportar
 * GOOGLE_APPLICATION_CREDENTIALS a `lib/credencial_falsa_del_emulador.json`.
 * El stub fotografía la variable Y el archivo al que apunta en el instante del
 * `exec`: eso es lo que leería el runtime. Si el archivo falta o no sirve, el
 * CLI le inyectaría el login al runtime, así que ahí el script tiene que NO
 * arrancar.
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
const LOOPBACK = ['127.0.0.1', '::1', 'localhost'];
const CREDENCIAL = path.join('lib', 'credencial_falsa_del_emulador.json');
const COPIADOS = [
  'emulator.sh',
  'strip_rules.js',
  path.join('lib', 'java21.sh'),
  path.join('lib', 'emulador_sin_produccion.sh'),
  CREDENCIAL,
];

const STUBS = {
  // Con `exec`, lo que tenga el entorno acá es lo que tendría el emulador.
  firebase: [
    '#!/usr/bin/env bash',
    'printf "%s\\n" "$*" > "$FOTO_DIR/argv"',
    'if [ -n "${CLOUD_SECRET_MANAGER_URL+x}" ]; then',
    '  printf "%s" "$CLOUD_SECRET_MANAGER_URL" > "$FOTO_DIR/sm_url"',
    'fi',
    'if [ -n "${STORAGE_BUCKET_URL+x}" ]; then printf "%s" "$STORAGE_BUCKET_URL" > "$FOTO_DIR/bucket"; fi',
    'if [ -n "${GOOGLE_APPLICATION_CREDENTIALS+x}" ]; then',
    '  printf "%s" "$GOOGLE_APPLICATION_CREDENTIALS" > "$FOTO_DIR/gac"',
    '  if [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then cp "$GOOGLE_APPLICATION_CREDENTIALS" "$FOTO_DIR/gac_contenido"; fi',
    'fi',
  ].join('\n'),
  npm: '#!/usr/bin/env bash\nexit 0',
  java: '#!/usr/bin/env bash\necho \'openjdk version "21.0.8" 2025-07-15\' >&2',
};

/**
 * Los campos de la credencial falsa, ESCRITOS acá y no leídos del archivo: si
 * alguien pegara una credencial real en `credencial_falsa_del_emulador.json`
 * "para probar FCM en local", comparar el archivo contra sí mismo daría verde
 * y la credencial quedaría commiteada (review del PR).
 */
const CAMPOS_FALSOS = {
  type: 'authorized_user',
  client_id: 'credencial-falsa-del-emulador.apps.googleusercontent.com',
  client_secret: 'no-es-un-secreto',
  refresh_token: 'no-es-un-token',
};

/**
 * `credencial`: null = la del repo; 'falta' = se borra; otro string = ese contenido.
 * `envFunctions`: { nombreDeArchivo: contenido } escritos en `functions/`;
 *   `null` = un directorio, `{ symlink: destino }` = un symlink.
 * `sinFunctions`: no crea `functions/`.
 */
function repoDeJuguete(t, { credencial = null, envFunctions = {}, sinFunctions = false } = {}) {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'emulator-secretos-'));
  t.after(() => fs.rmSync(raiz, { recursive: true, force: true }));

  for (const rel of COPIADOS) {
    const destino = path.join(raiz, 'scripts', rel);
    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.copyFileSync(path.join(SCRIPTS_DIR, rel), destino);
  }
  const credDestino = path.join(raiz, 'scripts', CREDENCIAL);
  if (credencial === 'falta') fs.rmSync(credDestino);
  else if (credencial !== null) fs.writeFileSync(credDestino, credencial);
  fs.copyFileSync(path.join(SCRIPTS_DIR, '..', 'firebase.json'), path.join(raiz, 'firebase.json'));
  fs.writeFileSync(
    path.join(raiz, 'firestore.rules'),
    "rules_version = '2';\nservice cloud.firestore {\n  match /databases/{database}/documents {}\n}\n",
  );
  if (!sinFunctions) fs.mkdirSync(path.join(raiz, 'functions', 'node_modules'), { recursive: true });
  for (const [nombre, contenido] of Object.entries(envFunctions)) {
    const destino = path.join(raiz, 'functions', nombre);
    if (contenido === null) fs.mkdirSync(destino);
    else if (typeof contenido === 'object') fs.symlinkSync(contenido.symlink, destino);
    else fs.writeFileSync(destino, contenido);
  }

  const bin = path.join(raiz, 'bin');
  fs.mkdirSync(bin);
  for (const [nombre, cuerpo] of Object.entries(STUBS)) {
    fs.writeFileSync(path.join(bin, nombre), `${cuerpo}\n`, { mode: 0o755 });
  }
  const foto = path.join(raiz, 'foto');
  fs.mkdirSync(foto);
  return { raiz, bin, foto };
}

/** `cwd`: relativo a la raíz del repo de juguete; por defecto, la raíz. */
function correr(repo, extra = {}, { cwd = '.' } = {}) {
  const env = { ...process.env };
  delete env.SKIP_FUNCTIONS;
  delete env.CLOUD_SECRET_MANAGER_URL;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  Object.assign(env, extra, {
    PATH: [repo.bin, path.dirname(process.execPath), process.env.PATH].join(path.delimiter),
    FOTO_DIR: repo.foto,
  });
  const r = spawnSync('bash', [path.join(repo.raiz, 'scripts', 'emulator.sh')], {
    cwd: path.join(repo.raiz, cwd),
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
    bucket: leer(path.join(repo.foto, 'bucket')),
    gac: leer(path.join(repo.foto, 'gac')),
    gacContenido: leer(path.join(repo.foto, 'gac_contenido')),
  };
}

/** Lo que el runtime leería: la credencial falsa del repo, y no otra. */
function esLaCredencialFalsa(r) {
  assert.notStrictEqual(
    r.gac,
    null,
    'el emulador arrancó SIN GOOGLE_APPLICATION_CREDENTIALS: el runtime de Functions usa las\n' +
      'ADC o el firebase login del dev, y FCM sale a producción con ellas.\n' +
      `SALIDA:\n${r.salida}`,
  );
  assert.ok(path.isAbsolute(r.gac), `ruta relativa: el runtime corre en functions/, no acá: ${r.gac}`);
  assert.notStrictEqual(r.gacContenido, null, `GOOGLE_APPLICATION_CREDENTIALS apunta a algo que no existe: ${r.gac}`);
  const cred = JSON.parse(r.gacContenido);
  for (const [campo, valor] of Object.entries(CAMPOS_FALSOS)) {
    assert.strictEqual(cred[campo], valor, `${campo} no es el de la credencial falsa: ${r.gac}`);
  }
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
    assert.ok(LOOPBACK.includes(host), `no es loopback: ${r.smUrl}`);

    // Que nadie atienda se mide, no se supone: si algo escuchara ahí, recibiría
    // los pedidos de secretos y podría contestarlos.
    const resultado = await intentarConectar(host, Number(u.port || 80));
    assert.strictEqual(resultado, 'ECONNREFUSED', `${r.smUrl} no está muerto: ${resultado}`);
  });

  test(`${modo.nombre}: un CLOUD_SECRET_MANAGER_URL heredado del entorno se pisa`, (t) => {
    const heredado = 'https://secretmanager.googleapis.com';
    const r = correr(repoDeJuguete(t), { ...modo.env, CLOUD_SECRET_MANAGER_URL: heredado });
    arranco(r, modo);
    assert.ok(r.smUrl, `no llegó CLOUD_SECRET_MANAGER_URL a firebase.\nSALIDA:\n${r.salida}`);
    assert.notStrictEqual(r.smUrl, heredado, 'el emulador arrancó con el Secret Manager de verdad');
    // El host parseado, no un substring de la URL: `includes('googleapis.com')`
    // dejaba pasar cualquier host que no lo contuviera, loopback o no.
    const host = new URL(r.smUrl).hostname.replace(/^\[|\]$/g, '');
    assert.ok(LOOPBACK.includes(host), `el heredado se pisó con un host que no es loopback: ${r.smUrl}`);
  });

  test(`${modo.nombre}: el emulador arranca con la credencial falsa del repo`, (t) => {
    const r = correr(repoDeJuguete(t), modo.env);
    arranco(r, modo);
    esLaCredencialFalsa(r);
  });

  test(`${modo.nombre}: un GOOGLE_APPLICATION_CREDENTIALS heredado (la clave de prod) se pisa`, (t) => {
    // Lo que AGENTS.md § Entornos describe: `GOOGLE_APPLICATION_CREDENTIALS=$TREINO_SA_KEY`.
    const repo = repoDeJuguete(t);
    const heredada = path.join(repo.raiz, 'sa-key-de-produccion.json');
    fs.writeFileSync(heredada, JSON.stringify({ type: 'service_account', project_id: 'treino-dev' }));
    const r = correr(repo, { ...modo.env, GOOGLE_APPLICATION_CREDENTIALS: heredada });
    arranco(r, modo);
    assert.notStrictEqual(r.gac, heredada, 'el emulador arrancó con la credencial heredada del shell');
    esLaCredencialFalsa(r);
  });

  const sin = (campo) => {
    const c = { ...CAMPOS_FALSOS };
    delete c[campo];
    return JSON.stringify(c);
  };
  const vacio = (campo) => JSON.stringify({ ...CAMPOS_FALSOS, [campo]: '' });
  for (const [caso, credencial] of [
    ['falta', 'falta'],
    ['no es JSON', 'esto no es json'],
    ['es de otro tipo', JSON.stringify({ type: 'service_account' })],
    // Con `type` pero sin cualquiera de estos tres, el CLI ya no la cuenta como
    // ADC y vuelve a inyectar el login (medido con `hasDefaultCredentials()`;
    // hallazgo del review del PR).
    ['no tiene refresh_token', sin('refresh_token')],
    ['no tiene client_id', sin('client_id')],
    ['no tiene client_secret', sin('client_secret')],
    // Vacío también: con "" el CLI tampoco la cuenta (medido).
    ['tiene client_id vacío', vacio('client_id')],
    ['tiene refresh_token vacío', vacio('refresh_token')],
  ]) {
    test(`${modo.nombre}: si la credencial falsa ${caso}, el emulador NO arranca`, (t) => {
      const r = correr(repoDeJuguete(t, { credencial }), modo.env);
      assert.notStrictEqual(r.code, 0, `salió con 0 sin credencial falsa usable.\nSALIDA:\n${r.salida}`);
      assert.strictEqual(r.argv, null, `llamó a firebase igual: ${r.argv}`);
      assert.match(r.salida, /falta o está rota .*el emulador NO se levanta/);
    });
  }

  // El emulador mete estos archivos en el runtime DESPUÉS de process.env: una
  // GOOGLE_APPLICATION_CREDENTIALS ahí le gana a la falsa (medido).
  for (const [archivo, contenido] of [
    ['.env.local', 'GOOGLE_APPLICATION_CREDENTIALS=/ruta/a/sa-key.json\n'],
    ['.env', 'OTRA=1\nexport GOOGLE_APPLICATION_CREDENTIALS=/ruta/a/sa-key.json\n'],
    ['.env.treino-dev', 'MAIL_FROM=x\n  GOOGLE_APPLICATION_CREDENTIALS = /ruta/a/sa-key.json\n'],
    ['.secret.local', 'GOOGLE_APPLICATION_CREDENTIALS=/ruta/a/sa-key.json\n'],
    // `export` pegado: el parser de firebase-tools lo acepta (review del PR).
    ['.env.prod', 'exportGOOGLE_APPLICATION_CREDENTIALS=/ruta/a/sa-key.json\n'],
  ]) {
    test(`${modo.nombre}: una GOOGLE_APPLICATION_CREDENTIALS en functions/${archivo} frena el arranque`, (t) => {
      const r = correr(repoDeJuguete(t, { envFunctions: { [archivo]: contenido } }), modo.env);
      assert.notStrictEqual(r.code, 0, `salió con 0 con la variable en ${archivo}.\nSALIDA:\n${r.salida}`);
      assert.strictEqual(r.argv, null, `llamó a firebase igual: ${r.argv}`);
      assert.match(r.salida, new RegExp(`definen GOOGLE_APPLICATION_CREDENTIALS[\\s\\S]*functions/\\${archivo}\\n`));
    });
  }

  test(`${modo.nombre}: un .env de functions que no se puede leer frena el arranque`, (t) => {
    // Un symlink roto: no hay forma de saber qué define. Sirve también como
    // root (CI), donde un chmod 000 no impediría leer.
    const r = correr(
      repoDeJuguete(t, { envFunctions: { '.env.local': { symlink: '/no/existe/.env.local' } } }),
      modo.env,
    );
    assert.notStrictEqual(r.code, 0, `salió con 0 con un .env.local ilegible.\nSALIDA:\n${r.salida}`);
    assert.strictEqual(r.argv, null, `llamó a firebase igual: ${r.argv}`);
    assert.match(r.salida, /functions\/\.env\.local \(no se pudo leer: ENOENT\)/);
  });

  test(`${modo.nombre}: sin el directorio de functions, el emulador NO arranca`, (t) => {
    // Sin directorio no hay nada que revisar, y un OK ahí sería un OK sin mirar.
    const r = correr(repoDeJuguete(t, { sinFunctions: true }), modo.env);
    assert.notStrictEqual(r.code, 0, `salió con 0 sin functions/.\nSALIDA:\n${r.salida}`);
    assert.strictEqual(r.argv, null, `llamó a firebase igual: ${r.argv}`);
    assert.match(r.salida, /functions \(no existe: no se pudo revisar\)/);
  });

  test(`${modo.nombre}: archivos de env de functions SIN esa variable no frenan nada`, (t) => {
    // El control del anterior: que no frene por tener archivos de env, ni por
    // un nombre parecido o comentado.
    const r = correr(
      repoDeJuguete(t, {
        envFunctions: {
          '.env.local': 'MAIL_FROM=x\n# GOOGLE_APPLICATION_CREDENTIALS=/ruta\n',
          '.env.treino-dev': 'MY_GOOGLE_APPLICATION_CREDENTIALS=no-es-la-misma\n',
          '.secret.local': 'RESEND_API_KEY=re_de_prueba\n',
          // Un directorio que matchea el nombre: antes hacía reventar el chequeo.
          '.env.d': null,
        },
      }),
      modo.env,
    );
    arranco(r, modo);
    esLaCredencialFalsa(r);
  });

  test(`${modo.nombre}: el bucket de respaldo es el de la app`, (t) => {
    // Sin login ni caché, el CLI cae a `<proyecto>.appspot.com` salvo que haya
    // STORAGE_BUCKET_URL (medido). El de la app sale de firebase_options.dart.
    const opciones = fs.readFileSync(path.join(SCRIPTS_DIR, '..', 'lib', 'firebase_options.dart'), 'utf8');
    const buckets = [...new Set([...opciones.matchAll(/storageBucket:\s*'([^']+)'/g)].map((m) => m[1]))];
    assert.strictEqual(buckets.length, 1, `firebase_options.dart no tiene UN bucket: ${buckets}`);
    const r = correr(repoDeJuguete(t), modo.env);
    arranco(r, modo);
    assert.strictEqual(r.bucket, buckets[0], 'STORAGE_BUCKET_URL no es el bucket de la app');
  });
}

// ── Fuera de los dos modos ──────────────────────────────────────────────────

test('la credencial versionada tiene los valores falsos, no otros', () => {
  const cred = JSON.parse(fs.readFileSync(path.join(SCRIPTS_DIR, CREDENCIAL), 'utf8'));
  for (const [campo, valor] of Object.entries(CAMPOS_FALSOS)) {
    assert.strictEqual(cred[campo], valor, `${CREDENCIAL}: ${campo} cambió; ¿es una credencial real?`);
  }
});

test('el chequeo de env mira functions/ aunque emulator.sh se corra desde otro directorio', (t) => {
  // emulator.sh pasa el directorio relativo a SÍ MISMO. Con `cerrar_produccion
  // functions` (relativo al cwd), corrido desde scripts/ miraría scripts/functions,
  // que no existe. Va con SKIP_FUNCTIONS: el modo completo exige correr desde la
  // raíz por otro motivo (functions/node_modules).
  const sucio = correr(
    repoDeJuguete(t, { envFunctions: { '.env.local': 'GOOGLE_APPLICATION_CREDENTIALS=/ruta/a/sa-key.json\n' } }),
    { SKIP_FUNCTIONS: '1' },
    { cwd: 'scripts' },
  );
  assert.notStrictEqual(sucio.code, 0, `desde scripts/ no vio functions/.env.local.\nSALIDA:\n${sucio.salida}`);
  assert.strictEqual(sucio.argv, null, `llamó a firebase igual: ${sucio.argv}`);
  assert.match(sucio.salida, /functions\/\.env\.local\n/);

  // Control: desde ahí mismo, sin la variable, arranca y con la credencial falsa.
  const limpio = correr(repoDeJuguete(t), { SKIP_FUNCTIONS: '1' }, { cwd: 'scripts' });
  assert.strictEqual(limpio.code, 0, `desde scripts/ no arrancó.\nSALIDA:\n${limpio.salida}`);
  esLaCredencialFalsa(limpio);
});

test('firebase.json sigue cargando las Functions de functions/, que es lo que revisa emulator.sh', () => {
  // El emulador toma el directorio de `functions[].source` (y `configDir`, si
  // hay). emulator.sh revisa `../functions` fijo: si esto se mueve, el chequeo
  // miraría un directorio que el emulador no usa.
  const { functions } = JSON.parse(fs.readFileSync(path.join(SCRIPTS_DIR, '..', 'firebase.json'), 'utf8'));
  const bases = Array.isArray(functions) ? functions : [functions];
  assert.deepStrictEqual(
    bases.map((b) => ({ source: b.source, configDir: b.configDir })),
    [{ source: 'functions', configDir: undefined }],
  );
});
