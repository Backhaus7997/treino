/**
 * test/frontera.test.js
 *
 * #834 — EL TRINQUETE. Ningún script de `scripts/` carga credenciales sin
 * pasar por `lib/`.
 *
 *   cd scripts && npm test
 *
 * POR QUÉ ESTE TEST Y NO UNO POR SCRIPT.
 *
 * Un test por script probaría 43 veces lo mismo y no probaría lo único que
 * importa: que no exista el 44°. La primera versión de #834 escribió el
 * resolutor con 24 tests verdes y CERO llamadores — el módulo estaba bien y la
 * frontera no existía, porque nadie la cruzaba. Lo que impide que eso vuelva a
 * pasar no es cobertura sobre el módulo: es un escaneo que falla cuando aparece
 * un `initializeApp` suelto.
 *
 * Mismo espíritu que los ratchets de `test/app/theme/tokens/`: no verifican
 * comportamiento, verifican que una regla estructural siga valiendo para
 * archivos que todavía no existen.
 *
 * QUÉ MIRA. Sólo código: los comentarios se sacan antes de escanear. Una doc
 * que menciona `GOOGLE_APPLICATION_CREDENTIALS` explicando algo es prosa; una
 * línea de código que la lee es una puerta.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const RAIZ_SCRIPTS = path.resolve(__dirname, '..');

/**
 * Directorios que no son "scripts que corren contra Firebase":
 *   lib/         — es la frontera misma; acá SÍ vive `initializeApp`.
 *   test/        — nosotros.
 *   rules_test/  — suite del emulador de rules, con su propio package.json.
 *   node_modules — obvio.
 */
const DIRS_EXCLUIDOS = new Set(['lib', 'test', 'rules_test', 'node_modules']);

/**
 * Las PUERTAS: las formas de conseguir una credencial salteándose `lib/`.
 *
 * `GOOGLE_APPLICATION_CREDENTIALS` está en la lista aunque no sea una API:
 * leerla desde un script significa que ese script decide por su cuenta de dónde
 * sale la clave, que es exactamente lo que la frontera centraliza.
 */
