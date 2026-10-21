/**
 * set_trainer_discovery_visibility.js
 *
 * Oculta (o vuelve a mostrar) a una cuenta INTERNA en todas las superficies
 * públicas de listado, SIN borrar la cuenta:
 *
 *   - `trainerPublicProfiles/{uid}` → directorio de coaches que ve el alumno
 *     ("Encontrá tu coach": mapa, lista y online).
 *   - `userPublicProfiles/{uid}`    → búsqueda de personas, «gente para
 *     seguir» del feed y rankings por gym.
 *
 * Para qué: cuentas internas (soporte, la del dueño, una de QA, las que usan
 * los revisores de Play / App Store) que no tienen que aparecerle a un usuario
 * real, pero que tienen que seguir pudiendo iniciar sesión y usar todo.
 *
 * Qué escribe: SOLO `hiddenFromDiscovery` (bool), con `merge`, en cada uno de
 * los dos docs QUE EXISTA. Nada más. El cliente filtra los listados con ese
 * campo; abrir el perfil por uid (link, chat, pantallas propias) sigue andando.
 * Reversible: correlo de nuevo con `--hidden=false`.
 *
 * Es DRY-RUN por defecto: muestra qué haría y no escribe. `--apply` escribe.
 * Un doc que no existe NO se crea (un `merge` fabricaría un perfil fantasma
 * sin `uid` y rompería el parseo del cliente). Un atleta no tiene
 * `trainerPublicProfiles`: se saltea y se dice. Si no existe NINGUNO, falla.
 *
 * ⚠️  ORDEN: reglas → este script. Nunca al revés.
 * Las reglas de `userPublicProfiles` validan el doc ENTERO con
 * `keys().hasOnly(...)`. Si este script le escribe el campo a un perfil y las
 * reglas desplegadas todavía no lo conocen, ese usuario NO puede volver a
 * actualizar su perfil desde la app (contadores, gym, nombre: todo
 * permission-denied). Por eso, con `--apply` contra un proyecto real, el
 * script LEE las reglas desplegadas y aborta si el bloque de
 * `userPublicProfiles` no nombra el campo. (Buscarlo en todo el archivo no
 * sirve: `trainerPublicProfiles` ya lo nombra desde antes.)
 *
 * Uso:
 *   # Con credencial (ver scripts/README.md, #834): la clave vive FUERA del repo.
 *   export TREINO_SA_KEY=/ruta/fuera/del/repo/sa.json
 *   cd scripts
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=true            # dry-run
 *   node set_trainer_discovery_visibility.js --email=<email> --hidden=true        # dry-run, uid por Auth
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=true --apply    # escribe
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=false --apply   # la vuelve a mostrar
 *
 *   # Contra el emulador (sin credenciales ni chequeo de reglas):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/set_trainer_discovery_visibility.js --uid=<uid> --hidden=true --apply
 *
 * Con `--email` se resuelve el uid por Firebase Auth; contra el emulador hace
 * falta además `FIREBASE_AUTH_EMULATOR_HOST`.
 */

'use strict';

const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const FLAGS_VALIDAS = ['--uid', '--email', '--hidden', '--apply'];
const CAMPO = 'hiddenFromDiscovery';
const COLECCIONES = ['trainerPublicProfiles', 'userPublicProfiles'];
const RULES_API = 'https://firebaserules.googleapis.com/v1';

function parseArgs(argv) {
  const out = { uid: null, email: null, hidden: null, apply: false };
  for (const arg of argv.slice(2)) {
    const [flag, ...resto] = arg.split('=');
    const valor = resto.join('=');
    if (!FLAGS_VALIDAS.includes(flag)) {
      throw new Error(`Flag desconocida: ${arg}`);
    }
    if (flag === '--apply') out.apply = true;
    else if (flag === '--uid') out.uid = valor;
    else if (flag === '--email') out.email = valor;
    else if (flag === '--hidden') {
      if (valor !== 'true' && valor !== 'false') {
        throw new Error('--hidden tiene que ser true o false');
      }
      out.hidden = valor === 'true';
    }
  }
  if (out.hidden === null) throw new Error('Falta --hidden=true|false');
  if (!out.uid && !out.email) throw new Error('Falta --uid=<uid> o --email=<email>');
  if (out.uid && out.email) throw new Error('Pasá --uid O --email, no los dos');
  return out;
}

/**
 * `true` si el bloque `match /userPublicProfiles/{uid}` de [fuente] nombra el
 * campo entre comillas simples, que es como aparece en sus allowlists
 * `hasOnly`. Corta el bloque en el siguiente `match /` al principio de una
 * línea —no en uno citado dentro de un comentario— para no contar la
 * mención de `trainerPublicProfiles`.
 */
