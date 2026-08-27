/**
 * test/target_project.test.js
 *
 * `lib/target_project.js` puro: contra qué proyecto va a escribir el proceso,
 * y si está apuntando al emulador. Sin red, sin `firebase-admin`.
 *
 *   node --test scripts/test/
 *
 * Por qué existen (#826): la revisión encontró que el barrido anterior buscaba
 * comandos de `firebase`/`gcloud` y por eso no veía `npm run seed:all`, que es
 * el camino más corto que hay hacia producción. Este módulo es lo que permite
 * que esos entrypoints —que llaman a `admin.initializeApp()` pelado— sepan a
 * dónde están escribiendo antes de escribir.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  SERVICIOS,
  emuladoresActivos,
  contraEmuladorDe,
  projectIdObjetivo,
} = require('../lib/target_project');

/** Las CINCO variables de emulador que lee el Admin SDK, sobre cuatro servicios. */
const VARIABLES = [
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'STORAGE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'FIREBASE_DATABASE_EMULATOR_HOST',
];

/** Qué servicio desvía cada una. */
const SERVICIO_DE = {
  FIRESTORE_EMULATOR_HOST: 'firestore',
  FIREBASE_AUTH_EMULATOR_HOST: 'auth',
  STORAGE_EMULATOR_HOST: 'storage',
  FIREBASE_STORAGE_EMULATOR_HOST: 'storage',
  FIREBASE_DATABASE_EMULATOR_HOST: 'database',
};

/** Las 32 combinaciones de las cinco variables. */
function combinaciones() {
  const out = [];
  for (let mascara = 0; mascara < 1 << VARIABLES.length; mascara += 1) {
    out.push(VARIABLES.filter((_, i) => (mascara & (1 << i)) !== 0));
  }
  return out;
}

function envCon(vars) {
  return Object.fromEntries(vars.map((v) => [v, '127.0.0.1:9099']));
}

/** Escribe un `sa-key.json` de mentira en un tmpdir. NUNCA en `scripts/`. */
function credencialFalsa(contenido) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'treino-826-'));
  const ruta = path.join(dir, 'sa-key.json');
  fs.writeFileSync(ruta, typeof contenido === 'string' ? contenido : JSON.stringify(contenido));
  return ruta;
}

// ── emuladoresActivos / contraEmuladorDe ──────────────────────────────────
//
// #846 — acá había `usandoEmulador()`, un OR entre `FIRESTORE_EMULATOR_HOST` y
// `FIREBASE_AUTH_EMULATOR_HOST` que devolvía UN booleano para todo el proceso.
// En #826 eso alcanzaba: sus dos llamadores lo pasaban a
// `bannerDeProduccion({contraEmulador})`, o sea apagaba un CARTEL y el peor
// caso era no gritar. `scripts/migrations/strip_appointment_reason.mjs` fue el
// primero en usarlo de COMPUERTA DE ESCRITURA, y ahí el OR miente: un
// `FIREBASE_AUTH_EMULATOR_HOST` suelto —el que queda exportado de una sesión de
// `emulator.sh`— daba "emulador sí" mientras los writes de Firestore iban a
// `treino-dev`, que es producción.
//
// La API pasó a ser por SERVICIO porque la pregunta antes de un write es una
// sola: ¿está desviado el servicio que voy a escribir?

test('emuladoresActivos: sin variables no hay ningún servicio desviado', () => {
  assert.deepStrictEqual(emuladoresActivos({}), {
    firestore: false,
    auth: false,
    storage: false,
    database: false,
  });
});

test('emuladoresActivos: cada variable desvía SÓLO su servicio', () => {
  for (const variable of VARIABLES) {
    const estado = emuladoresActivos(envCon([variable]));
    const esperado = SERVICIO_DE[variable];
    for (const servicio of SERVICIOS) {
      assert.strictEqual(
        estado[servicio],
        servicio === esperado,
        `${variable} tocó "${servicio}" y sólo debía tocar "${esperado}"`,
      );
    }
  }
});

test('emuladoresActivos: los dos nombres de Storage cuentan igual', () => {
  // `firebase-admin` acepta las dos y normaliza `FIREBASE_STORAGE_EMULATOR_HOST`
  // a `STORAGE_EMULATOR_HOST`. Mirar una sola daría un falso negativo.
  assert.strictEqual(emuladoresActivos({ STORAGE_EMULATOR_HOST: 'x' }).storage, true);
  assert.strictEqual(emuladoresActivos({ FIREBASE_STORAGE_EMULATOR_HOST: 'x' }).storage, true);
});

