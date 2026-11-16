'use strict';

/**
 * backfill_archive_orphan_assigned_routines.js
 *
 * Archiva (`routines/{id}.status = 'archived'`) los planes `trainer-assigned` cuyo par (assignedBy,
 * assignedTo) NO tiene un vínculo vivo: los que un PF asignó a un ex-alumno DESPUÉS de terminar el
 * vínculo, o a un uid que nunca fue su alumno (#1723, ref #1695). El ex-alumno los ve como «DE TU
 * COACH · ACTIVA» y no puede archivarlos ni borrarlos. La CF `archiveOrphanAssignedPlanOnCreate`
 * cierra el hueco de acá en adelante; esto barre lo que ya quedó. Archiva, NO borra: las sesiones
 * ya entrenadas apuntan a esos docs (header de `functions/src/cleanup-assigned-plans.ts`).
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN (AGENTS.md § Entornos). `--apply` esconde planes de usuarios reales:
 *     dry-run primero, siempre, y leé los conteos antes de escribir.
 * Por par, con TODOS sus `trainer_links`: vivo (active | paused) -> intacto; algún link terminado por
 * `reason == 'trainer-account-deleted'` (#1333) -> intacto, el PF borró su cuenta y el plan SE QUEDA con
 * el alumno ("cualquier link" y no "el último", igual que la CF: la cuenta del PF no vuelve);
 * assignedBy == assignedTo -> intacto; assignedBy/assignedTo ausentes -> sin decidir; si no, huérfano
 * y se archiva (`terminado`, `solo-solicitudes` o `sin-vinculo`, para que el dry-run diga por qué).
 * Sólo lee `trainer-assigned` con `status != 'archived'` (sin `status` = activo). El archivado
 * re-evalúa el par y cada plan adentro de una transacción: un re-vínculo entre la lectura y la
 * escritura no archiva un plan legítimo. Idempotente. ORDEN: functions (la CF) -> este script.
 * USO (credencial: `export TREINO_SA_KEY=~/.config/treino/sa-key.json`, scripts/README.md #834)
 *   node scripts/backfill_archive_orphan_assigned_routines.js            # DRY-RUN (default)
 *   node scripts/backfill_archive_orphan_assigned_routines.js --apply    # escribe (`--apply --dry-run` NO)
 *   # Emulador, sin clave. `--project` sólo existe contra el emulador (namespace local):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_archive_orphan_assigned_routines.js --project=demo-treino
 */

const { FieldPath, getFirestore } = require('firebase-admin/firestore');
const { inicializarAdmin, proyectoDe } = require('./lib/admin'); // la única puerta (#834)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');

/** Espeja `LIVE_LINK_STATUSES` de `functions/src/chat/sync-chat-on-trainer-link.ts`. */
const VIVOS = new Set(['active', 'paused']);
/** Copia de `TRAINER_ACCOUNT_DELETED_REASON` (`functions/src/cascade/trainer-data.ts`, #1333): JS plano no importa el TS. */
const CUENTA_DEL_PF_BORRADA = 'trainer-account-deleted';
const PAGE_SIZE = 500;
const PLANES_POR_TRANSACCION = 400; // el tope de Firestore es 500 escrituras

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

const esTexto = (v) => typeof v === 'string' && v !== '';
/** Clave de un par. JSON y no `${t}_${a}`: `a_b` + `c` no tiene que chocar con `a` + `b_c`. */
const parId = (trainerId, athleteId) => JSON.stringify([trainerId, athleteId]);

/** Qué son los links de un par: 'vivo' | 'cuenta-borrada' | 'huerfano' (+ `motivo`). Puro. */
function evaluarVinculos(links) {
  if (links.some((l) => VIVOS.has(l.status))) return { tipo: 'vivo' };
  if (links.some((l) => l.reason === CUENTA_DEL_PF_BORRADA)) return { tipo: 'cuenta-borrada' };
  if (links.length === 0) return { tipo: 'huerfano', motivo: 'sin-vinculo' };
  const hubo = links.some((l) => l.status === 'terminated' && l.acceptedAt != null);
  return { tipo: 'huerfano', motivo: hubo ? 'terminado' : 'solo-solicitudes' };
}

/** ¿Es `data` (`data()` o null) un plan asignado, todavía sin archivar, de ESTE par? Puro. */
function planPendiente(data, par) {
  return Boolean(data) && data.source === 'trainer-assigned' && data.status !== 'archived' &&
    data.assignedBy === par.trainerId && data.assignedTo === par.athleteId;
}