function reglasDePerfilesConocenElCampo(fuente) {
  const inicio = fuente.search(/^\s*match \/userPublicProfiles\//m);
  if (inicio === -1) return false;
  const despues = fuente.indexOf('\n', inicio);
  const resto = despues === -1 ? '' : fuente.slice(despues);
  const fin = resto.search(/^\s*match \//m);
  const bloque = fin === -1 ? resto : resto.slice(0, fin);
  return bloque.includes(`'${CAMPO}'`);
}

/** Fuente del ruleset de Firestore DESPLEGADO en [projectId]. Tira si no la puede leer. */
async function fuenteDeReglasDesplegadas(credential, projectId, { fetchImpl = fetch } = {}) {
  const { access_token: token } = await credential.getAccessToken();
  const headers = { Authorization: `Bearer ${token}` };

  const release = await fetchImpl(
    `${RULES_API}/projects/${projectId}/releases/cloud.firestore`,
    { headers },
  );
  if (!release.ok) throw new Error(`release de cloud.firestore: HTTP ${release.status}`);
  const { rulesetName } = await release.json();

  const ruleset = await fetchImpl(`${RULES_API}/${rulesetName}`, { headers });
  if (!ruleset.ok) throw new Error(`ruleset ${rulesetName}: HTTP ${ruleset.status}`);
  const { source } = await ruleset.json();
  return (source?.files ?? []).map((f) => f.content ?? '').join('\n');
}

async function main() {
  let args;
  try {
    args = parseArgs(process.argv);
  } catch (e) {
    console.error(`✗ ${e.message}`);
    console.error(
      'Uso: node set_trainer_discovery_visibility.js (--uid=<uid>|--email=<email>) --hidden=true|false [--apply]',
    );
    process.exit(1);
  }

  // El cartel ANTES de inicializar nada (mismo idioma que cleanup_rejected_links.js).
  const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
    contraEmulador: contraEmuladorDe(['firestore']),
  });
  if (bannerProd) console.warn(bannerProd);

  const { app, contexto } = inicializarAdmin();
  const proyecto = contexto ? proyectoDe(contexto) : '(app ya inicializada)';

  let uid = args.uid;
  if (args.email) {
    const user = await getAuth(app).getUserByEmail(args.email);
    uid = user.uid;
  }

  console.log('═'.repeat(66));
  console.log(`  PROYECTO: ${proyecto}`);
  console.log(`  MODO:     ${args.apply ? '⚠️  APPLY — ESCRIBE' : 'dry-run (no escribe nada)'}`);
  console.log(`  UID:      ${uid}${args.email ? `  (por email ${args.email})` : ''}`);
  console.log('═'.repeat(66));

  const db = getFirestore(app);
  const existentes = [];
  for (const coleccion of COLECCIONES) {
    const ref = db.collection(coleccion).doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      console.log(`  ${coleccion}: no existe — se saltea (no se crea).`);
      continue;
    }
    const actual = snap.data()[CAMPO];
    console.log(
      `  ${coleccion}: «${snap.data().displayName ?? '(sin nombre)'}»  ` +
        `${CAMPO}: ${actual === undefined ? '(ausente = visible)' : actual}  →  ${args.hidden}`,
    );
    existentes.push({ coleccion, ref });
  }

  if (existentes.length === 0) {
    console.error(`✗ El uid ${uid} no tiene perfil público en ninguna colección: nada que ocultar.`);
    process.exit(1);
  }

  if (!args.apply) {
    console.log('\nDry-run: no se escribió nada. Repetí con --apply para aplicar.');
    return;
  }

  const tocaPerfiles = existentes.some((e) => e.coleccion === 'userPublicProfiles');
  if (tocaPerfiles && contexto?.modo !== 'emulador') {
    let conocen;
    try {
      const fuente = await fuenteDeReglasDesplegadas(app.options.credential, proyecto);
      conocen = reglasDePerfilesConocenElCampo(fuente);
    } catch (err) {
      console.error(
        `✗ No pude leer las reglas desplegadas de ${proyecto}: ${err.message}\n` +
          '  Sin eso no escribo: si las reglas no conocen el campo, esta cuenta no\n' +
          '  puede volver a editar su perfil desde la app.',
      );
      process.exit(1);
    }
    if (!conocen) {
      console.error(
        `✗ Las reglas DESPLEGADAS en ${proyecto} no conocen '${CAMPO}' en userPublicProfiles.\n` +
          '  Deployá primero las reglas. No se escribió nada. Ver el encabezado.',
      );
      process.exit(1);
    }
    console.log(`✓ Las reglas desplegadas ya conocen '${CAMPO}' en userPublicProfiles.`);
  }

  for (const { coleccion, ref } of existentes) {
    await ref.set({ [CAMPO]: args.hidden }, { merge: true });
    console.log(`✓ ${coleccion}/${uid}.${CAMPO} = ${args.hidden}`);
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { parseArgs, reglasDePerfilesConocenElCampo };
