'use strict';

/**
 * backfill_trainer_public_avatar.js
 *
 * Copia `users/{uid}.avatarUrl` a `trainerPublicProfiles/{uid}.avatarUrl` en las tarjetas que
 * quedaron con la foto vieja o sin foto (#1718). Hasta #1706 cambiar la foto actualizaba `users/`
 * pero dejaba la tarjeta de Discovery como estaba; y hasta #1766 una tarjeta nueva nacía sin la
 * foto que la cuenta ya tenía. #1706 y #1766 arreglan de ahí en adelante; esto barre lo que ya quedó.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN (AGENTS.md § Entornos). `--apply` escribe sobre tarjetas
 *     públicas de usuarios reales: dry-run primero, siempre, y leé los conteos antes de escribir.
 * Por tarjeta existente (nunca crea una), con el `users/{uid}` de su dueño como fuente de verdad:
 *   · el dueño no existe o no es `role == 'trainer'` (tarjeta forjada)    -> se omite y se informa.
 *   · la cuenta tiene foto y la tarjeta no tiene esa misma                  -> COPIA (sin foto / otra foto).
 *   · la cuenta NO tiene foto (null, ausente o en blanco) y la tarjeta sí    -> «foto quitada»: es el
 *     «Quitar foto» anterior a #1706. Se informa y NO se toca: borrar la URL es lo único destructivo de
 *     este script. Con `--limpiar-fotos-quitadas` la pone en `null`, como hace la app desde #1694.
 *   · `avatarUrl` de la cuenta que no es string                              -> sin decidir.
 * Sólo escribe `avatarUrl` (`update`, no `set merge`: si la tarjeta se borró no la resucita). No imprime
 * las URLs (llevan token): sólo el uid y el tipo de cambio. El cambio se re-evalúa en una transacción por
 * tarjeta; si ya no coincide con lo que se informó, no se escribe. Idempotente.
 * USO (credencial: `export TREINO_SA_KEY=~/.config/treino/sa-key.json`, scripts/README.md #834)
 *   node scripts/backfill_trainer_public_avatar.js                              # DRY-RUN (default)
 *   node scripts/backfill_trainer_public_avatar.js --apply                      # escribe (`--apply --dry-run` NO)
 *   node scripts/backfill_trainer_public_avatar.js --apply --limpiar-fotos-quitadas
 *   # Emulador, sin clave. `--project` sólo existe contra el emulador (namespace local):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_trainer_public_avatar.js --project=demo-treino
 */

const { FieldPath, getFirestore } = require('firebase-admin/firestore');
const { inicializarAdmin, proyectoDe } = require('./lib/admin'); // la única puerta (#834)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');

const PAGE_SIZE = 500;
const TARJETAS_POR_TANDA = 300;

function parseArgs(argv) {
  const out = { write: false, limpiar: false, project: null };
  let dryRun = false;
  for (const arg of argv.slice(2)) {
    if (arg === '--apply') out.write = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg === '--limpiar-fotos-quitadas') out.limpiar = true;
    else if (arg.startsWith('--project=')) out.project = arg.slice('--project='.length) || null;
    else throw new Error(`Flag desconocida: "${arg}"`);
  }
  if (dryRun) out.write = false; // ante flags en conflicto gana la que NO escribe
  return out;
}

/**
 * Qué hacer con una tarjeta. Puro. `user` y `card` son `data()` o null.
 * Devuelve { accion, valor? }: 'no-entrenador' | 'sin-decidir' | 'igual' | 'copiar-sin-foto' | 'copiar-otra-foto' | 'foto-quitada'.
 */
function decidir(user, card) {
  if (!user || user.role !== 'trainer') return { accion: 'no-entrenador' };
  const cuenta = user.avatarUrl;
  if (cuenta != null && typeof cuenta !== 'string') return { accion: 'sin-decidir' };
  const deseada = typeof cuenta === 'string' && cuenta.trim() !== '' ? cuenta.trim() : null;
  const actual = typeof card.avatarUrl === 'string' && card.avatarUrl.trim() !== '' ? card.avatarUrl : null;
  if (deseada === null) return { accion: actual === null ? 'igual' : 'foto-quitada', valor: null };
  if (actual === deseada) return { accion: 'igual' };
  return { accion: actual === null ? 'copiar-sin-foto' : 'copiar-otra-foto', valor: deseada };
}

/** Escribe `avatarUrl` si, adentro de la transacción, la decisión sigue siendo la que se informó. */
function escribir(db, uid, planeada) {
  const tarjeta = db.collection('trainerPublicProfiles').doc(uid);
  const usuario = db.collection('users').doc(uid);
  return db.runTransaction(async (tx) => {
    const [t, u] = await Promise.all([tx.get(tarjeta), tx.get(usuario)]);
    if (!t.exists) return false;
    const d = decidir(u.exists ? u.data() : null, t.data());
    if (d.accion !== planeada) return false;
    tx.update(tarjeta, { avatarUrl: d.valor });
    return true;
  });
}