const PUERTAS = [
  { patron: /\binitializeApp\s*\(/, nombre: 'initializeApp()' },
  { patron: /\bcredential\.cert\s*\(/, nombre: 'admin.credential.cert()' },
  { patron: /\bapplicationDefault\s*\(/, nombre: 'admin.credential.applicationDefault()' },
  { patron: /\bkeyFile\b/, nombre: 'keyFile (GoogleAuth)' },
  { patron: /sa-key\.json/, nombre: 'sa-key.json por ruta' },
  { patron: /GOOGLE_APPLICATION_CREDENTIALS/, nombre: 'GOOGLE_APPLICATION_CREDENTIALS' },
];

/** Señales de que el script habla con Firebase y, por lo tanto, necesita la puerta. */
const TOCA_FIREBASE = [
  /require\(\s*['"]firebase-admin['"]\s*\)/,
  /from\s+['"]firebase-admin['"]/,
  /\bGoogleAuth\b/,
  /\binicializarAdmin\b/,
  /\bcargarCredencial\b/,
];

/** Que el archivo entre por `lib/admin.js` o, si no usa el Admin SDK, por `lib/credenciales.js`. */
const IMPORTA_LA_FRONTERA = /['"]\.\/lib\/(admin|credenciales)(\.js)?['"]/;

/**
 * Saca comentarios de bloque y de línea.
 *
 * El `//` sólo cuenta si NO viene pegado a `:` — si no, `https://…` adentro de
 * un string se comería el resto de la línea y el escaneo se volvería ciego
 * justo donde hay URLs (`deploy_rules.js`).
 */
function sinComentarios(fuente) {
  return fuente
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

/** Los scripts de primer nivel de `scripts/`. */
function scriptsDelRepo() {
  return fs
    .readdirSync(RAIZ_SCRIPTS, { withFileTypes: true })
    .filter((e) => e.isFile() && /\.(js|mjs)$/.test(e.name))
    .map((e) => e.name)
    .sort();
}

const ARCHIVOS = scriptsDelRepo().map((nombre) => ({
  nombre,
  codigo: sinComentarios(fs.readFileSync(path.join(RAIZ_SCRIPTS, nombre), 'utf8')),
}));

// ── El trinquete ───────────────────────────────────────────────────────────

test('el escaneo encuentra scripts (si no, el trinquete estaría pasando en vacío)', () => {
  assert.ok(
    ARCHIVOS.length >= 40,
    `sólo ${ARCHIVOS.length} archivos escaneados — algo se rompió en el listado`,
  );
});

test('ningún script abre una puerta a la credencial por su cuenta', () => {
  const infracciones = [];
  for (const { nombre, codigo } of ARCHIVOS) {
    for (const { patron, nombre: puerta } of PUERTAS) {
      if (patron.test(codigo)) infracciones.push(`${nombre} → ${puerta}`);
    }
  }
  assert.deepStrictEqual(
    infracciones,
    [],
    'Estos scripts resuelven credenciales sin pasar por la frontera (#834):\n  ' +
      infracciones.join('\n  ') +
      '\n\nUsá `inicializarAdmin()` de `./lib/admin` (o `cargarCredencial()` de\n' +
      '`./lib/credenciales` si no usás el Admin SDK). Ver scripts/README.md.',
  );

  // También al revés, para que DIRS_EXCLUIDOS no se convierta en una lista de
  // excepciones que crece: `lib/` tiene que seguir siendo el que las abre.
  const admin = fs.readFileSync(path.join(RAIZ_SCRIPTS, 'lib', 'admin.js'), 'utf8');
  assert.match(sinComentarios(admin), /\binitializeApp\s*\(/);
});

test('todo script que habla con Firebase importa la frontera', () => {
  const sinPuerta = ARCHIVOS.filter(
    ({ codigo }) => TOCA_FIREBASE.some((p) => p.test(codigo)) && !IMPORTA_LA_FRONTERA.test(codigo),
  ).map(({ nombre }) => nombre);

  assert.deepStrictEqual(
    sinPuerta,
    [],
    'Estos scripts usan Firebase sin importar `./lib/admin` ni `./lib/credenciales` (#834):\n  ' +
      sinPuerta.join('\n  '),
  );
});

test('los 44 scripts que inicializan Firebase pasan por la frontera', () => {
  // 43 tocaban credenciales de verdad + `seed_emulator_full.js`, que es
  // emulator-only y entra igual para que no quede NINGÚN `initializeApp` suelto.
  //
  // El número está clavado a propósito: si alguien agrega un script que entra
  // por `lib/`, este test lo cuenta y hay que subirlo — leyendo el diff. Es el
  // recordatorio de que la lista se mira, no se asume.
  const cableados = ARCHIVOS.filter(({ codigo }) => IMPORTA_LA_FRONTERA.test(codigo));
  assert.strictEqual(
    cableados.length,
    44,
    `cableados: ${cableados.length}. Si agregaste o sacaste un script, actualizá ` +
      'este número Y confirmá que el nuevo entra por lib/:\n  ' +
      cableados.map((a) => a.nombre).join('\n  '),
  );
});

test('ninguna doc manda a guardar la clave adentro del repo', () => {
  // El fallo cerrado sólo es defendible si la doc que la persona ya tiene
  // delante dice dónde va la clave AHORA. Un `Save as scripts/sa-key.json` en un
  // comentario manda derecho contra el rechazo, sin explicar por qué.
  const malas = [];
  for (const nombre of scriptsDelRepo()) {
    const fuente = fs.readFileSync(path.join(RAIZ_SCRIPTS, nombre), 'utf8');
    for (const [i, linea] of fuente.split('\n').entries()) {
      if (nombre === 'deploy_rules.js') continue; // explica el agujero histórico
      if (/scripts[/\\]sa-key\.json|scripts[/\\]treino-dev-service-account/.test(linea)) {
        malas.push(`${nombre}:${i + 1}`);
      }
    }
  }
  assert.deepStrictEqual(malas, [], `doc que manda la clave adentro del repo:\n  ${malas.join('\n  ')}`);
});
