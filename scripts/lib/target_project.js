'use strict';

/**
 * lib/target_project.js
 *
 * CONTRA QUÉ proyecto va a escribir este proceso, resuelto por las mismas
 * fuentes y en el mismo orden que usa el Admin SDK. Nada más que eso.
 *
 * Por qué existe (#826): `lib/firebase_projects.js` sabe QUÉ ids son
 * producción, pero necesita que alguien le pase el id. Los backfills lo tenían
 * a mano —hacen `require('./sa-key.json')` y leen `project_id`—. Los
 * entrypoints de los npm scripts NO: `seed_workout_catalog.js` y
 * `promote_user_to_trainer.js` llaman a `admin.initializeApp()` pelado y dejan
 * que el SDK resuelva el proyecto desde el entorno. O sea que el camino de
 * invocación más corto que hay —`npm run seed:all`— era justo el que no podía
 * decir a dónde estaba escribiendo.
 *
 * Ese es el agujero que encontró la revisión: el barrido anterior buscaba
 * `firebase` y `gcloud`, y estos 39 de 43 scripts —el riesgo MAYOR que declara
 * el propio PR— no se invocan así. Se invocan con `npm run`.
 *
 * Separado de `firebase_projects.js` a propósito: ese módulo es una regla pura
 * (un id, un booleano) y se queda sin I/O. Este lee el entorno y, si hace
 * falta, el JSON de credenciales — un `readFileSync` de un archivo local, sin
 * red y sin `firebase-admin`, para que siga siendo testeable en milisegundos.
 */

const fs = require('node:fs');

/**
 * ¿Este proceso apunta al emulador?
 *
 * Cualquiera de las dos variables alcanza: `FIRESTORE_EMULATOR_HOST` desvía
 * Firestore y `FIREBASE_AUTH_EMULATOR_HOST` desvía Auth, y un script que setea
 * una sola igual está en modo local. Vacío o whitespace NO cuenta: exportar la
 * variable en blanco no desvía nada, y tratarla como emulador apagaría el
 * cartel exactamente cuando el proceso sí va a producción.
 */
function usandoEmulador(env = process.env) {
  const hosts = [env.FIRESTORE_EMULATOR_HOST, env.FIREBASE_AUTH_EMULATOR_HOST];
  return hosts.some((h) => typeof h === 'string' && h.trim() !== '');
}

/**
 * El project id contra el que va a escribir este proceso, o `null` si no se
 * puede saber desde el entorno.
 *
 * El orden replica al del Admin SDK: primero las variables explícitas de
 * proyecto, después la credencial. Si devuelve `null` el llamador NO debe
 * inventar nada —callar es correcto—: significa que el proyecto lo va a
 * resolver el SDK por un camino que este módulo no ve (metadata server de GCP,
 * un `projectId` pasado a mano a `initializeApp`), y afirmar "no es producción"
 * ahí sería la misma clase de falsa tranquilidad que motivó el issue.
 */
function projectIdObjetivo(env = process.env) {
  const explicito = env.GOOGLE_CLOUD_PROJECT || env.GCLOUD_PROJECT;
  if (typeof explicito === 'string' && explicito.trim() !== '') {
    return explicito.trim();
  }

  const credPath = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (typeof credPath !== 'string' || credPath.trim() === '') return null;

  try {
    const json = JSON.parse(fs.readFileSync(credPath.trim(), 'utf8'));
    const id = json && json.project_id;
    return typeof id === 'string' && id.trim() !== '' ? id.trim() : null;
  } catch {
    // Credencial ausente o ilegible: el script va a morir solo un renglón más
    // abajo con un error mucho más claro que el que podríamos dar acá.
    return null;
  }
}

module.exports = { usandoEmulador, projectIdObjetivo };
