/**
 * test/firebase_admin_superficie.test.js
 *
 * EL TRINQUETE DE LA DEPENDENCIA: que el `firebase-admin` REALMENTE INSTALADO
 * siga teniendo la API contra la que están escritos los scripts.
 *
 *   cd scripts && npm test
 *
 * POR QUÉ EXISTE. El 2026-09-07 un `npm install` limpio dejaba los 44 scripts
 * de `scripts/` completamente muertos:
 *
 *   $ FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_emulator_full.js
 *   scripts/lib/admin.js:86
 *     if (admin.apps.length) return { admin, contexto: null };
 *                    ^
 *   TypeError: Cannot read properties of undefined (reading 'length')
 *
 * `firebase-admin` v14 BORRÓ la API namespaced. El root export pasó a ser once
 * símbolos —`initializeApp`, `getApp`, `getApps`, `deleteApp`,
 * `applicationDefault`, `cert`, `refreshToken`, `FirebaseError`,
 * `FirebaseAppError`, `AppErrorCode`, `SDK_VERSION`— y `admin.apps`,
 * `admin.app`, `admin.credential`, `admin.firestore`, `admin.auth` y
 * `admin.storage` quedaron TODOS `undefined`. Cuando esto se escribió, los
 * scripts usaban esa API en 88 lugares repartidos en 46 archivos; la migración
 * a los subpaths modulares los viene bajando y hoy quedan pocos. No hay número
 * fijo acá a propósito: el escaneo lo cuenta solo en cada corrida.
 *
 * Y NADIE SE ENTERÓ, dos veces (`cac2d6fa` y `de77562a`/#901). Por dos motivos
 * que se tapaban entre sí, y los dos son parte de lo que arregla este archivo:
 *
 *   1. El job `scripts-test` de `ci.yml` NO INSTALABA NADA. Iba directo a
 *      `npm --prefix scripts test`, sin `npm ci`. Medido el 2026-09-07: con
 *      `scripts/node_modules` borrado, la suite daba **469/469 en verde**. O
 *      sea que CI validaba 469 cosas sobre un paquete que jamás descargaba, y
 *      dependabot podía subir `firebase-admin` a cualquier versión sin que
 *      nada se pusiera rojo.
 *   2. Los tests que sí cargan un script de verdad lo hacen con
 *      `fixtures/stub_firebase_admin.js`, que intercepta `Module._load` y
 *      devuelve un objeto de mentira. Es correcto para lo que ese fixture
 *      prueba —que un guard corte ANTES de tocar Firestore— pero significa que
 *      la suite entera, por construcción, no puede ver la superficie real del
 *      SDK. El stub tiene la API que el stub decide tener.
 *
 * Este test es el único de `scripts/test/` que hace `require('firebase-admin')`
 * A SECAS, sin stub y sin inyección. Es la contraparte de los otros dos
 * trinquetes estructurales del directorio (`frontera.test.js`,
 * `storage_scripts_destination.test.js`): no prueba comportamiento, prueba que
 * una premisa siga valiendo.
 *
 * CÓMO. La lista de APIs NO está escrita a mano: se extrae del código de los
 * scripts en cada corrida. Una lista a mano se desactualiza y termina
 * prometiendo una cobertura que no tiene —el patrón del #826—; un escaneo
 * cubre también los scripts que todavía no existen. Si mañana alguien escribe
 * `admin.messaging()`, este test lo empieza a chequear solo.
 *
 * SI ESTE TEST SE PONE ROJO no toques la lista: o volvés la versión de
 * `firebase-admin` a la que tiene esa API, o migrás los archivos que faltan a
 * los subpaths modulares (`firebase-admin/firestore`, `/auth`, `/storage`). El
 * rojo es la pregunta "¿migraste?", no un detalle de configuración.
 *
 * EL PRIMER TEST CAMBIÓ DE FORMA, y vale saber por qué. Exigía que el escaneo
 * encontrara al menos 8 APIs distintas — un guard contra "esto pasa en vacío"
 * que era correcto ANTES de empezar a migrar. Dejó de serlo: `USOS` se vacía a
 * propósito a medida que la migración avanza, así que ese umbral convertía el
 * ÉXITO en un rojo. Ahora se custodia lo que de verdad importa —que el
 * EXTRACTOR sepa encontrar la API— con un autotest contra un fuente sintético,
 * que vale igual con 88 usos que con ninguno.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const RAIZ_SCRIPTS = path.resolve(__dirname, '..');

/**
 * Igual que en `frontera.test.js`:
 *   test/        — nosotros, y acá vive el `admin` de mentira.
 *   rules_test/  — suite del emulador de rules, con su propio package.json.
 *   node_modules — obvio.
 *
 * `lib/` NO está excluido, al revés que allá: `lib/admin.js` es justamente el
 * que usa `admin.apps` y `admin.credential.cert`, o sea las dos APIs que v14
 * borró y por donde todo empezó a fallar.
 */
const DIRS_EXCLUIDOS = new Set(['test', 'rules_test', 'node_modules']);

/**
 * Saca comentarios de bloque y de línea. Mismo criterio que `frontera.test.js`:
 * el `//` no cuenta si viene pegado a `:`, para no comerse media línea por una
 * URL adentro de un string.
 *
 * Hace falta acá porque este mismo archivo, y varios headers de `scripts/`,
 * nombran en prosa APIs que v14 borró. Escanear los comentarios convertiría
 * esa documentación en un test rojo permanente.
 */