const FILAS = {
  tarjetas: 'tarjetas escaneadas', noEntrenador: 'dueño que no es entrenador (o sin users/): se omiten',
  iguales: 'ya coinciden con la cuenta: intactas', copiarSinFoto: 'a COPIAR: la tarjeta no tenía foto',
  copiarOtraFoto: 'a COPIAR: la tarjeta tenía otra foto', fotoQuitada: 'foto quitada (cuenta sin foto, tarjeta con foto)',
  escritas: 'tarjetas ESCRITAS', sinDecidir: 'sin decidir (revisar a mano, NO se tocan)',
};
const CONTADOR = { 'no-entrenador': 'noEntrenador', igual: 'iguales', 'copiar-sin-foto': 'copiarSinFoto',
  'copiar-otra-foto': 'copiarOtraFoto', 'foto-quitada': 'fotoQuitada' };

/** `db`: Firestore; `opts`: { write, limpiar?, pagina? }; `out`: { log, warn }. Devuelve los conteos. */
async function run(db, opts, out = console) {
  const r = { tarjetas: 0, noEntrenador: 0, iguales: 0, copiarSinFoto: 0, copiarOtraFoto: 0, fotoQuitada: 0,
    sinDecidir: [], aEscribir: [], escritas: 0, cambiaron: 0 };
  const pagina = opts.pagina || PAGE_SIZE;

  for (let cursor = null; ;) {
    let q = db.collection('trainerPublicProfiles').orderBy(FieldPath.documentId()).limit(pagina);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    for (let i = 0; i < snap.docs.length; i += TARJETAS_POR_TANDA) {
      const tanda = snap.docs.slice(i, i + TARJETAS_POR_TANDA);
      const usuarios = await db.getAll(...tanda.map((d) => db.collection('users').doc(d.id)));
      tanda.forEach((doc, j) => {
        r.tarjetas++;
        const { accion } = decidir(usuarios[j].exists ? usuarios[j].data() : null, doc.data());
        if (accion === 'sin-decidir') r.sinDecidir.push(`trainerPublicProfiles/${doc.id}: users/.avatarUrl no es un string`);
        else r[CONTADOR[accion]]++;
        if (accion.startsWith('copiar') || (accion === 'foto-quitada' && opts.limpiar)) r.aEscribir.push({ uid: doc.id, accion });
      });
    }
    if (snap.size < pagina) break;
    cursor = snap.docs[snap.docs.length - 1];
  }

  // El plan se imprime ANTES de escribir: si la corrida se corta, queda a la vista qué se tocaba.
  for (const { uid, accion } of r.aEscribir) out.log(`  ${opts.write ? 'escribir' : 'escribiría'} trainerPublicProfiles/${uid}.avatarUrl  (${accion})`);
  for (const { uid, accion } of opts.write ? r.aEscribir : []) {
    if (await escribir(db, uid, accion)) r.escritas++;
    else r.cambiaron++;
  }

  out.log(`\n──── ${opts.write ? 'SUMMARY' : 'DRY-RUN SUMMARY'} ────`);
  for (const [k, texto] of Object.entries(FILAS)) {
    if (k !== 'escritas' || opts.write) out.log(`${String(r[k].length ?? r[k]).padStart(8)}  ${texto}`);
  }
  if (r.fotoQuitada && !opts.limpiar) out.warn(`ℹ ${r.fotoQuitada} fotos quitadas NO se tocan. Para ponerlas en null: --limpiar-fotos-quitadas`);
  if (r.cambiaron) out.warn(`⚠ ${r.cambiaron} tarjetas cambiaron durante la corrida y NO se escribieron; volvé a correr.`);
  for (const s of r.sinDecidir) out.warn(`  sin decidir: ${s}`);
  out.log(opts.write ? '\nListo. Idempotente: se puede repetir.' : '\nDry run completo. Nada se escribió. Para escribir: --apply');
  return r;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv);
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
    return undefined;
  }
  if (opts.project && !process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('--project sólo existe contra el emulador: contra un proyecto real sale de la credencial.');
    process.exitCode = 1;
    return undefined;
  }

  // El cartel ANTES de inicializar (AGENTS.md §11.1): `treino-dev` es producción.
  const banner = bannerDeProduccion(projectIdObjetivo(), { contraEmulador: contraEmuladorDe(['firestore']) });
  if (banner) console.warn(banner);

  const { app, contexto } = inicializarAdmin(opts.project ? { projectId: opts.project } : {});
  console.log(`Target Firebase project: ${opts.project || proyectoDe(contexto)}`);
  console.log(opts.write ? '--apply: ESCRIBE en Firestore.' : 'Modo DRY-RUN (default): no se escribe nada. Usá --apply.');

  return run(getFirestore(app), opts).catch((err) => {
    console.error('FAILED:', err);
    process.exitCode = 1;
  });
}

module.exports = { parseArgs, decidir, run };

if (require.main === module) main();
