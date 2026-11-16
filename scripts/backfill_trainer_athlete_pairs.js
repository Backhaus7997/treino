'use strict';

/**
 * backfill_trainer_athlete_pairs.js
 *
 * Escribe `trainer_athlete_pairs/{trainerId}_{athleteId}` para los pares PF-alumno
 * que ya tenían vínculo ANTES de la CF `syncTrainerAthletePair` (#1806). La CF sólo
 * escribe ante un create, un delete o un cambio de status; un par vivo que no se
 * mueve nunca tendría doc, y con el gate de las reglas prendido su PF no podría
 * cargarle un pago.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN (AGENTS.md § Entornos). Dry-run primero, siempre.
 * Por par (trainerId, athleteId), con todos sus `trainer_links`, lo MISMO que la CF:
 *   · status = el mejor entre sus vínculos: active > paused > pending > terminated
 *     (un status desconocido no suma; sin ninguno conocido, `terminated`).
 *   · live   = status in [active, paused].
 *   · doc ausente o distinto -> se escribe `{trainerId, athleteId, live, status, updatedAt}`.
 *   · doc igual -> no se toca (idempotente).
 * No borra nada: un par sin vínculos no aparece en el escaneo, y si tiene doc es de la CF.
 * Cada escritura re-evalúa el par adentro de una transacción: un cambio de status entre
 * la lectura y la escritura gana, igual que si la hubiera escrito la CF.
 * ORDEN: functions -> este script -> `app_config/trainer_pairs_gate.enabled` -> reglas.
 * USO (credencial: `export TREINO_SA_KEY=~/.config/treino/sa-key.json`, scripts/README.md #834)
 *   node scripts/backfill_trainer_athlete_pairs.js            # DRY-RUN (default)
 *   node scripts/backfill_trainer_athlete_pairs.js --apply    # escribe (`--apply --dry-run` NO)
 *   # Emulador, sin clave. `--project` sólo existe contra el emulador (namespace local):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_trainer_athlete_pairs.js --project=demo-treino
 */

const { FieldPath, FieldValue, getFirestore } = require('firebase-admin/firestore');
const { inicializarAdmin, proyectoDe } = require('./lib/admin'); // la única puerta (#834)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');

const COLECCION = 'trainer_athlete_pairs';
// Espeja `PAIR_STATUS_ORDER` / `LIVE_PAIR_STATUSES` de functions/src/sync-trainer-athlete-pair.ts.
const ORDEN = ['active', 'paused', 'pending', 'terminated'];
const VIVOS = new Set(['active', 'paused']);
const PAGE_SIZE = 500;
const PARES_POR_TANDA = 300;

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

/** El doc que le corresponde a un par según los status de sus vínculos. Puro. */
function parEsperado(trainerId, athleteId, statuses) {
  const status = ORDEN.find((s) => statuses.includes(s)) || 'terminated';
  return { trainerId, athleteId, live: VIVOS.has(status), status };
}

/** ¿El doc guardado ya dice lo mismo? Puro. `doc` es `data()` o null. */
function alDia(esperado, doc) {
  return Boolean(doc) && ['trainerId', 'athleteId', 'live', 'status'].every((k) => doc[k] === esperado[k]);
}

/** Todos los `trainer_links`, paginados por id de documento, agrupados por par. */
async function leerPares(db, r, pagina) {
  const pares = new Map(); // pairId -> { trainerId, athleteId, statuses }
  let cursor = null;
  for (;;) {
    let q = db.collection('trainer_links').orderBy(FieldPath.documentId()).limit(pagina);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if (typeof d.trainerId !== 'string' || !d.trainerId || typeof d.athleteId !== 'string' || !d.athleteId) {
        r.sinDecidir.push(`trainer_links/${doc.id}: sin trainerId/athleteId`);
        continue;
      }
      const id = `${d.trainerId}_${d.athleteId}`; // PF primero: así lo arma la regla
      if (!pares.has(id)) pares.set(id, { trainerId: d.trainerId, athleteId: d.athleteId, statuses: [] });
      pares.get(id).statuses.push(d.status);
    }
    if (snap.size < pagina) return pares;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

/** Escribe el par releyendo sus vínculos en la transacción. true si escribió. */
function escribir(db, id, par) {
  const ref = db.collection(COLECCION).doc(id);
  const links = db.collection('trainer_links').where('trainerId', '==', par.trainerId).where('athleteId', '==', par.athleteId);
  return db.runTransaction(async (tx) => {
    const [doc, snap] = [await tx.get(ref), await tx.get(links)];
    if (snap.docs.length === 0) return false;
    const esperado = parEsperado(par.trainerId, par.athleteId, snap.docs.map((d) => d.data().status));
    if (alDia(esperado, doc.exists ? doc.data() : null)) return false;
    tx.set(ref, { ...esperado, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
}

const FILAS = {
  pares: 'pares escaneados', vivos: 'vivos (active/paused)', noVivos: 'no vivos (pending/terminated)',
  alDia: 'ya al día: intactos', aEscribir: 'pares a escribir', escritos: 'pares ESCRITOS',
};

/** `db`: Firestore; `opts`: { write, pagina? }; `out`: { log, warn }. Devuelve los conteos. */
async function run(db, opts, out = console) {
  const r = { pares: 0, vivos: 0, noVivos: 0, alDia: 0, aEscribir: [], escritos: 0, cambiaron: 0, sinDecidir: [] };
  const pares = await leerPares(db, r, opts.pagina || PAGE_SIZE);
  r.pares = pares.size;

  const lista = [...pares].map(([id, p]) => ({ id, par: p, esperado: parEsperado(p.trainerId, p.athleteId, p.statuses) }));
  for (const c of lista) r[c.esperado.live ? 'vivos' : 'noVivos']++;
  for (let i = 0; i < lista.length; i += PARES_POR_TANDA) {
    const tanda = lista.slice(i, i + PARES_POR_TANDA);
    const snaps = await db.getAll(...tanda.map((c) => db.collection(COLECCION).doc(c.id)));
    snaps.forEach((snap, j) => {
      if (alDia(tanda[j].esperado, snap.exists ? snap.data() : null)) r.alDia++;
      else r.aEscribir.push(tanda[j]);
    });
  }

  // El plan se imprime ANTES de escribir: si la corrida se corta, queda a la vista qué se tocaba.
  for (const c of r.aEscribir) {
    out.log(`  ${opts.write ? 'escribir' : 'escribiría'} ${COLECCION}/${c.id}  live=${c.esperado.live} status=${c.esperado.status}`);
  }
  for (const c of opts.write ? r.aEscribir : []) {
    if (await escribir(db, c.id, c.par)) r.escritos++;
    else r.cambiaron++;
  }

  out.log(`\n──── ${opts.write ? 'SUMMARY' : 'DRY-RUN SUMMARY'} ────`);
  for (const [k, texto] of Object.entries(FILAS)) {
    if (k !== 'escritos' || opts.write) out.log(`${String(r[k].length ?? r[k]).padStart(8)}  ${texto}`);
  }
  if (r.cambiaron) out.warn(`⚠ ${r.cambiaron} no se escribieron: al releerlos ya estaban al día (la CF llegó antes) o sin vínculos.`);
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

module.exports = { parseArgs, parEsperado, alDia, run };

if (require.main === module) main();
