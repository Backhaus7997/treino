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
 *
 * #834: lee `$TREINO_SA_KEY` además de `$GOOGLE_APPLICATION_CREDENTIALS`, en el
 * mismo orden que `lib/credenciales.js`. Este módulo NO valida la ruta —de eso
 * se ocupa la frontera, que corre igual un renglón más abajo—; acá sólo hace
 * falta saber el destino para poder nombrarlo en el cartel.
 */

const fs = require('node:fs');

/**
 * Qué variable de entorno desvía CADA servicio, con los nombres que lee el SDK.
 *
 * Storage tiene DOS: `firebase-admin` acepta las dos y normaliza
 * `FIREBASE_STORAGE_EMULATOR_HOST` a `STORAGE_EMULATOR_HOST`. Mirar una sola
 * daría un falso negativo — el mismo criterio que ya usa
 * `storage_target.js:emuladoresActivos()`.
 */
const VARIABLES_POR_SERVICIO = Object.freeze({
  firestore: Object.freeze(['FIRESTORE_EMULATOR_HOST']),
  auth: Object.freeze(['FIREBASE_AUTH_EMULATOR_HOST']),
  storage: Object.freeze(['STORAGE_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST']),
  database: Object.freeze(['FIREBASE_DATABASE_EMULATOR_HOST']),
});

const SERVICIOS = Object.freeze(Object.keys(VARIABLES_POR_SERVICIO));

/**
 * Vacío o whitespace NO cuenta: exportar la variable en blanco no desvía nada,
 * y tratarla como emulador apagaría la salvaguarda exactamente cuando el
 * proceso sí va a producción.
 */
function seteada(valor) {
  return typeof valor === 'string' && valor.trim() !== '';
}

/**
 * Qué emuladores están puestos, SERVICIO POR SERVICIO.
 *
 * ─── #846 — por qué esto reemplaza al `usandoEmulador()` que había ──────────
 *
 * Ese helper hacía un **OR** entre `FIRESTORE_EMULATOR_HOST` y
 * `FIREBASE_AUTH_EMULATOR_HOST` y devolvía UN booleano. En #826 eso era
 * suficiente porque sus dos únicos llamadores lo pasaban a
 * `bannerDeProduccion({contraEmulador})`: apagaba un CARTEL, no cambiaba una
 * decisión, y el peor caso era no gritar.
 *
 * `scripts/migrations/strip_appointment_reason.mjs` fue el primero en
 * ascenderlo a **compuerta de escritura**, y ahí el OR miente. Medido con
 * `--apply` y una key falsa:
 *
 *     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099   (y Firestore NO)
 *       → "emulador: sí", sin cartel, salteando las dos puertas
 *       → destino real: treino-dev, o sea PRODUCCIÓN, escribiendo
 *
 * Y es la situación de todos los días: esa variable queda exportada de una
 * sesión de `emulator.sh` o la hereda una shell. Es literalmente el modo de
 * fallar de #826 — una salvaguarda que tranquiliza justo contra producción.
 *
 * La forma correcta ya estaba a dos archivos: `storage_target.js` chequea POR
 * SERVICIO y aborta el split-brain. Un booleano global no puede responder la
 * única pregunta que importa antes de un write: **¿el servicio que voy a
 * ESCRIBIR está desviado?**
 */
function emuladoresActivos(env = process.env) {
  const estado = {};
  for (const servicio of SERVICIOS) {
    estado[servicio] = VARIABLES_POR_SERVICIO[servicio].some((v) => seteada(env[v]));
  }
  return estado;
}

/**
 * ¿TODOS los servicios que este proceso toca están desviados al emulador?
 *
 * `servicios` es la lista de los que el llamador va a ESCRIBIR o LEER, con las
 * claves de `VARIABLES_POR_SERVICIO`. Se exige que estén TODOS —no cualquiera—
 * porque basta que uno no lo esté para que el proceso le hable a producción:
 * es el mismo criterio del `contraEmulador` de `planDeStorage()`.
 *
 * Una lista vacía devuelve `false` a propósito. "No declaré qué toco" no es
 * "no toco nada", y un default permisivo acá es exactamente el bug que este
 * módulo dejó de tener.
 *
 * Un servicio desconocido tira: un typo (`'firestor'`) que devolviera `false`
 * silencioso convertiría una corrida contra el emulador en un cartel de
 * producción, y uno que devolviera `true` haría lo contrario. Que se rompa.
 */
function contraEmuladorDe(servicios, env = process.env) {
  if (!Array.isArray(servicios) || servicios.length === 0) return false;
  const estado = emuladoresActivos(env);
  return servicios.every((servicio) => {
    if (!Object.prototype.hasOwnProperty.call(estado, servicio)) {
      throw new Error(
        `servicio desconocido: "${servicio}". Válidos: ${SERVICIOS.join(', ')}.`,
      );
    }
    return estado[servicio];
  });
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

  // Las dos variables de credencial, en el orden en que las resuelve
  // `lib/credenciales.js`. `TREINO_SA_KEY` es la canónica desde #834; mirar
  // sólo `GOOGLE_APPLICATION_CREDENTIALS` dejaba sin cartel exactamente a quien
  // ya migró — o sea, al que hizo lo correcto. Ese es el peor reparto posible.
  const credPath = env.TREINO_SA_KEY || env.GOOGLE_APPLICATION_CREDENTIALS;
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

module.exports = {
  SERVICIOS,
  VARIABLES_POR_SERVICIO,
  emuladoresActivos,
  contraEmuladorDe,
  projectIdObjetivo,
};
