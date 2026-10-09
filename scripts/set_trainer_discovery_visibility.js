/**
 * set_trainer_discovery_visibility.js
 *
 * Oculta (o vuelve a mostrar) a un PF en el directorio que ve el alumno
 * ("Encontrá tu coach": mapa, lista y online), SIN borrar la cuenta.
 *
 * Para qué: cuentas internas (la del dueño, una de QA, la del PF que usan los
 * revisores de Play / App Store) que no tienen que aparecerle a un alumno real,
 * pero que tienen que seguir pudiendo iniciar sesión y usar todo lo del PF.
 *
 * Qué escribe: SOLO `trainerPublicProfiles/{uid}.hiddenFromDiscovery` (bool),
 * con `merge`. Nada más. El repo del cliente filtra los listados con ese campo;
 * abrir el perfil por uid (link, chat, pantallas del propio PF) sigue andando.
 * Reversible: correlo de nuevo con `--hidden=false`.
 *
 * Es DRY-RUN por defecto: muestra qué haría y no escribe. `--apply` escribe.
 * Si el doc `trainerPublicProfiles/{uid}` no existe NO lo crea (un `merge`
 * fabricaría un perfil fantasma sin `uid` y rompería el parseo del cliente).
 *
 * Uso:
 *   # Con credencial (ver scripts/README.md, #834): la clave vive FUERA del repo.
 *   export TREINO_SA_KEY=/ruta/fuera/del/repo/sa.json
 *   cd scripts
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=true            # dry-run
 *   node set_trainer_discovery_visibility.js --email=<email> --hidden=true        # dry-run, uid por Auth
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=true --apply    # escribe
 *   node set_trainer_discovery_visibility.js --uid=<uid> --hidden=false --apply   # lo vuelve a mostrar
 *
 *   # Contra el emulador (sin credenciales):
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

  const ref = getFirestore(app).collection('trainerPublicProfiles').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`✗ trainerPublicProfiles/${uid} no existe: nada que ocultar. No se crea.`);
    process.exit(1);
  }

  const actual = snap.data().hiddenFromDiscovery;
  console.log(`  displayName:          ${snap.data().displayName ?? '(sin nombre)'}`);
  console.log(`  hiddenFromDiscovery:  ${actual === undefined ? '(ausente = visible)' : actual}  →  ${args.hidden}`);

  if (!args.apply) {
    console.log('\nDry-run: no se escribió nada. Repetí con --apply para aplicar.');
    return;
  }

  await ref.set({ hiddenFromDiscovery: args.hidden }, { merge: true });
  console.log(`\n✓ trainerPublicProfiles/${uid}.hiddenFromDiscovery = ${args.hidden}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
