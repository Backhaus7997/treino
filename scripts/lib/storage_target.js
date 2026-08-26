'use strict';

/**
 * lib/storage_target.js
 *
 * CONTRA QUÉ BUCKET DE STORAGE va a escribir un script, y si ese destino es
 * coherente con el de Firestore. Puro: sin `firebase-admin`, sin red; lo único
 * que toca del disco es `.firebaserc`, y por una ruta inyectable.
 *
 * Por qué existe (#838): cuatro scripts de `scripts/` hardcodeaban
 * `treino-dev.firebasestorage.app` y ninguna variable de entorno los redirigía.
 * El peor —`extract_exercise_thumbnails.js`— chequeaba `FIRESTORE_EMULATOR_HOST`
 * e imprimía `destino: EMULADOR`, pero `initializeApp({ storageBucket })` seguía
 * apuntando al bucket real: el operador leía EMULADOR y los `.jpg` terminaban en
 * producción, con la URL de prod metida en el Firestore local. Misma familia que
 * el #826: la salvaguarda existe, se ve, y apunta al lugar equivocado.
 *
 * ─── LA DECISIÓN DE FONDO: ABORTAR, NO AUTO-REDIRIGIR ───────────────────────
 *
 * Había dos salidas para el caso 1 y se eligió abortar. El motivo NO es que
 * redirigir sea difícil —de hecho es gratis: `firebase-admin` ya lee
 * `STORAGE_EMULATOR_HOST` / `FIREBASE_STORAGE_EMULATOR_HOST` solo, adentro de
 * `admin.storage()` (ver `firebase-admin/lib/storage/storage.js`), así que si el
 * operador exporta la variable el redirect pasa sin que el script haga nada—.
 * El motivo es que forzarla desde el script inventaría un destino que el
 * operador no pidió, y encima uno que hoy no existe: `scripts/emulator.sh`
 * arranca `--only firestore,auth,functions`, o sea que el emulador de Storage
 * (declarado en `firebase.json`, puerto 9199) NO está levantado en la corrida
 * normal. Auto-redirigir cambiaría "sube a prod calladito" por "explota con
 * ECONNREFUSED en el archivo 37, con 36 documentos ya patcheados": otra vez
 * datos partidos en dos entornos, que es exactamente el daño que se quiere
 * evitar.
 *
 * Entonces la regla es una sola y no admite grises: **Firestore y Storage
 * apuntan los dos al emulador, o los dos a la nube. Cualquier mezcla aborta
 * antes de la primera escritura.** Un script que escribe mitad en local y mitad
 * en prod deja basura en los dos lados y ninguna de las dos mitades se puede
 * revertir mirando la otra.
 */

const fs = require('node:fs');
const path = require('node:path');

const { esProduccion, bannerDeProduccion } = require('./firebase_projects');

/** `.firebaserc` de la raíz del repo — `scripts/lib/..` dos veces. */
const FIREBASERC = path.join(__dirname, '..', '..', '.firebaserc');

/** El sufijo de bucket que usa Firebase desde 2024 (antes era `.appspot.com`). */
const SUFIJO_BUCKET = '.firebasestorage.app';

/** Lee `--nombre=valor` de un argv ya cortado (sin `node` ni el script). */
function opcion(argv, nombre) {
  const hit = (argv || []).find((a) => typeof a === 'string' && a.startsWith(`--${nombre}=`));
  return hit ? hit.split('=').slice(1).join('=').trim() : null;
}

/**
 * El project id que declara `.firebaserc`, o `null` si no se puede leer.
 *
 * Es el último recurso a propósito: es lo que el repo declara, no lo que la
 * corrida realmente va a usar. Si hay credenciales o env var, ganan ellas.
 */
function proyectoDeFirebaserc(ruta = FIREBASERC) {
  try {
    const rc = JSON.parse(fs.readFileSync(ruta, 'utf8'));
    const dflt = rc && rc.projects && rc.projects.default;
    return typeof dflt === 'string' && dflt ? dflt : null;
  } catch {
    return null; // sin .firebaserc legible no hay default; el llamador decide
  }
}

/** El `project_id` del service account apuntado por una ruta, o `null`. */
function proyectoDeSaKey(ruta) {
  if (!ruta) return null;
  try {
    const sa = JSON.parse(fs.readFileSync(ruta, 'utf8'));
    return typeof sa.project_id === 'string' && sa.project_id ? sa.project_id : null;
  } catch {
    return null; // credenciales ilegibles: que falle el SDK con su propio error
  }
}

/**
 * Contra qué proyecto corre esto, y de dónde salió el dato.
 *
 * El orden imita al del propio Admin SDK para que lo que imprimimos sea lo que
 * realmente va a pasar, no una segunda opinión:
 *   1. `--project=` explícito (lo que el operador pidió gana siempre)
 *   2. `GOOGLE_CLOUD_PROJECT` / `GCLOUD_PROJECT` (las que mira el SDK)
 *   3. el `project_id` del `GOOGLE_APPLICATION_CREDENTIALS`
 *   4. `.firebaserc`
 */
