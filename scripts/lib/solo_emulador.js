'use strict';

/**
 * lib/solo_emulador.js
 *
 * La compuerta de los scripts que SÓLO pueden correr contra el emulador: los
 * siete de `scripts/capturas/`. No piden credencial ni pasan por `lib/admin.js`
 * —inicializan con `projectId: 'treino-dev'`, que contra el emulador es nada más
 * que el namespace local—, así que esta compuerta es lo ÚNICO que separa una
 * corrida de capturas de una escritura en producción. Si deja pasar algo que no
 * es el emulador, el SDK resuelve la credencial por su cuenta
 * (`GOOGLE_APPLICATION_CREDENTIALS` o las ADC de `gcloud`, AGENTS.md → Entornos)
 * y `treino-dev` deja de ser un namespace.
 *
 * ─── Por qué reemplaza al `if (!process.env.FIRESTORE_EMULATOR_HOST)` ───────
 *
 * Ese chequeo es truthy, y `' '` es truthy: con la variable exportada en blanco
 * la compuerta PASA. Medido sobre los siete, sin red (tripwire en sockets y
 * DNS) y sin credenciales en el ambiente:
 *
 *     FIRESTORE_EMULATOR_HOST=' '   → los siete pasan la compuerta y
 *                                     `getFirestore()` tira "is not a valid host"
 *
 * O sea que hoy no escriben en ningún lado sólo porque el SDK se rompe un
 * renglón más abajo. Eso no es una compuerta: es una validación interna de
 * `@google-cloud/firestore`, que ningún contrato obliga a mantener y que
 * cualquier actualización del lockfile se puede llevar.
 *
 * El vocabulario —qué es "en blanco", qué variable desvía qué servicio— NO se
 * define acá: es de `target_project.js`, igual que para `credenciales.js` y
 * `storage_target.js`. Una tercera definición de "emulador" en el repo sería
 * volver a abrir la nota 3 del #1442, la que partió el criterio en dos.
 */

const fs = require('node:fs');
const path = require('node:path');
const {
  SERVICIOS,
  VARIABLES_POR_SERVICIO,
  contraEmuladorDe,
  estadoDeVariable,
  renglonesEnBlanco,
  variablesEnBlanco,
} = require('./target_project');

const FIREBASE_JSON = path.join(__dirname, '..', '..', 'firebase.json');

/**
 * El puerto que `firebase.json` le asigna al emulador de `servicio`, o `null`.
 *
 * Se lee del archivo en vez de escribirlo acá para que la sugerencia del abort
 * no pueda desfasarse del emulador que `scripts/emulator.sh` levanta de verdad.
 * Sólo corre al armar un mensaje de abort; si el archivo no está o no se puede
 * leer, la sugerencia sale sin puerto en vez de inventar uno.
 */
function puertoDelEmulador(servicio) {
  try {
    const config = JSON.parse(fs.readFileSync(FIREBASE_JSON, 'utf8'));
    const puerto = config && config.emulators && config.emulators[servicio] && config.emulators[servicio].port;
    return Number.isInteger(puerto) ? puerto : null;
  } catch {
    return null;
  }
}

function sugerenciasDeExport(servicios) {
  return servicios.map((servicio) => {
    const variable = VARIABLES_POR_SERVICIO[servicio][0];
    const puerto = puertoDelEmulador(servicio);
    return `export ${variable}=${puerto === null ? '<host:puerto>' : `localhost:${puerto}`}`;
  });
}

