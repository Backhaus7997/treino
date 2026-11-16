'use strict';

/**
 * backfill_chat_closed_unlinked.js
 *
 * Cierra (`chats/{pairId}.closedAt`) el chat de los pares PF-alumno cuyo vínculo
 * terminó ANTES de la CF `syncChatOnTrainerLink` (#1697), que desde ahí lo cierra sola.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN (AGENTS.md § Entornos). `--apply` corta el chat de
 *     usuarios reales: dry-run primero, siempre.
 * Por par (trainerId, athleteId), con todos sus `trainer_links`:
 *   · con un link vivo (active | paused) -> no se toca.
 *   · sin ningún link que haya sido real -> no se toca. `terminated` no distingue un
 *     rechazo de un fin de vínculo; lo decide `clasificar` de `cleanup_rejected_links.js`:
 *     acceptedAt != null = fue real; acceptedAt null + declined / cancelled-by-athlete /
 *     cuenta borrada = nunca lo fue; el resto es AMBIGUO y se lista sin tocar. (No existe
 *     `startedAt`: el modelo sólo tiene `acceptedAt`.) La CF tampoco cierra `pending -> terminated`.
 *   · corte = la última `terminatedAt` de un link REAL (no la de un rechazo posterior).
 *   · chat inexistente, con `closedAt`, o creado DESPUÉS del corte (social: al terminar no
 *     había chat, y la CF tampoco lo habría cerrado) -> no se toca.
 *   · si no, `closedAt = corte`: cuándo terminó el vínculo, lo que habría estampado la CF.
 * El cierre re-evalúa todo adentro de una transacción: un re-vínculo entre la lectura y la
 * escritura no puede dejar cerrado un chat con vínculo vivo. Idempotente.
 * ORDEN: reglas -> functions -> este script. Las reglas del chat no tienen allowlist de
 * claves: con las viejas desplegadas un miembro podría BORRAR el `closedAt`.
 * USO (credencial: `export TREINO_SA_KEY=~/.config/treino/sa-key.json`, scripts/README.md #834)
 *   node scripts/backfill_chat_closed_unlinked.js            # DRY-RUN (default)
 *   node scripts/backfill_chat_closed_unlinked.js --apply    # escribe (`--apply --dry-run` NO)
 *   # Emulador, sin clave. `--project` sólo existe contra el emulador (namespace local):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_chat_closed_unlinked.js --project=demo-treino
 */

const { FieldPath, getFirestore } = require('firebase-admin/firestore');
const { clasificar } = require('./cleanup_rejected_links');
const { inicializarAdmin, proyectoDe } = require('./lib/admin'); // la única puerta (#834)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');

const VIVOS = new Set(['active', 'paused']);
const PAGE_SIZE = 500;
const CHATS_POR_TANDA = 300;

function parseArgs(argv) {
  const out = { write: false, project: null };
  let dryRun = false;
  for (const arg of argv.slice(2)) {
    if (arg === '--apply') out.write = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg.startsWith('--project=')) out.project = arg.slice('--project='.length) || null;
    else throw new Error(`Flag desconocida: "${arg}"`);
  }
  if (dryRun) out.write = false; // ante flags en conflicto gana la que NO escribe
  return out;
}

const esTs = (v) => Boolean(v) && typeof v.seconds === 'number' && typeof v.nanoseconds === 'number';
const cmp = (a, b) => a.seconds - b.seconds || a.nanoseconds - b.nanoseconds;

/** Qué son los links de un par: 'vivo' | 'pendiente' | 'rechazado' | 'sin-decidir' | 'candidato' (+ corte). Puro. */
function evaluarVinculos(links) {
  if (links.some((l) => VIVOS.has(l.status))) return { tipo: 'vivo' };
  const g = { conserva: [], borra: [], ambiguo: [] };
  for (const l of links) if (l.status === 'terminated') g[clasificar(l)].push(l);

  if (g.conserva.length) {
    const corte = g.conserva.map((l) => l.terminatedAt).filter(esTs).sort(cmp).pop();
    return corte
      ? { tipo: 'candidato', corte }
      : { tipo: 'sin-decidir', motivo: 'vínculo real terminado sin terminatedAt' };
  }
  if (g.ambiguo.length) return { tipo: 'sin-decidir', motivo: 'terminated sin acceptedAt ni razón de rechazo' };
  return { tipo: g.borra.length ? 'rechazado' : 'pendiente' };
}

/** Qué hacer con el chat de un par candidato. Puro. `chat` es `data()` o null. */
function evaluarChat(corte, chat) {
  if (!chat) return 'no-chat';
  if (chat.closedAt != null) return 'ya-cerrado';
  if (!esTs(chat.createdAt)) return 'sin-decidir';
  return cmp(chat.createdAt, corte) <= 0 ? 'cerrar' : 'social';
}

