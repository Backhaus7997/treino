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
 *
 * ─── Y EL DESTINO SON DOS COSAS, NO UNA ─────────────────────────────────────
 *
 * Producción se evalúa por proyecto Y por bucket, con un OR. El guard del #826
 * mira sólo el project id, que para un backfill de Firestore ES el destino;
 * para un script que sube archivos no lo es. `--project=treino-scratch
 * --bucket=treino-dev.firebasestorage.app` es una corrida contra producción con
 * un project id que no está en ninguna lista, y hasta que se agregó
 * `esBucketDeProduccion` pasaba sin cartel. Ver ahí el detalle.
 */

const fs = require('node:fs');
const path = require('node:path');

const {
  PROYECTOS_DE_PRODUCCION,
  esProduccion,
  bannerDeProduccion,
} = require('./firebase_projects');

/** `.firebaserc` de la raíz del repo — `scripts/lib/..` dos veces. */
const FIREBASERC = path.join(__dirname, '..', '..', '.firebaserc');

/** El sufijo de bucket que usa Firebase desde 2024 (antes era `.appspot.com`). */
const SUFIJO_BUCKET = '.firebasestorage.app';

/**
 * El sufijo VIEJO. No se usa para derivar nada —los buckets nuevos salen con el
 * de arriba— pero sí para RECONOCER: un `--bucket=treino-dev.appspot.com`
 * escrito de memoria por alguien que arrancó antes de 2024 apunta al mismo
 * proyecto de producción, y un guard que no lo reconoce no grita.
 */
const SUFIJO_BUCKET_LEGACY = '.appspot.com';

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
 * El nombre de bucket, sin el ruido que el Admin SDK igual tolera: `gs://`,
 * barra final, mayúsculas, espacios. Devuelve `''` si no hay nada que mirar.
 */
function normalizarBucket(bucket) {
  if (typeof bucket !== 'string') return '';
  return bucket.trim().toLowerCase().replace(/^gs:\/\//, '').replace(/\/+$/, '');
}

/**
 * ¿Este BUCKET es producción?
 *
 * Existe porque `esProduccion` mira el PROJECT ID, y para un script que sube
 * archivos el project id no es el destino: el destino es el bucket. Los dos se
 * pueden separar, y separarlos no requiere mala fe ni un caso rebuscado —
 * alcanza con un `--project` de prueba y un `--bucket` copiado del README:
 *
 *   node upload_drive_exercise_videos.js --project=treino-scratch \
 *        --bucket=treino-dev.firebasestorage.app
 *
 * Antes de este chequeo esa corrida imprimía `destino: prod (…)` en una línea
 * suelta y NO gritaba el cartel, porque `treino-scratch` no está en la lista.
 * Los `.mp4` terminaban igual en el bucket real — y Storage es justo lo que el
 * backup diario de Firestore NO cubre.
 *
 * Se reconoce por los tres nombres con los que se puede escribir el mismo
 * bucket de un proyecto de la lista: el sufijo nuevo, el legacy, y el id pelado
 * (que el SDK acepta y resuelve al default). La lista sigue siendo la del #826,
 * explícita — acá no se hereda ninguna heurística sobre el nombre.
 */
function esBucketDeProduccion(bucket) {
  const b = normalizarBucket(bucket);
  if (!b) return false;
  return PROYECTOS_DE_PRODUCCION.some(
    (p) => b === p || b === `${p}${SUFIJO_BUCKET}` || b === `${p}${SUFIJO_BUCKET_LEGACY}`,
  );
}

/**
 * El cartel para el caso "el proyecto no es producción pero el bucket sí".
 *
 * Es un cartel APARTE y no una rama del `bannerDeProduccion` del #826 a
 * propósito, por dos motivos. Uno: ése vive en `firebase_projects.js`, que es
 * copia literal del PR #835 y se borra al mergearlo — meterle una rama sería
 * plantar el conflicto que todo este archivo viene esquivando. Dos: diría una
 * cosa falsa. Su primera línea es `"<projectId>" IS PRODUCTION`, y acá el
 * projectId justamente NO lo es; lo que es producción es el bucket. Un cartel
 * que nombra mal lo que está en riesgo es el bug del #838 otra vez.
 */
function bannerDeBucketDeProduccion(bucket, projectId) {
  return [
    '',
    '🚨 ─────────────────────────────────────────────────────────────────────',
    `🚨  Bucket "${bucket}" IS PRODUCTION STORAGE.`,
    `🚨  The project ("${projectId}") is not, so the #826 project banner does`,
    '🚨  NOT fire — but the files land in the real bucket all the same.',
    '🚨',
    '🚨  The daily Firestore backup does NOT cover Cloud Storage: what this',
    '🚨  script writes there is gone for good.',
    '🚨',
    '🚨  Emulator instead:  FIRESTORE_EMULATOR_HOST=localhost:8080',
    '🚨                     FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199',
    '🚨  Context: issue #838 / AGENTS.md → Entornos',
    '🚨 ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
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

  // Contra el emulador ninguno de los dos nombres es un destino real: el SDK
  // enruta por la env var y tanto el project id como el bucket son namespaces
  // locales. Gritar ahí enseña a ignorar el cartel (misma razón que el
  // `contraEmulador` de `bannerDeProduccion`).
  const proyectoEsProduccion = !contraEmulador && esProduccion(projectId);
  const bucketEsProduccion = !contraEmulador && esBucketDeProduccion(bucket);

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
    proyectoEsProduccion,
    bucketEsProduccion,
    // El destino es producción si CUALQUIERA de los dos lo es. Que el proyecto
    // sea de prueba no vuelve descartable al bucket que recibe los archivos.
    esProduccion: proyectoEsProduccion || bucketEsProduccion,
    // Uno solo: si el proyecto ya es producción, el cartel del #826 cuenta la
    // historia entera y el del bucket sería una segunda pared de emojis que se
    // aprende a saltear. El del bucket es para el hueco que el otro no ve.
    banner:
      bannerDeProduccion(projectId, { contraEmulador }) ||
      (bucketEsProduccion ? bannerDeBucketDeProduccion(bucket, projectId) : null),
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
  SUFIJO_BUCKET_LEGACY,
  bannerDeBucketDeProduccion,
  bucketDeProyecto,
  emuladoresActivos,
  esBucketDeProduccion,
  exigirDestinoCoherente,
  planDeStorage,
  resolverBucket,
  resolverProjectId,
  textoDeAbort,
};
