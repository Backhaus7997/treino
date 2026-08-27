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

/** Un `firebase-admin` de mentira que anota con qué lo llamaron. */
function adminFalso() {
  const registro = { apps: [], opciones: null, certificados: [] };
  return {
    registro,
    get apps() {
      return registro.apps;
    },
    credential: {
      cert(cred) {
        registro.certificados.push(cred);
        return { __cert: cred };
      },
    },
    initializeApp(opciones) {
      registro.opciones = opciones;
      registro.apps.push({});
      return {};
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
  const admin = adminFalso();

  const { contexto } = inicializarAdmin({
    admin,
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' },
    consola: consolaFalsa(),
    // Si el camino del emulador tocara cualquiera de estos, el test explota.
    existeEntrada: explota('existsSync'),
    leerArchivo: explota('readFileSync'),
    modoDeArchivo: explota('statSync'),
    home: HOME,
  });

  assert.strictEqual(contexto.modo, 'emulador');
  assert.deepStrictEqual(admin.registro.opciones, { projectId: 'treino-dev' });
  assert.deepStrictEqual(admin.registro.certificados, []);
});

test('contra el emulador, una ruta adentro del repo se rechaza IGUAL', () => {
  // `FIRESTORE_EMULATOR_HOST` desvía Firestore a localhost y nada más: Storage
  // y Auth de Admin siguen yendo a la nube. Con la clave leída desde adentro
  // del repo eso es un camino real a producción disfrazado de "corriendo
  // local". Es el único caso que el modo emulador sigue frenando.
  const admin = adminFalso();
  const consola = consolaFalsa();
  const dentro = '/algun/repo/scripts/sa-key.json';

  assert.throws(
    () =>
      inicializarAdmin({
        admin,
        env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080', [VAR_RUTA]: dentro },
        consola,
        salir: () => {},
        existeEntrada: (p) => p === dentro || p === '/algun/repo/.git',
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.strictEqual(admin.registro.apps.length, 0);
  assert.match(consola.lineas.join('\n'), /árbol de git/);
});

test('contra el emulador, una variable vieja o rota NO frena nada', () => {
  // Lo contrario del test de arriba, y es igual de importante: romper el
  // desarrollo local por una variable que quedó apuntando a un archivo que ya
  // no existe sería cobrarle a todo el mundo un riesgo que no existe.
  const admin = adminFalso();

  inicializarAdmin({
    admin,
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080', [VAR_RUTA]: '/se/borro/hace/meses.json' },
    consola: consolaFalsa(),
    existeEntrada: () => false,
    home: HOME,
  });

  assert.strictEqual(admin.registro.apps.length, 1);
});

test('el emulador respeta las opciones extra (storageBucket) y el projectId forzado', () => {
  const admin = adminFalso();

  inicializarAdmin({
    admin,
    projectId: 'otro-proyecto',
    extra: { storageBucket: 'un.bucket' },
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' },
    consola: consolaFalsa(),
    home: HOME,
  });

  assert.deepStrictEqual(admin.registro.opciones, {
    projectId: 'otro-proyecto',
    storageBucket: 'un.bucket',
  });
});

// ── Credencial: se resuelve ANTES de inicializar ───────────────────────────

test('con credencial válida inicializa con cert() y el project id de la identidad', () => {
  const admin = adminFalso();
  const cred = credencialDe('firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com', 'treino-dev');
  const env = { [VAR_RUTA]: FUERA };

  const { contexto } = inicializarAdmin({
    admin,
    env,
    consola: consolaFalsa(),
    existeEntrada: (p) => p === FUERA,
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o600,
    home: HOME,
  });

  assert.strictEqual(contexto.modo, 'credencial');
  assert.strictEqual(contexto.produccion, true);
  assert.deepStrictEqual(admin.registro.certificados, [cred]);
  assert.strictEqual(admin.registro.opciones.projectId, 'treino-dev');
  assert.strictEqual(proyectoDe(contexto), 'treino-dev');
});

test('la ruta validada queda en GOOGLE_APPLICATION_CREDENTIALS — no queda un ADC paralelo', () => {
  // Éste es el punto que hace que cablear sirva para los scripts que usaban
  // ADC: el resolutor corre primero y le IMPONE la ruta al ambiente, en vez de
  // dejar que la librería resuelva por su cuenta.
  const admin = adminFalso();
  const cred = credencialDe('sa@ajeno.iam.gserviceaccount.com', 'ajeno');
  const env = { [VAR_RUTA]: FUERA };

  inicializarAdmin({
    admin,
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
  const admin = adminFalso();
  const consola = consolaFalsa();
  const salidas = [];

  assert.throws(
    () =>
      inicializarAdmin({
        admin,
        env: {},
        consola,
        salir: (c) => salidas.push(c),
        existeEntrada: () => false,
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.deepStrictEqual(salidas, [1]);
  assert.strictEqual(admin.registro.apps.length, 0, 'no se puede haber inicializado nada');
  assert.match(consola.lineas.join('\n'), /mv scripts\/sa-key\.json/);
});

test('una ruta adentro del repo se rechaza antes de inicializar', () => {
  const admin = adminFalso();
  const consola = consolaFalsa();
  const dentro = '/algun/repo/scripts/sa-key.json';

  assert.throws(
    () =>
      inicializarAdmin({
        admin,
        env: { [VAR_RUTA]: dentro },
        consola,
        salir: () => {},
        existeEntrada: (p) => p === dentro || p === '/algun/repo/.git',
        home: HOME,
      }),
    ErrorDeCredencial,
  );

  assert.strictEqual(admin.registro.apps.length, 0);
  assert.match(consola.lineas.join('\n'), /árbol de git/);
});

test('los avisos de permisos se muestran, pero no frenan', () => {
  const admin = adminFalso();
  const consola = consolaFalsa();
  const cred = credencialDe('sa@ajeno.iam.gserviceaccount.com', 'ajeno');

  inicializarAdmin({
    admin,
    env: { [VAR_RUTA]: FUERA },
    consola,
    existeEntrada: (p) => p === FUERA,
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o644,
    home: HOME,
  });

  assert.strictEqual(admin.registro.apps.length, 1, 'un aviso no frena');
  assert.match(consola.lineas.join('\n'), /chmod 600/);
});

// ── Idempotencia ───────────────────────────────────────────────────────────

test('si ya hay una app, no reinicializa ni vuelve a resolver credencial', () => {
  // `seed_workout_catalog.js` se requiere desde `seed_emulator_full.js`, que ya
  // inicializó. Un segundo `initializeApp` explotaría.
  const admin = adminFalso();
  admin.registro.apps.push({});

  const { contexto } = inicializarAdmin({
    admin,
    env: {},
    consola: consolaFalsa(),
    existeEntrada: explota('existsSync'),
    home: HOME,
  });

  assert.strictEqual(contexto, null);
  assert.strictEqual(admin.registro.opciones, null, 'no se llamó a initializeApp');
});