function resolverProjectId({ argv = [], env = process.env, rutaFirebaserc = FIREBASERC } = {}) {
  const porFlag = opcion(argv, 'project');
  if (porFlag) return { projectId: porFlag, origen: '--project=' };

  const porEnv = env.GOOGLE_CLOUD_PROJECT || env.GCLOUD_PROJECT;
  if (porEnv) return { projectId: porEnv.trim(), origen: 'GOOGLE_CLOUD_PROJECT' };

  const porSaKey = proyectoDeSaKey(env.GOOGLE_APPLICATION_CREDENTIALS);
  if (porSaKey) return { projectId: porSaKey, origen: 'GOOGLE_APPLICATION_CREDENTIALS' };

  const porRc = proyectoDeFirebaserc(rutaFirebaserc);
  if (porRc) return { projectId: porRc, origen: '.firebaserc' };

  return { projectId: null, origen: null };
}

/** El bucket por defecto de un proyecto. `null` si no hay proyecto. */
function bucketDeProyecto(projectId) {
  if (typeof projectId !== 'string' || !projectId.trim()) return null;
  return `${projectId.trim()}${SUFIJO_BUCKET}`;
}

/**
 * Contra qué bucket, y de dónde salió.
 *
 * `--bucket=` y `FIREBASE_STORAGE_BUCKET` existen para poder apuntar a otro
 * lado sin editar código — que es la mitad del #838: el hardcodeo no sólo
 * mentía, tampoco dejaba salida—. El default se DERIVA del proyecto activo, así
 * que el día que exista un proyecto de dev de verdad, estos scripts lo siguen
 * sin que nadie los toque.
 */
function resolverBucket({ argv = [], env = process.env, projectId = null } = {}) {
  const porFlag = opcion(argv, 'bucket');
  if (porFlag) return { bucket: porFlag, origen: '--bucket=' };

  const porEnv = env.FIREBASE_STORAGE_BUCKET;
  if (porEnv) return { bucket: porEnv.trim(), origen: 'FIREBASE_STORAGE_BUCKET' };

  const derivado = bucketDeProyecto(projectId);
  return derivado
    ? { bucket: derivado, origen: `derivado de ${projectId}` }
    : { bucket: null, origen: null };
}

/**
 * Qué emuladores están puestos, según las MISMAS variables que lee el SDK.
 *
 * Storage: `firebase-admin` acepta las dos, y normaliza
 * `FIREBASE_STORAGE_EMULATOR_HOST` a `STORAGE_EMULATOR_HOST`. Mirar sólo una de
 * las dos daría un falso negativo y abortaría una corrida que estaba bien.
 */
function emuladoresActivos(env = process.env) {
  return {
    firestore: Boolean(env.FIRESTORE_EMULATOR_HOST),
    storage: Boolean(env.STORAGE_EMULATOR_HOST || env.FIREBASE_STORAGE_EMULATOR_HOST),
  };
}

/**
 * El plan completo del destino: proyecto, bucket, emuladores, si es coherente y
 * qué cartel corresponde. Puro y sin efectos — el que decide morirse es
 * `exigirDestinoCoherente`, para que el test pueda mirar el plan sin subprocesos.
 *
 * `etiquetaDestino` es lo que el script tiene DERECHO a imprimir. Cuando el
 * destino es incoherente vale `null`, y eso es deliberado: el bug del #838 fue
 * un script que tenía una etiqueta para todos los casos y elegía la equivocada.
 * Si no hay verdad que contar, no hay etiqueta que imprimir.
 */
function planDeStorage({ argv = [], env = process.env, rutaFirebaserc = FIREBASERC } = {}) {
  const { projectId, origen: origenProyecto } = resolverProjectId({ argv, env, rutaFirebaserc });
  const { bucket, origen: origenBucket } = resolverBucket({ argv, env, projectId });
  const emu = emuladoresActivos(env);

  const contraEmulador = emu.firestore && emu.storage;
  const enLaNube = !emu.firestore && !emu.storage;
  const coherente = contraEmulador || enLaNube;

  let motivo = null;
  if (emu.firestore && !emu.storage) {
    motivo =
      'Firestore apunta al EMULADOR (FIRESTORE_EMULATOR_HOST) pero Storage NO: ' +
      `las subidas irían al bucket real "${bucket}" y la URL de producción ` +
      'quedaría escrita en el Firestore local.';
  } else if (!emu.firestore && emu.storage) {
    motivo =
      'Storage apunta al EMULADOR (STORAGE_EMULATOR_HOST) pero Firestore NO: ' +
      'quedarían URLs de localhost escritas en el Firestore de producción, que ' +
      'ningún cliente puede abrir.';
  }

  return {
    projectId,
    origenProyecto,
    bucket,
    origenBucket,
    emuladorFirestore: emu.firestore,
    emuladorStorage: emu.storage,
    contraEmulador,
    coherente,
    motivo,
    esProduccion: !contraEmulador && esProduccion(projectId),
    banner: bannerDeProduccion(projectId, { contraEmulador }),
    etiquetaDestino: !coherente
      ? null
      : contraEmulador
        ? 'EMULADOR (Firestore + Storage)'
        : `prod (${bucket})`,
  };
}