/** Recorre una colección (o query) paginada por id de documento, llamando a `fn(doc)` por cada uno. */
async function paginar(consulta, pagina, fn) {
  const base = consulta.orderBy(FieldPath.documentId()).limit(pagina);
  let cursor = null;
  for (;;) {
    const snap = await (cursor ? base.startAfter(cursor) : base).get();
    snap.docs.forEach(fn);
    if (snap.size < pagina) return;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

/** Archiva los planes de `ids` si, adentro de la transacción, el par sigue huérfano. Devuelve { archivados, cambiaron }. */
function archivar(db, par, ids) {
  const links = db.collection('trainer_links').where('trainerId', '==', par.trainerId).where('athleteId', '==', par.athleteId);
  const refs = ids.map((id) => db.collection('routines').doc(id));
  return db.runTransaction(async (tx) => {
    // Todas las lecturas antes de la primera escritura.
    const v = evaluarVinculos((await tx.get(links)).docs.map((d) => d.data()));
    const snaps = await tx.getAll(...refs);
    if (v.tipo !== 'huerfano') return { archivados: 0, cambiaron: ids.length };
    let archivados = 0;
    snaps.forEach((snap, i) => {
      if (!planPendiente(snap.exists ? snap.data() : null, par)) return;
      tx.update(refs[i], { status: 'archived' });
      archivados++;
    });
    return { archivados, cambiaron: ids.length - archivados };
  });
}

const FILAS = {
  planes: 'planes trainer-assigned escaneados', yaArchivados: 'ya archivados: intactos',
  autoasignados: 'autoasignados (assignedBy == assignedTo): intactos', pares: 'pares con planes sin archivar',
  vivos: 'pares con vínculo vivo (active/paused): intactos',
  cuentaBorrada: 'pares con vínculo trainer-account-deleted (#1333): intactos, el plan se queda',
  huerfanosTerminado: 'pares huérfanos, el vínculo TERMINÓ', huerfanosSolicitudes: 'pares huérfanos, sólo solicitudes (pending/rechazos)',
  huerfanosSinVinculo: 'pares huérfanos, SIN ningún vínculo', aArchivar: 'planes a archivar',
  archivados: 'planes ARCHIVADOS', sinDecidir: 'sin decidir (revisar a mano, NO se tocan)',
};
const CONTADOR = { terminado: 'huerfanosTerminado', 'solo-solicitudes': 'huerfanosSolicitudes', 'sin-vinculo': 'huerfanosSinVinculo' };

/** `db`: Firestore; `opts`: { write, pagina?, porTransaccion? }; `out`: { log, warn }. Devuelve los conteos. */
async function run(db, opts, out = console) {
  const r = { planes: 0, yaArchivados: 0, autoasignados: 0, pares: 0, vivos: 0, cuentaBorrada: 0,
    huerfanosTerminado: 0, huerfanosSolicitudes: 0, huerfanosSinVinculo: 0, linksSinPar: 0,
    sinDecidir: [], aArchivar: [], archivados: 0, cambiaron: 0 };
  const pagina = opts.pagina || PAGE_SIZE;
  const porTransaccion = opts.porTransaccion || PLANES_POR_TRANSACCION;

  const planes = new Map(); // parId -> { trainerId, athleteId, ids }
  await paginar(db.collection('routines').where('source', '==', 'trainer-assigned'), pagina, (doc) => {
    const d = doc.data();
    r.planes++;
    if (d.status === 'archived') r.yaArchivados++;
    else if (!esTexto(d.assignedBy) || !esTexto(d.assignedTo)) r.sinDecidir.push(`routines/${doc.id}: assignedBy/assignedTo ausentes o inválidos`);
    else if (d.assignedBy === d.assignedTo) r.autoasignados++;
    else {
      const id = parId(d.assignedBy, d.assignedTo);
      if (!planes.has(id)) planes.set(id, { trainerId: d.assignedBy, athleteId: d.assignedTo, ids: [] });
      planes.get(id).ids.push(doc.id);
    }
  });
  const vinculos = new Map(); // parId -> links
  await paginar(db.collection('trainer_links'), pagina, (doc) => {
    const d = doc.data();
    if (!esTexto(d.trainerId) || !esTexto(d.athleteId)) return void r.linksSinPar++;
    const id = parId(d.trainerId, d.athleteId);
    vinculos.set(id, [...(vinculos.get(id) || []), d]);
  });
  r.pares = planes.size;

  for (const [id, par] of planes) {
    const v = evaluarVinculos(vinculos.get(id) || []);
    if (v.tipo === 'vivo') r.vivos++;
    else if (v.tipo === 'cuenta-borrada') r.cuentaBorrada++;
    else {
      r[CONTADOR[v.motivo]]++;
      r.aArchivar.push({ par, motivo: v.motivo });
    }
  }

  // El plan se imprime ANTES de escribir: si la corrida se corta, queda a la vista qué se tocaba.
  for (const { par, motivo } of r.aArchivar) {
    for (const id of par.ids) out.log(`  ${opts.write ? 'archivar' : 'archivaría'} routines/${id}  ${par.trainerId} -> ${par.athleteId}  (${motivo})`);
  }
  for (const { par } of opts.write ? r.aArchivar : []) {
    for (let i = 0; i < par.ids.length; i += porTransaccion) {
      const res = await archivar(db, par, par.ids.slice(i, i + porTransaccion));
      r.archivados += res.archivados;
      r.cambiaron += res.cambiaron;
    }
  }

  out.log(`\n──── ${opts.write ? 'SUMMARY' : 'DRY-RUN SUMMARY'} ────`);
  for (const [k, texto] of Object.entries(FILAS)) {
    if (k === 'archivados' && !opts.write) continue;
    const n = k === 'aArchivar' ? r.aArchivar.reduce((s, { par }) => s + par.ids.length, 0) : r[k].length ?? r[k];
    out.log(`${String(n).padStart(8)}  ${texto}`);
  }
  if (r.linksSinPar) out.warn(`ℹ ${r.linksSinPar} trainer_links sin trainerId/athleteId: no entran a ningún par.`);
  if (r.cambiaron) out.warn(`⚠ ${r.cambiaron} planes cambiaron durante la corrida y NO se archivaron; volvé a correr.`);
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

module.exports = { parseArgs, evaluarVinculos, planPendiente, run };

if (require.main === module) main();
