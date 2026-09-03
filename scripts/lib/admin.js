/**
 * lib/admin.js
 *
 * #834 — LA ÚNICA PUERTA POR LA QUE SE INICIALIZA EL ADMIN SDK.
 *
 * `lib/credenciales.js` decide si una credencial se puede usar. Este módulo es
 * lo que hace que esa decisión OCURRA: mientras los scripts llamaban a
 * `admin.initializeApp()` por su cuenta, el resolutor existía y no lo invocaba
 * nadie — la frontera estaba escrita, no aplicada.
 *
 * Está separado de `credenciales.js` a propósito. Aquél no tiene dependencias y
 * todo lo observable le entra por parámetro, así que se testea entero con stubs.
 * Éste, en cambio, tiene que tocar `firebase-admin` y `process.env` de verdad:
 * es el adaptador, y la parte impura vive acá y sólo acá.
 *
 * LO QUE HACE, EN ORDEN (el orden es la feature):
 *
 *   1. ¿Emulador? Entonces no hace falta credencial: inicializa con `projectId`
 *      y listo. El desarrollo local no necesita ninguna variable, hoy ni
 *      después de este cambio. Lo único que sigue frenando es una variable
 *      apuntando ADENTRO de un árbol de git — `FIRESTORE_EMULATOR_HOST` desvía
 *      Firestore y nada más, así que eso sería un camino real a producción
 *      disfrazado de local. Ver `rechazarSiApuntaAlRepo`.
 *
 *      "Emulador" acá es `FIRESTORE_EMULATOR_HOST`, ni más ni menos: es la
 *      única variable que desvía lo que estos scripts escriben. Un ambiente que
 *      dice emulador por otra vía (Auth, Storage, RTDB) sin ésa no llega hasta
 *      acá — `resolverContexto` aborta antes. Sin ese corte, `contexto.modo`
 *      valdría `'emulador'` para una corrida que escribe en producción, y las
 *      dos cosas que cuelgan de él —saltear la credencial y apagar el cartel—
 *      serían las dos falsas a la vez.
 *   2. Si no, resuelve la credencial ANTES de `initializeApp`. Tiene que ser
 *      antes: `admin.initializeApp()` sin argumentos y
 *      `admin.credential.applicationDefault()` leen
 *      `GOOGLE_APPLICATION_CREDENTIALS` adentro de la librería, sin pasar por
 *      acá. Si dejáramos que inicialice primero, la clave de producción ya
 *      estaría cargada cuando llegáramos a opinar.
 *   3. Alinea el ADC: le escribe a `GOOGLE_APPLICATION_CREDENTIALS` la ruta que
 *      ya pasó la frontera. Sin esto quedaría un segundo camino sin validar
 *      para cualquier otra librería Google del proceso.
 *   4. Inicializa con `cert()` explícito — la identidad efectiva es la que
 *      verificamos, no la que el ambiente tenga ganas de resolver.
 *
 * Si la credencial no pasa, imprime el mensaje de migración y sale con 1. Un
 * script de datos no tiene nada mejor que hacer con ese error que mostrarlo.
 */

'use strict';

const {
  ErrorDeCredencial,
  VAR_ADC,
  resolverContexto,
} = require('./credenciales');

/** Proyecto contra el que corre el emulador local (`scripts/emulator.sh`). */
const PROJECT_ID_EMULADOR = 'treino-dev';

/**
 * Inicializa `firebase-admin` pasando por la frontera y devuelve
 * `{ admin, contexto }`.
 *
 * @param {object}  [opciones]
 * @param {string}  [opciones.projectId]  Fuerza el proyecto (p. ej. `--project=X`).
 *                                        Si no se pasa, sale de la credencial.
 * @param {object}  [opciones.extra]      Opciones crudas para `initializeApp`
 *                                        (`storageBucket`, …).
 * @param {object}  [opciones.env]        Ambiente. Inyectable para tests.
 * @param {object}  [opciones.admin]      El SDK. Inyectable para tests.
 * @param {object}  [opciones.consola]    Dónde escribir avisos. Inyectable.
 * @param {Function}[opciones.salir]      Cómo abortar. Inyectable.
 */
function inicializarAdmin({
  projectId = null,
  extra = {},
  env = process.env,
  admin = require('firebase-admin'),
  consola = console,
  salir = (codigo) => process.exit(codigo),
  ...io
} = {}) {
  // Idempotente: `seed_workout_catalog.js` se requiere desde
  // `seed_emulator_full.js`, que ya inicializó su app apuntada al emulador. Un
  // segundo `initializeApp` explotaría. No se re-resuelve credencial: la app que
  // ya existe sólo pudo nacer pasando por acá.
  if (admin.apps.length) return { admin, contexto: null };

  let contexto;
  try {
    contexto = resolverContexto({ env, projectIdEmulador: PROJECT_ID_EMULADOR, ...io });
  } catch (err) {
    if (!(err instanceof ErrorDeCredencial)) throw err;
    consola.error(err.message);
    salir(1);
    // `salir` inyectado en tests puede no cortar el flujo; no seguimos igual.
    throw err;
  }

  for (const aviso of contexto.avisos) consola.error(aviso);

  if (contexto.modo === 'emulador') {
    admin.initializeApp({ projectId: projectId || contexto.projectId, ...extra });
    return { admin, contexto };
  }

  // Ver (3) en el encabezado: el resto del proceso hereda la ruta validada.
  env[VAR_ADC] = contexto.ruta;

  admin.initializeApp({
    credential: admin.credential.cert(contexto.credencial),
    projectId: projectId || contexto.credencial.project_id || undefined,
    ...extra,
  });

  return { admin, contexto };
}

/**
 * El proyecto contra el que se va a escribir, para los scripts que lo imprimen
 * o que tienen su propio guard `--allow-prod`.
 */
function proyectoDe(contexto) {
  return contexto.modo === 'emulador'
    ? contexto.projectId
    : contexto.proyectoDeLaIdentidad || contexto.credencial.project_id;
}

module.exports = {
  PROJECT_ID_EMULADOR,
  inicializarAdmin,
  proyectoDe,
};