/**
 * El texto del abort. Separado del `process.exit` para poder assertarlo sin
 * matar el proceso del test.
 */
function textoDeAbort(plan) {
  // El motivo se arma como una sola oración (así el test lo asserta con un
  // match limpio) pero se imprime envuelto: un renglón de 200 caracteres en una
  // terminal angosta es un renglón que nadie lee.
  const motivo = [];
  let renglon = '';
  for (const palabra of String(plan.motivo || '').split(/\s+/)) {
    if (renglon && (renglon + ' ' + palabra).length > 66) {
      motivo.push(`⛔  ${renglon}`);
      renglon = palabra;
    } else {
      renglon = renglon ? `${renglon} ${palabra}` : palabra;
    }
  }
  if (renglon) motivo.push(`⛔  ${renglon}`);

  return [
    '',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '⛔  ABORTADO: el destino de Firestore y el de Storage no coinciden.',
    '⛔',
    ...motivo,
    '⛔',
    '⛔  Este script NO corre a medias: escribir mitad en local y mitad en la',
    '⛔  nube deja datos rotos en los dos lados (#838).',
    '⛔',
    '⛔  Para correr entero contra el emulador, levantalo CON Storage y',
    '⛔  exportá las dos variables:',
    '⛔    firebase emulators:start --only firestore,auth,storage',
    '⛔    export FIRESTORE_EMULATOR_HOST=localhost:8080',
    '⛔    export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199',
    '⛔  (ojo: scripts/emulator.sh NO levanta Storage — arranca --only',
    '⛔   firestore,auth,functions.)',
    '⛔',
    '⛔  Para correr entero contra la nube, sacá FIRESTORE_EMULATOR_HOST del',
    '⛔  ambiente. Leé el cartel que sale después: es producción.',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
}

/**
 * Resuelve el destino, lo imprime, y corta la corrida si no se puede contar la
 * verdad. Devuelve el plan cuando se puede seguir.
 *
 * El orden importa y es el mismo que fijó el #826: primero el abort (nada que
 * mostrar si no vamos a correr), después el cartel de producción, y recién
 * después lo que el script quiera loguear. Un cartel que sale detrás de un
 * "subiendo 793 thumbs…" ya llegó tarde.
 */
function exigirDestinoCoherente({
  argv = process.argv.slice(2),
  env = process.env,
  rutaFirebaserc = FIREBASERC,
  salida = console,
  morir = (codigo) => process.exit(codigo),
} = {}) {
  const plan = planDeStorage({ argv, env, rutaFirebaserc });

  if (!plan.projectId || !plan.bucket) {
    salida.error(
      '\n⛔ ABORTADO: no pude resolver contra qué proyecto/bucket corre esto.\n' +
        '   Pasá --project=<id> y/o --bucket=<bucket>, o exportá ' +
        'GOOGLE_APPLICATION_CREDENTIALS (#838).\n',
    );
    morir(1);
    return plan;
  }

  if (!plan.coherente) {
    salida.error(textoDeAbort(plan));
    morir(1);
    return plan;
  }

  // La etiqueta la imprime EL GUARD, no cada script. Ése es el arreglo del
  // #838: mientras cada uno armaba su propia frase ("destino: EMULADOR") a
  // partir de su propia lectura del ambiente, una de ellas podía contradecir a
  // lo que el SDK hacía — y contradecía. Acá sale del mismo objeto que decidió
  // si la corrida sigue, así que no hay dos versiones que puedan divergir.
  salida.log(
    `Proyecto: ${plan.projectId} (${plan.origenProyecto}) · bucket: ${plan.bucket} ` +
      `(${plan.origenBucket}) · destino: ${plan.etiquetaDestino}`,
  );
  if (plan.banner) {
    salida.warn(plan.banner);
    // El cartel del #826 dice "Emulator instead: FIRESTORE_EMULATOR_HOST=…", y
    // para un script que sube a Storage ese consejo, solo, termina en el abort
    // de arriba. Se completa acá y no en el cartel porque el cartel lo comparten
    // los backfills, que no tocan Storage y no tienen por qué exportar nada.
    salida.warn(
      '🚨  Ojo: este script escribe en Storage. Para el emulador hace falta\n' +
        '🚨  TAMBIÉN  FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199  (#838).\n',
    );
  }

  return plan;
}

module.exports = {
  SUFIJO_BUCKET,
  bucketDeProyecto,
  emuladoresActivos,
  exigirDestinoCoherente,
  planDeStorage,
  resolverBucket,
  resolverProjectId,
  textoDeAbort,
};