function mensajeEnBlanco(enBlanco, servicios) {
  return [
    '',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '⛔  ABORTADO: hay variables de emulador exportadas EN BLANCO.',
    '⛔',
    ...renglonesEnBlanco(enBlanco).map((r) => `⛔    ${r}`),
    '⛔',
    '⛔  Ninguna es un host: ninguna lleva su servicio al emulador. Este',
    '⛔  script es SOLO para el emulador, y un ambiente que no dice a dónde',
    '⛔  ir no se adivina.',
    '⛔',
    '⛔  Sacalas del ambiente y exportá el host del emulador:',
    `⛔    unset ${enBlanco.join(' ')}`,
    ...sugerenciasDeExport(servicios).map((s) => `⛔    ${s}`),
    '⛔',
    '⛔  Contexto: scripts/capturas/README.md / AGENTS.md → Entornos',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
}

function mensajeSinEmulador(servicios, env) {
  const faltan = servicios.filter((s) => !contraEmuladorDe([s], env));
  const renglones = faltan.flatMap((s) =>
    VARIABLES_POR_SERVICIO[s].map((v) => `${v}  (${estadoDeVariable(env[v])})`),
  );
  return [
    '',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '⛔  ABORTADO: este script es SOLO para el emulador, y lo que toca no',
    '⛔  está desviado:',
    '⛔',
    ...renglones.map((r) => `⛔    ${r}`),
    '⛔',
    '⛔  Levantá el emulador (SKIP_FUNCTIONS=1 ./scripts/emulator.sh) y',
    '⛔  exportá el host:',
    ...sugerenciasDeExport(faltan).map((s) => `⛔    ${s}`),
    '⛔',
    '⛔  Contexto: scripts/capturas/README.md / AGENTS.md → Entornos',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
}

/**
 * ¿Puede correr un script que sólo existe para el emulador?
 *
 * `servicios` son los que el script TOCA, con las claves de
 * `VARIABLES_POR_SERVICIO`. Devuelve `{ ok: true }` o
 * `{ ok: false, motivo, mensaje }`, sin efectos: la que corta el proceso es
 * `exigirSoloEmulador`.
 *
 *   'EN_BLANCO'    → alguna variable de emulador, de CUALQUIER servicio, está
 *                    en blanco. Primero, para que `' '` en
 *                    `FIRESTORE_EMULATOR_HOST` diga lo que es en vez de
 *                    "no está desviado". Y de cualquier servicio por el mismo
 *                    motivo que `credenciales.js`: el ambiente se contradice y
 *                    quien lo armó cree algo que no es.
 *   'SIN_EMULADOR' → alguno de los `servicios` no tiene host
 *                    (`contraEmuladorDe` exige TODOS).
 *
 * Una lista vacía o un servicio desconocido TIRAN antes de mirar el ambiente:
 * "no dije qué toco" no puede convertirse en un veredicto, ni en uno que deja
 * pasar ni en uno que aborta por el motivo equivocado.
 */
function veredictoSoloEmulador(servicios, env = process.env) {
  if (!Array.isArray(servicios) || servicios.length === 0) {
    throw new TypeError('veredictoSoloEmulador: hay que declarar qué servicios toca el script.');
  }
  for (const servicio of servicios) {
    if (!SERVICIOS.includes(servicio)) {
      throw new Error(`servicio desconocido: "${servicio}". Válidos: ${SERVICIOS.join(', ')}.`);
    }
  }

  const enBlanco = variablesEnBlanco(env);
  if (enBlanco.length > 0) {
    return { ok: false, motivo: 'EN_BLANCO', mensaje: mensajeEnBlanco(enBlanco, servicios) };
  }
  if (!contraEmuladorDe(servicios, env)) {
    return { ok: false, motivo: 'SIN_EMULADOR', mensaje: mensajeSinEmulador(servicios, env) };
  }
  return { ok: true };
}

/**
 * La compuerta en sí: imprime el motivo y sale con 1 si el script no puede
 * correr. Va ANTES de `initializeApp()`, que es donde el script se ata a un
 * destino.
 */
function exigirSoloEmulador(servicios, env = process.env) {
  const veredicto = veredictoSoloEmulador(servicios, env);
  if (!veredicto.ok) {
    process.stderr.write(veredicto.mensaje);
    process.exit(1);
  }
}

module.exports = {
  veredictoSoloEmulador,
  exigirSoloEmulador,
};
