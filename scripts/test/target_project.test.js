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
  TODAS_LAS_VARIABLES,
  EFECTO_EN_BLANCO,
  renglonesEnBlanco,
  estadoDeVariable,
  variablesEnBlanco,
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
  // Ninguna de las dos desvía el servicio al emulador, y tratarlas como tal
  // apagaría la salvaguarda. Pero "no es emulador" NO quiere decir "es la
  // nube": `' '` el SDK la lee y se rompe. Eso lo resuelve `variablesEnBlanco`,
  // más abajo, y por eso este test ya no dice que en blanco "no desvía nada".
  for (const valor of ['', '   ']) {
    assert.strictEqual(emuladoresActivos({ FIRESTORE_EMULATOR_HOST: valor }).firestore, false);
  }
});

// ── estadoDeVariable / variablesEnBlanco ──────────────────────────────────
//
// Nota 3 del #1442: con `FIRESTORE_EMULATOR_HOST=' '` y
// `FIREBASE_STORAGE_EMULATOR_HOST=' '`, `storage_target.js` decía EMULADOR (su
// `Boolean(' ')` es `true`) y `credenciales.js` decía nube (su `trim()`), así
// que la misma corrida salía etiquetada EMULADOR, sin cartel, con `lib/admin.js`
// cargando la credencial. Medido contra el SDK, ninguno de los dos tenía razón.

test('estadoDeVariable: tres estados, y `\' \'` es el tercero', () => {
  assert.strictEqual(estadoDeVariable(undefined), 'ausente');
  // `''` es falsy: Firestore, firebase-admin (Storage), Auth y Database la
  // ignoran. Medido; ver el comentario de `estadoDeVariable`.
  assert.strictEqual(estadoDeVariable(''), 'ausente');
  for (const valor of [' ', '   ', '\t', '\n', ' \t\n ']) {
    assert.strictEqual(estadoDeVariable(valor), 'en blanco', JSON.stringify(valor));
  }
  assert.strictEqual(estadoDeVariable('localhost:8080'), 'puesta');
  assert.strictEqual(estadoDeVariable('http://localhost:9199'), 'puesta');
});

test('variablesEnBlanco: nombra las cinco, en el orden del mapa', () => {
  const todasEnBlanco = Object.fromEntries(VARIABLES.map((v) => [v, ' ']));
  assert.deepStrictEqual(variablesEnBlanco(todasEnBlanco), [...TODAS_LAS_VARIABLES]);
  // Que el mapa del módulo sea el de este archivo: si mañana entra una sexta
  // variable, este test pide sumarla acá (y a `EFECTO_EN_BLANCO`).
  assert.deepStrictEqual([...TODAS_LAS_VARIABLES].sort(), [...VARIABLES].sort());
});

test('variablesEnBlanco: ni la vacía, ni la puesta, ni la ausente', () => {
  assert.deepStrictEqual(variablesEnBlanco({}), []);
  assert.deepStrictEqual(
    variablesEnBlanco({
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      FIREBASE_AUTH_EMULATOR_HOST: '',
      FIREBASE_STORAGE_EMULATOR_HOST: '  ',
    }),
    ['FIREBASE_STORAGE_EMULATOR_HOST'],
  );
});

test('variablesEnBlanco: una sola variable en blanco alcanza, de cualquier servicio', () => {
  for (const v of VARIABLES) {
    assert.deepStrictEqual(variablesEnBlanco({ [v]: ' ' }), [v], v);
  }
});

test('renglonesEnBlanco: no imprime el valor y entra en la caja del abort', () => {
  // El valor puede ser un tab: escribirlo como `' '` mentiría sobre el
  // ambiente. Y un renglón más largo que la caja de ⛔ se lee mal.
  const renglones = renglonesEnBlanco(VARIABLES);
  for (const r of renglones) {
    assert.ok(r.length <= 62, `renglón de ${r.length}: ${r}`);
    assert.doesNotMatch(r, /= ' '/);
  }
  for (const v of VARIABLES) assert.ok(renglones.includes(`${v}  (en blanco)`), v);
});

test('EFECTO_EN_BLANCO: una frase por variable, ni una de más', () => {
  // El abort imprime esta frase por cada variable en blanco. Una que falte sale
  // como "→ undefined", que es peor que no decir nada.
  assert.deepStrictEqual(Object.keys(EFECTO_EN_BLANCO).sort(), [...VARIABLES].sort());
  for (const v of VARIABLES) assert.ok(EFECTO_EN_BLANCO[v].trim(), v);
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

// ── #834 — la variable canónica ────────────────────────────────────────────

// Las dos van por `credencialFalsa()`, que ya estaba en este archivo, y no por
// un `path.join(os.tmpdir(), ...)` armado a mano como traía la primera versión.
// No es estilo: `os.tmpdir()` es world-writable y un nombre predecible —lo era,
// `treino-target-${process.pid}-a.json`— lo puede pre-crear otro usuario de la
// máquina como symlink y hacer que el test escriba donde él quiera. CodeQL lo
// marcó (`js/insecure-temporary-file`, 3 alertas) y tenía razón: el patrón lo
// introdujo este PR. `mkdtempSync` resuelve las dos mitades de una, porque
// crea el directorio con nombre aleatorio y permisos 0700.

test('projectIdObjetivo lee TREINO_SA_KEY, no sólo GOOGLE_APPLICATION_CREDENTIALS', () => {
  // Sin esto, el cartel de #826 desaparecía justo para quien ya había migrado
  // la clave afuera del repo: el que hizo lo correcto se quedaba sin aviso.
  const ruta = credencialFalsa({ project_id: 'treino-dev' });
  assert.strictEqual(projectIdObjetivo({ TREINO_SA_KEY: ruta }), 'treino-dev');
});

test('TREINO_SA_KEY le gana a GOOGLE_APPLICATION_CREDENTIALS, como en la frontera', () => {
  // Dos llamadas, dos `mkdtemp` distintos: las rutas no pueden colisionar.
  const canonica = credencialFalsa({ project_id: 'el-canonico' });
  const adc = credencialFalsa({ project_id: 'el-otro' });
  assert.strictEqual(
    projectIdObjetivo({ TREINO_SA_KEY: canonica, GOOGLE_APPLICATION_CREDENTIALS: adc }),
    'el-canonico',
  );
});
