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
 * daría un falso negativo. `storage_target.js:emuladoresActivos()` delega acá
 * (antes tenía su propia copia con `Boolean()`, que contaba `' '` como host).
 */
const VARIABLES_POR_SERVICIO = Object.freeze({
  firestore: Object.freeze(['FIRESTORE_EMULATOR_HOST']),
  auth: Object.freeze(['FIREBASE_AUTH_EMULATOR_HOST']),
  storage: Object.freeze(['STORAGE_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST']),
  database: Object.freeze(['FIREBASE_DATABASE_EMULATOR_HOST']),
});

const SERVICIOS = Object.freeze(Object.keys(VARIABLES_POR_SERVICIO));

/** Las cinco variables, en el orden del mapa. */
const TODAS_LAS_VARIABLES = Object.freeze(SERVICIOS.flatMap((s) => VARIABLES_POR_SERVICIO[s]));

/**
 * Qué hace el SDK con cada variable EN BLANCO, para que el abort lo diga por
 * variable. Una frase genérica ("Firestore tira al inicializar") sería falsa el
 * día que la única en blanco sea la de Auth. Las de Firestore y Storage están
 * medidas corriendo el SDK; las de Auth y Database, leyendo su código.
 */
const EFECTO_EN_BLANCO = Object.freeze({
  FIRESTORE_EMULATOR_HOST: 'getFirestore() tira: "is not a valid host"',
  FIREBASE_AUTH_EMULATOR_HOST: 'Auth pasa a modo emulador (`!!host`) sin host',
  STORAGE_EMULATOR_HOST: 'Storage arma un endpoint inválido (`https://` + el blanco)',
  FIREBASE_STORAGE_EMULATOR_HOST:
    'con STORAGE_EMULATOR_HOST sin valor, firebase-admin la reescribe a un ' +
    'endpoint inválido (`http://` + el blanco)',
  FIREBASE_DATABASE_EMULATOR_HOST: 'Database pasa a modo emulador (`if (host)`) sin host',
});

/**
 * Los renglones que un abort imprime por cada variable en blanco: el nombre y
 * su `EFECTO_EN_BLANCO`, envuelto a `ancho`. Vive acá y no en cada mensaje para
 * que `credenciales.js` y `storage_target.js` digan exactamente lo mismo. No
 * imprime el valor: puede ser un tab o un salto de línea, y escribirlo como
 * `' '` sería mentir sobre lo que hay en el ambiente.
 */
function renglonesEnBlanco(variables, ancho = 62) {
  const out = [];
  for (const v of variables) {
    out.push(`${v}  (en blanco)`);
    let renglon = '  →';
    for (const palabra of EFECTO_EN_BLANCO[v].split(' ')) {
      if (renglon !== '  →' && `${renglon} ${palabra}`.length > ancho) {
        out.push(renglon);
        renglon = `    ${palabra}`;
      } else {
        renglon = `${renglon} ${palabra}`;
      }
    }
    out.push(renglon);
  }
  return out;
}