/** Todos los `trainer_links`, paginados por id de documento, agrupados por par. */
async function leerPares(db, r, pagina) {
  const pares = new Map(); // pairId -> { trainerId, athleteId, links }
  let cursor = null;
  for (;;) {
    let q = db.collection('trainer_links').orderBy(FieldPath.documentId()).limit(pagina);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if (typeof d.trainerId !== 'string' || typeof d.athleteId !== 'string') {
        r.sinDecidir.push(`trainer_links/${doc.id}: sin trainerId/athleteId`);
        continue;
      }
      const id = [d.trainerId, d.athleteId].sort().join('_'); // = ChatRepository.chatIdFor
      if (!pares.has(id)) pares.set(id, { trainerId: d.trainerId, athleteId: d.athleteId, links: [] });
      pares.get(id).links.push(d);
    }
    if (snap.size < pagina) return pares;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

/** Cierra el chat si, adentro de la transacción, todo sigue igual. Devuelve el corte o null. */
function cerrar(db, id, par) {
  const chatRef = db.collection('chats').doc(id);
  const links = db.collection('trainer_links').where('trainerId', '==', par.trainerId).where('athleteId', '==', par.athleteId);
  return db.runTransaction(async (tx) => {
    const chat = await tx.get(chatRef);
    const v = evaluarVinculos((await tx.get(links)).docs.map((d) => d.data()));
    if (v.tipo !== 'candidato') return null;
    if (evaluarChat(v.corte, chat.exists ? chat.data() : null) !== 'cerrar') return null;
    tx.update(chatRef, { closedAt: v.corte });
    return v.corte;
  });
}

const FILAS = {
  pares: 'pares escaneados', vivos: 'con vínculo vivo (active/paused): intactos',
  soloPendientes: 'sin terminar (sólo pendientes): intactos',
  rechazados: 'skipped-declined: sólo rechazos/cancelaciones, nunca fueron vínculo',
  noChat: 'no-chat: vínculo terminado pero sin chat', yaCerrados: 'already-closed: el chat ya tenía closedAt',
  social: 'skipped-social: chat creado después del corte', sinDecidir: 'sin decidir (revisar a mano, NO se tocan)',
  aCerrar: 'chats a cerrar', cerrados: 'chats CERRADOS',
};
const CONTADOR = { vivo: 'vivos', pendiente: 'soloPendientes', rechazado: 'rechazados',
  'no-chat': 'noChat', 'ya-cerrado': 'yaCerrados', social: 'social' };

/** `db`: Firestore; `opts`: { write, pagina? }; `out`: { log, warn }. Devuelve los conteos. */
async function run(db, opts, out = console) {
  const r = { pares: 0, vivos: 0, soloPendientes: 0, rechazados: 0, noChat: 0, yaCerrados: 0, social: 0,
    sinDecidir: [], aCerrar: [], cerrados: 0, cambiaron: 0 };
  const pares = await leerPares(db, r, opts.pagina || PAGE_SIZE);
  r.pares = pares.size;

  const candidatos = [];
  for (const [id, par] of pares) {
    const v = evaluarVinculos(par.links);
    if (v.tipo === 'candidato') candidatos.push({ id, par, corte: v.corte });
    else if (v.tipo === 'sin-decidir') r.sinDecidir.push(`chats/${id}: ${v.motivo}`);
    else r[CONTADOR[v.tipo]]++;
  }

  for (let i = 0; i < candidatos.length; i += CHATS_POR_TANDA) {
    const tanda = candidatos.slice(i, i + CHATS_POR_TANDA);
    const snaps = await db.getAll(...tanda.map((c) => db.collection('chats').doc(c.id)));
    snaps.forEach((snap, j) => {
      const v = evaluarChat(tanda[j].corte, snap.exists ? snap.data() : null);
      if (v === 'cerrar') r.aCerrar.push(tanda[j]);
      else if (v === 'sin-decidir') r.sinDecidir.push(`chats/${tanda[j].id}: chat sin createdAt`);
      else r[CONTADOR[v]]++;
    });
  }

  // El plan se imprime ANTES de escribir: si la corrida se corta, queda a la vista qué se tocaba.
  for (const c of r.aCerrar) out.log(`  ${opts.write ? 'cerrar' : 'cerraría'} chats/${c.id}  closedAt=${c.corte.toDate().toISOString()}`);
  for (const c of opts.write ? r.aCerrar : []) {
    if (await cerrar(db, c.id, c.par)) r.cerrados++;
    else r.cambiaron++;
  }

  out.log(`\n──── ${opts.write ? 'SUMMARY' : 'DRY-RUN SUMMARY'} ────`);
  for (const [k, texto] of Object.entries(FILAS)) {
    if (k !== 'cerrados' || opts.write) out.log(`${String(r[k].length ?? r[k]).padStart(8)}  ${texto}`);
  }
  if (r.cambiaron) out.warn(`⚠ ${r.cambiaron} cambiaron durante la corrida y NO se cerraron; volvé a correr.`);
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
  const emulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (opts.project && !emulador) {
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

module.exports = { parseArgs, evaluarVinculos, evaluarChat, run };

if (require.main === module) main();
