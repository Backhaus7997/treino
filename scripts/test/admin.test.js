/**
 * test/admin.test.js
 *
 * #834 — los tests del ADAPTADOR: `lib/admin.js`, la única puerta por la que
 * los 44 scripts inicializan el Admin SDK.
 *
 *   cd scripts && npm test
 *
 * Lo que se prueba acá no es "resuelve bien la credencial" —eso lo cubre
 * `credenciales.test.js`— sino el ORDEN y los efectos, que es donde este módulo
 * puede fallar en silencio:
 *
 *   - contra el emulador NO se toca el filesystem (el stub explota si alguien
 *     mira), porque romper el desarrollo local rompe a todos;
 *   - la credencial se resuelve ANTES de `initializeApp`, no después;
 *   - `GOOGLE_APPLICATION_CREDENTIALS` queda apuntada a la ruta ya validada,
 *     que es lo que impide que el ADC se autentique por un camino paralelo.
 *
 * `firebase-admin` entra inyectado: estos tests no lo cargan ni lo necesitan.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { inicializarAdmin, proyectoDe } = require('../lib/admin');
const { VAR_RUTA, VAR_ADC, ErrorDeCredencial } = require('../lib/credenciales');

const HOME = '/home/tester';
const FUERA = '/home/tester/.config/treino/sa-key.json';

const credencialDe = (clientEmail, projectId) => ({
  type: 'service_account',
  project_id: projectId,
  client_email: clientEmail,
  private_key: '-----BEGIN PRIVATE KEY-----FALSA-----END PRIVATE KEY-----',
});

/**
 * Las cuatro funciones de `firebase-admin/app` que `lib/admin.js` usa, de
 * mentira, anotando con qué las llamaron.
 *
 * CAMBIÓ DE FORMA junto con `lib/admin.js`, en el mismo commit, y eso no es
 * casualidad: el drift entre este doble y el SDK real es exactamente lo que dejó
 * pasar el bug original —dependabot subió `firebase-admin` a v14 dos veces
 * (`cac2d6fa` y `de77562a`/#901) y la suite siguió verde, porque el doble tenía
 * la API que el doble decidía tener—. Antes fingía el módulo namespaced
 * (`apps`, `credential.cert`); ahora finge los subpaths modulares.
 *
 * El nombre del campo `registro` y su forma NO cambian: es lo que asertan los
 * ~20 tests de este archivo, y esas aserciones son sobre la CONDUCTA de
 * `inicializarAdmin` —qué credencial certificó, con qué opciones inicializó—,
 * que es justo lo que este PR no toca.
 */
function sdkFalso() {
  const registro = { apps: [], opciones: null, certificados: [] };
  return {
    registro,
    getApps() {
      return registro.apps;
    },
    getApp() {
      return registro.apps[0];
    },
    cert(cred) {
      registro.certificados.push(cred);
      return { __cert: cred };
    },
    initializeApp(opciones) {
      registro.opciones = opciones;
      const app = {};
      registro.apps.push(app);
      return app;
    },
  };
}

/** Consola de mentira: junta lo que se le escribió. */
const consolaFalsa = () => {
  const lineas = [];
  return { lineas, error: (t) => lineas.push(String(t)) };
};

const explota = (que) => () => assert.fail(`no se debía tocar ${que}`);

// ── Emulador: sin credencial, sin filesystem ───────────────────────────────

test('contra el emulador no se mira el filesystem ni se pide credencial', () => {
  const sdk = sdkFalso();

  const { contexto } = inicializarAdmin({
    sdk,
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' },
    consola: consolaFalsa(),
    // Si el camino del emulador tocara cualquiera de estos, el test explota.
    existeEntrada: explota('existsSync'),
    leerArchivo: explota('readFileSync'),
    modoDeArchivo: explota('statSync'),
    home: HOME,
  });

  assert.strictEqual(contexto.modo, 'emulador');
  assert.deepStrictEqual(sdk.registro.opciones, { projectId: 'treino-dev' });
  assert.deepStrictEqual(sdk.registro.certificados, []);
});