function sinComentarios(fuente) {
  return fuente
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

/**
 * `admin.<algo>` y `admin.<algo>.<algo>`, dos niveles, que es hasta donde
 * llegan los scripts (`admin.firestore.Timestamp`).
 *
 * El lookbehind saca los falsos positivos que importan: `require('./lib/admin.js')`
 * —el `/` de la ruta— y cualquier `firebase-admin.` —el guión—. Sin él, el
 * escaneo pediría que el SDK exportara una propiedad `js`.
 */
const USO_DE_ADMIN = /(?<![\w$./'"\\-])admin\.([A-Za-z_$][\w$]*)(?:\.([A-Za-z_$][\w$]*))?/g;

/** Todos los `.js`/`.mjs` de `scripts/`, recursivo, menos los excluidos. */
function fuentesDeScripts(dir = RAIZ_SCRIPTS, prefijo = '') {
  const encontrados = [];
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entrada.isDirectory()) {
      if (DIRS_EXCLUIDOS.has(entrada.name) || entrada.name.startsWith('.')) continue;
      encontrados.push(...fuentesDeScripts(path.join(dir, entrada.name), `${prefijo}${entrada.name}/`));
    } else if (/\.(js|mjs)$/.test(entrada.name)) {
      encontrados.push(`${prefijo}${entrada.name}`);
    }
  }
  return encontrados;
}

/** Las rutas `admin.<algo>[.<algo>]` que aparecen en un fuente. Pura, para autotestearla. */
function apisEn(fuente) {
  const rutas = [];
  for (const [, primero, segundo] of sinComentarios(fuente).matchAll(USO_DE_ADMIN)) {
    rutas.push(segundo ? `${primero}.${segundo}` : primero);
  }
  return rutas;
}

/** `Map<'firestore.Timestamp', Set<archivo>>` — qué API usa cada script. */
function apisUsadas() {
  const usos = new Map();
  for (const nombre of fuentesDeScripts()) {
    for (const ruta of apisEn(fs.readFileSync(path.join(RAIZ_SCRIPTS, nombre), 'utf8'))) {
      if (!usos.has(ruta)) usos.set(ruta, new Set());
      usos.get(ruta).add(nombre);
    }
  }
  return usos;
}

/** Resuelve `'firestore.Timestamp'` sobre el módulo, sin explotar en el camino. */
function resolver(modulo, ruta) {
  return ruta.split('.').reduce((obj, clave) => (obj == null ? undefined : obj[clave]), modulo);
}

const USOS = apisUsadas();

// ── El trinquete ───────────────────────────────────────────────────────────

test('el escaneo encuentra scripts y el extractor funciona (si no, esto pasaría en vacío)', () => {
  // El modo de falla que hay que descartar primero: un test que no mide nada y
  // sale verde. Es la lección del stub ESM del #846.
  assert.ok(
    fuentesDeScripts().length >= 40,
    `sólo ${fuentesDeScripts().length} archivos escaneados — se rompió el listado`,
  );

  // ANTES esto exigía `USOS.size >= 8` y que apareciera `admin.firestore`, y
  // era correcto mientras la migración no había empezado. Dejó de serlo: a
  // medida que los scripts pasan a los subpaths modulares, `USOS` se vacía A
  // PROPÓSITO, y el día que quede en cero ese umbral convierte el ÉXITO de la
  // migración en un rojo.
  //
  // Lo que hay que custodiar no es cuántas APIs quedan —eso baja solo, y que
  // baje es la meta— sino que el EXTRACTOR siga sabiendo encontrarlas. Se
  // prueba contra un fuente sintético, así el guard vale igual con 88 usos que
  // con ninguno.
  const sonda = [
    "const db = admin.firestore();",
    "const t = admin.firestore.Timestamp.now();",
    "// admin.auth() en un comentario NO cuenta",
    "const x = require('./lib/admin.js');",
  ].join('\n');
  assert.deepStrictEqual(
    apisEn(sonda),
    ['firestore', 'firestore.Timestamp'],
    'el extractor dejó de matchear la API namespaced, o empezó a contar comentarios y rutas',
  );
});

test('el firebase-admin instalado tiene TODA la API que usan los scripts', () => {
  // El único `require('firebase-admin')` sin stub de toda la suite. Si esto
  // tira MODULE_NOT_FOUND, el job de CI dejó de correr `npm ci` y volvimos a
  // testear contra un paquete que no existe.
  const admin = require('firebase-admin');

  const faltantes = [];
  for (const [ruta, archivos] of [...USOS].sort()) {
    if (typeof resolver(admin, ruta) === 'undefined') {
      faltantes.push(`admin.${ruta}  ← ${[...archivos].sort().join(', ')}`);
    }
  }

  assert.deepStrictEqual(
    faltantes,
    [],
    'El `firebase-admin` instalado (' +
      admin.SDK_VERSION +
      ') no tiene APIs que los scripts usan:\n  ' +
      faltantes.join('\n  ') +
      '\n\nv14 borró la API namespaced entera. NO agregues excepciones acá: o volvés\n' +
      'la versión a una que tenga esa API (ver el candado en scripts/package.json),\n' +
      'o migrás esos archivos a los subpaths modulares de `firebase-admin/*`.',
  );
});

test('`admin.apps` es un array — la idempotencia de lib/admin.js depende de eso', () => {
  // Se testea aparte porque es la que rompió, y porque el error que produce
  // —`Cannot read properties of undefined (reading 'length')`— no dice
  // "cambió la API": parece un bug del script. Que el rojo lo diga.
  const admin = require('firebase-admin');
  assert.ok(
    Array.isArray(admin.apps),
    '`admin.apps` no es un array. `lib/admin.js` lo usa para no inicializar dos ' +
      'veces cuando `seed_emulator_full.js` requiere `seed_workout_catalog.js`. ' +
      'En v14 el reemplazo es `admin.getApps()`.',
  );
});