/**
 * Una variable de emulador tiene TRES estados, no dos:
 *
 *   'ausente'   → sin definir, o `''` (ver abajo la excepción de Storage).
 *   'puesta'    → tiene un host. El SDK desvía el servicio ahí.
 *   'en blanco' → sólo whitespace: espacios, tabs, saltos de línea. NO es
 *                 ninguna de las otras dos.
 *
 * ─── Por qué `' '` no es "ausente" (lo que este archivo decía antes) ───────
 *
 * El comentario de `seteada()` afirmaba que "exportar la variable en blanco no
 * desvía nada". Es falso. Medido con firebase-admin 14.5.0,
 * @google-cloud/firestore 9.3.1 y @google-cloud/storage 8.2.0, sin red
 * (tripwire en sockets y DNS), Firestore y Storage leen la variable con un
 * chequeo truthy —`if (host)`, `typeof host === 'string'`— y `' '` es truthy.
 * Auth (`!!host`) y Database (`if (host)`) hacen lo mismo, según su código:
 *
 *   FIRESTORE_EMULATOR_HOST=' '          → `getFirestore()` TIRA: "is not a valid host"
 *   FIREBASE_STORAGE_EMULATOR_HOST=' '   → firebase-admin la reescribe a `http:// `
 *   STORAGE_EMULATOR_HOST=' '            → endpoint `https:// `; ni una conexión
 *
 * O sea que el servicio que esa variable desvía no va al emulador, pero
 * TAMPOCO a la nube: se rompe. Los demás servicios van adonde diga el resto del
 * ambiente. Y los dos módulos que preguntaban esto contestaban cada uno una
 * mentira distinta: `storage_target.js` (con `Boolean()`) la contaba como
 * emulador —etiqueta `EMULADOR`, sin cartel—, y este archivo (con `trim()`)
 * como ausente —lo que hace que `lib/admin.js` inicialice CON la credencial de
 * la nube—. La misma corrida salía con las dos cosas a la vez. El ambiente no
 * describe un destino, así que el estado es propio y quien pregunta ABORTA:
 * ver `variablesEnBlanco`.
 *
 * `''` sí es "ausente", y se midió por separado: Firestore y firebase-admin
 * para Storage la ignoran (`''` es falsy), y Auth y Database también, según su
 * código. La excepción es `STORAGE_EMULATOR_HOST=''`, que @google-cloud/storage
 * lee con `typeof` y convierte en el endpoint `https:` (la subida termina
 * conectando a `upload:443`, sin autenticar). No se trata acá: el plan la
 * nombra NUBE, que es la dirección que grita, y nada llega al Storage real.
 */
function estadoDeVariable(valor) {
  if (typeof valor !== 'string' || valor === '') return 'ausente';
  return valor.trim() === '' ? 'en blanco' : 'puesta';
}

function seteada(valor) {
  return estadoDeVariable(valor) === 'puesta';
}

/**
 * Las variables de emulador exportadas EN BLANCO, de TODOS los servicios.
 *
 * No hay nada que hacer con ellas más que abortar: ver `estadoDeVariable`. Son
 * todas y no sólo las del servicio que el llamador toca, por la misma razón por
 * la que `credenciales.js` aborta ante una parcial: el ambiente se contradice y
 * quien lo armó cree algo que no es.
 *
 * Con UNA excepción, la que el SDK mismo hace: firebase-admin sólo mira
 * `FIREBASE_STORAGE_EMULATOR_HOST` si `STORAGE_EMULATOR_HOST` no tiene valor
 * (`if (!STORAGE_EMULATOR_HOST && FIREBASE_STORAGE_EMULATOR_HOST)`, en
 * `firebase-admin/lib/storage/storage.js`). Con la otra puesta, la de Firebase
 * en blanco el SDK la ignora —medido: Storage va a `localhost:9199`— y vale lo
 * mismo que vacía. Abortar ahí cortaba una corrida de emulador coherente, que
 * es una alarma falsa (lo marcó Codex en el #1445). Si la otra está EN BLANCO
 * no se excluye: la corrida aborta igual por ésa, y así el `unset` del mensaje
 * nombra las dos de una vez.
 */
function variablesEnBlanco(env = process.env) {
  const storageConHost = estadoDeVariable(env.STORAGE_EMULATOR_HOST) === 'puesta';
  return TODAS_LAS_VARIABLES.filter(
    (v) =>
      estadoDeVariable(env[v]) === 'en blanco' &&
      !(v === 'FIREBASE_STORAGE_EMULATOR_HOST' && storageConHost),
  );
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
  TODAS_LAS_VARIABLES,
  EFECTO_EN_BLANCO,
  VARIABLES_POR_SERVICIO,
  renglonesEnBlanco,
  estadoDeVariable,
  variablesEnBlanco,
  emuladoresActivos,
  contraEmuladorDe,
  projectIdObjetivo,
};