test('contra el emulador, una ruta adentro del repo se rechaza IGUAL', () => {
  // `FIRESTORE_EMULATOR_HOST` desvía Firestore a localhost y nada más: Storage
  // y Auth de Admin siguen yendo a la nube. Con la clave leída desde adentro
  // del repo eso es un camino real a producción disfrazado de "corriendo
  // local". Es el único caso que el modo emulador sigue frenando.
  const sdk = sdkFalso();
  const consola = consolaFalsa();
  const dentro = '/algun/repo/scripts/sa-key.json';

  assert.throws(
    () =>
      inicializarAdmin({
        sdk,
        env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080', [VAR_RUTA]: dentro },
        consola,
        salir: () => {},
        existeEntrada: (p) => p === dentro || p === '/algun/repo/.git',
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.strictEqual(sdk.registro.apps.length, 0);
  assert.match(consola.lineas.join('\n'), /árbol de git/);
});

test('contra el emulador, una variable vieja o rota NO frena nada', () => {
  // Lo contrario del test de arriba, y es igual de importante: romper el
  // desarrollo local por una variable que quedó apuntando a un archivo que ya
  // no existe sería cobrarle a todo el mundo un riesgo que no existe.
  const sdk = sdkFalso();

  inicializarAdmin({
    sdk,
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080', [VAR_RUTA]: '/se/borro/hace/meses.json' },
    consola: consolaFalsa(),
    existeEntrada: () => false,
    home: HOME,
  });

  assert.strictEqual(sdk.registro.apps.length, 1);
});

test('el emulador respeta las opciones extra (storageBucket) y el projectId forzado', () => {
  const sdk = sdkFalso();

  inicializarAdmin({
    sdk,
    projectId: 'otro-proyecto',
    extra: { storageBucket: 'un.bucket' },
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' },
    consola: consolaFalsa(),
    home: HOME,
  });

  assert.deepStrictEqual(sdk.registro.opciones, {
    projectId: 'otro-proyecto',
    storageBucket: 'un.bucket',
  });
});

// ── Credencial: se resuelve ANTES de inicializar ───────────────────────────

test('con credencial válida inicializa con cert() y el project id de la identidad', () => {
  const sdk = sdkFalso();
  const cred = credencialDe('firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com', 'treino-dev');
  const env = { [VAR_RUTA]: FUERA };

  const { contexto } = inicializarAdmin({
    sdk,
    env,
    consola: consolaFalsa(),
    existeEntrada: (p) => p === FUERA,
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o600,
    home: HOME,
  });

  assert.strictEqual(contexto.modo, 'credencial');
  assert.strictEqual(contexto.produccion, true);
  assert.deepStrictEqual(sdk.registro.certificados, [cred]);
  assert.strictEqual(sdk.registro.opciones.projectId, 'treino-dev');
  assert.strictEqual(proyectoDe(contexto), 'treino-dev');
});

test('la ruta validada queda en GOOGLE_APPLICATION_CREDENTIALS — no queda un ADC paralelo', () => {
  // Éste es el punto que hace que cablear sirva para los scripts que usaban
  // ADC: el resolutor corre primero y le IMPONE la ruta al ambiente, en vez de
  // dejar que la librería resuelva por su cuenta.
  const sdk = sdkFalso();
  const cred = credencialDe('sa@ajeno.iam.gserviceaccount.com', 'ajeno');
  const env = { [VAR_RUTA]: FUERA };

  inicializarAdmin({
    sdk,
    env,
    consola: consolaFalsa(),
    existeEntrada: (p) => p === FUERA,
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o600,
    home: HOME,
  });

  assert.strictEqual(env[VAR_ADC], FUERA);
});

test('sin variable: imprime la migración, sale con 1 y NO inicializa nada', () => {
  const sdk = sdkFalso();
  const consola = consolaFalsa();
  const salidas = [];

  assert.throws(
    () =>
      inicializarAdmin({
        sdk,
        env: {},
        consola,
        salir: (c) => salidas.push(c),
        existeEntrada: () => false,
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.deepStrictEqual(salidas, [1]);
  assert.strictEqual(sdk.registro.apps.length, 0, 'no se puede haber inicializado nada');
  assert.match(consola.lineas.join('\n'), /mv scripts\/sa-key\.json/);
});

test('una ruta adentro del repo se rechaza antes de inicializar', () => {
  const sdk = sdkFalso();
  const consola = consolaFalsa();
  const dentro = '/algun/repo/scripts/sa-key.json';

  assert.throws(
    () =>
      inicializarAdmin({
        sdk,
        env: { [VAR_RUTA]: dentro },
        consola,
        salir: () => {},
        existeEntrada: (p) => p === dentro || p === '/algun/repo/.git',
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.strictEqual(sdk.registro.apps.length, 0);
  assert.match(consola.lineas.join('\n'), /árbol de git/);
});

test('los avisos de permisos se muestran, pero no frenan', () => {
  const sdk = sdkFalso();
  const consola = consolaFalsa();
  const cred = credencialDe('sa@ajeno.iam.gserviceaccount.com', 'ajeno');

  inicializarAdmin({
    sdk,
    env: { [VAR_RUTA]: FUERA },
    consola,
    existeEntrada: (p) => p === FUERA,
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o644,
    home: HOME,
  });

  assert.strictEqual(sdk.registro.apps.length, 1, 'un aviso no frena');
  assert.match(consola.lineas.join('\n'), /chmod 600/);
});

// ── Idempotencia ───────────────────────────────────────────────────────────

test('si ya hay una app, no reinicializa ni vuelve a resolver credencial', () => {
  // `seed_workout_catalog.js` se requiere desde `seed_emulator_full.js`, que ya
  // inicializó. Un segundo `initializeApp` explotaría.
  const sdk = sdkFalso();
  sdk.registro.apps.push({});

  const { contexto } = inicializarAdmin({
    sdk,
    env: {},
    consola: consolaFalsa(),
    existeEntrada: explota('existsSync'),
    home: HOME,
  });

  assert.strictEqual(contexto, null);
  assert.strictEqual(sdk.registro.opciones, null, 'no se llamó a initializeApp');
});