test('emuladoresActivos: vacío o whitespace NO cuenta como emulador', () => {
  // Exportar la variable en blanco no desvía nada, y tratarla como emulador
  // apagaría la salvaguarda exactamente cuando el proceso sí va a producción.
  for (const valor of ['', '   ']) {
    assert.strictEqual(emuladoresActivos({ FIRESTORE_EMULATOR_HOST: valor }).firestore, false);
  }
});

test('matriz de las 5 variables: contraEmuladorDe([firestore]) sólo mira la suya', () => {
  // Ésta es la fila del bug, y las otras 31 son las que prueban que no hay
  // ninguna combinación que la reproduzca por otro lado.
  for (const vars of combinaciones()) {
    const esperado = vars.includes('FIRESTORE_EMULATOR_HOST');
    assert.strictEqual(
      contraEmuladorDe(['firestore'], envCon(vars)),
      esperado,
      `combinación ${vars.join('+') || '(ninguna)'}`,
    );
  }
});

test('contraEmuladorDe: exige TODOS los servicios, no cualquiera', () => {
  // Basta que uno no esté desviado para que el proceso le hable a producción.
  // Es el mismo criterio del `contraEmulador` de `planDeStorage()`.
  const soloFirestore = envCon(['FIRESTORE_EMULATOR_HOST']);
  assert.strictEqual(contraEmuladorDe(['firestore'], soloFirestore), true);
  assert.strictEqual(contraEmuladorDe(['firestore', 'auth'], soloFirestore), false);

  const ambos = envCon(['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']);
  assert.strictEqual(contraEmuladorDe(['firestore', 'auth'], ambos), true);
});

test('contraEmuladorDe: sin declarar servicios devuelve false, no true', () => {
  // "No declaré qué toco" no es "no toco nada". Un default permisivo acá es
  // exactamente el bug que este módulo dejó de tener.
  const todo = envCon(VARIABLES);
  assert.strictEqual(contraEmuladorDe([], todo), false);
  assert.strictEqual(contraEmuladorDe(undefined, todo), false);
});

test('contraEmuladorDe: un servicio desconocido TIRA en vez de contestar', () => {
  // Un typo que devolviera false silencioso convertiría una corrida contra el
  // emulador en un cartel de producción; uno que devolviera true haría lo
  // contrario, que es peor. Que se rompa.
  assert.throws(
    () => contraEmuladorDe(['firestor'], envCon(['FIRESTORE_EMULATOR_HOST'])),
    /servicio desconocido/,
  );
});

// ── projectIdObjetivo ─────────────────────────────────────────────────────

test('projectIdObjetivo: GOOGLE_CLOUD_PROJECT gana', () => {
  assert.strictEqual(projectIdObjetivo({ GOOGLE_CLOUD_PROJECT: 'treino-dev' }), 'treino-dev');
});

test('projectIdObjetivo: GCLOUD_PROJECT como alternativa', () => {
  assert.strictEqual(projectIdObjetivo({ GCLOUD_PROJECT: 'treino-dev' }), 'treino-dev');
});

test('projectIdObjetivo: sale del project_id de GOOGLE_APPLICATION_CREDENTIALS', () => {
  const ruta = credencialFalsa({ project_id: 'treino-dev', type: 'service_account' });
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: ruta }), 'treino-dev');
});

test('projectIdObjetivo: la variable explícita gana sobre la credencial', () => {
  const ruta = credencialFalsa({ project_id: 'otro-proyecto' });
  const env = { GOOGLE_CLOUD_PROJECT: 'treino-dev', GOOGLE_APPLICATION_CREDENTIALS: ruta };
  assert.strictEqual(projectIdObjetivo(env), 'treino-dev');
});

test('projectIdObjetivo: sin nada devuelve null, no un valor inventado', () => {
  // Callar es correcto: significa que el proyecto lo resuelve el SDK por un
  // camino que este módulo no ve. Afirmar "no es producción" ahí sería peor
  // que no decir nada.
  assert.strictEqual(projectIdObjetivo({}), null);
});

test('projectIdObjetivo: credencial inexistente o ilegible devuelve null', () => {
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: '/no/existe.json' }), null);
  const roto = credencialFalsa('{ esto no es json');
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: roto }), null);
});

test('projectIdObjetivo: credencial sin project_id devuelve null', () => {
  const ruta = credencialFalsa({ type: 'service_account' });
  assert.strictEqual(projectIdObjetivo({ GOOGLE_APPLICATION_CREDENTIALS: ruta }), null);
});
