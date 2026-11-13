'use strict';

/**
 * backfill_cancel_appointments_unlinked.js
 *
 * Cancela (`appointments/{id}.status = 'cancelled'`) los turnos FUTUROS `confirmed` / `requested` de
 * los pares PF-alumno cuyo vínculo terminó ANTES de la CF `cancelAppointmentsOnUnlink` (#1833, sigue
 * a #1792), que desde ahí los cancela sola. Esos turnos siguen ocupando horario: el cliente del PF cancela
 * ANTES de terminar (#1809), pero el vínculo que termina el ALUMNO no tiene quién lo haga (el Path 1 le
 * exige > 24 h, así que los de las próximas 24 h quedaban `confirmed`).
 * Cancela, NO borra, y escribe lo mismo que la CF (`status`, `reason: 'link-terminated'`, `cancelledAt`,
 * `cancelledBy`, `cancellationLog`): `reason` es la señal que hace callar a `notify-appointment`.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN (AGENTS.md § Entornos). `--apply` cancela turnos de usuarios reales:
 *     dry-run primero, siempre, y leé los conteos antes de escribir.
 * ⚠️  ORDEN: functions -> este script. Antes tiene que estar desplegado el guard `link-terminated` de
 *     `notify-appointment`: sin él, cada turno cancelado dispara su push y su mail (una serie son ~36).
 * Por par (trainerId, athleteId), con todos sus `trainer_links`:
 *   · con un link vivo (active | paused) -> no se toca (la CF tampoco: `live-link`).
 *   · algún link terminado por borrado de cuenta (`reason` = account-deleted | trainer-account-deleted)
 *     -> no se toca: lo cubren las cascadas de borrado de cuenta, no esta CF.
 *   · sin ningún link que haya sido real -> no se toca. `terminated` no distingue un rechazo de un fin
 *     de vínculo; lo decide `clasificar` de `cleanup_rejected_links.js` (acceptedAt != null = fue real;
 *     la CF tampoco actúa en `pending -> terminated`). Los AMBIGUOS (terminated sin acceptedAt ni razón
 *     de rechazo) se listan sin tocar. Un par sin ningún `trainer_links` no tiene evidencia: tampoco.
 *   · si no, cancela los turnos abiertos del par que todavía no empezaron. «Por venir» se mide en el
 *     marco de `startsAt` —hora de pared argentina etiquetada UTC (ADR-7), o sea el instante real MENOS
 *     3 h—, igual que la CF: contra `Date.now()` los turnos de las próximas ~3 h figurarían ya pasados.
 *   · `cancelledBy` y el texto del rastro salen del `terminationReason` del último vínculo real que
 *     terminó (el PF, o el alumno; sin motivo conocido, el alumno con texto neutro), como en la CF.
 * La cancelación re-evalúa el par y cada turno adentro de una transacción: un re-vínculo entre la
 * lectura y la escritura no pierde turnos, y uno ya cancelado (el PF desde el cliente, #1809) no se
 * toca ni se duplica. Idempotente: la segunda corrida no encuentra nada.
 * USO (credencial: `export TREINO_SA_KEY=~/.config/treino/sa-key.json`, scripts/README.md #834)
 *   node scripts/backfill_cancel_appointments_unlinked.js            # DRY-RUN (default)
 *   node scripts/backfill_cancel_appointments_unlinked.js --apply    # escribe (`--apply --dry-run` NO)
 *   # Emulador, sin clave. `--project` sólo existe contra el emulador (namespace local):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_cancel_appointments_unlinked.js --project=demo-treino
 */

const { FieldPath, FieldValue, getFirestore } = require('firebase-admin/firestore');
const { clasificar } = require('./cleanup_rejected_links');
const { inicializarAdmin, proyectoDe } = require('./lib/admin'); // la única puerta (#834)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');

/** Espeja `LIVE_LINK_STATUSES` de `functions/src/chat/sync-chat-on-trainer-link.ts`. */
const VIVOS = new Set(['active', 'paused']);
/** Los estados de un turno que todavía ocupan horario. Espeja `OPEN_STATUSES` de la CF. */
const ABIERTOS = ['confirmed', 'requested'];
/** Copia de `LINK_TERMINATED_REASON` (`functions/src/cancel-appointments-on-unlink.ts`): JS plano no importa el TS. */
const LINK_TERMINADO = 'link-terminated';
/**
 * Copia de las razones con las que las cascadas de borrado de cuenta terminan un vínculo
 * ('account-deleted' de `cascade/trainer-links.ts`, `TRAINER_ACCOUNT_DELETED_REASON` de
 * `cascade/trainer-data.ts`). `scripts/test/backfill_cancel_appointments_unlinked.test.js` las
 * compara con el TS para que una copia no se desfase en silencio.
 */
const CUENTA_BORRADA = new Set(['account-deleted', 'trainer-account-deleted']);
/** UTC-3 fijo, sin horario de verano desde 2009. Espeja `ART_OFFSET_MS` de `functions/src/notifications/weekly-streak.ts`. */
const ART_OFFSET_MS = 3 * 60 * 60 * 1000;
const PAGE_SIZE = 500;
const PARES_POR_TANDA = 25; // pares cuyos turnos se leen en paralelo
const TURNOS_POR_TRANSACCION = 400; // el tope de Firestore es 500 escrituras

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
const esTs = (v) => Boolean(v) && typeof v.seconds === 'number' && typeof v.nanoseconds === 'number';
const cmp = (a, b) => a.seconds - b.seconds || a.nanoseconds - b.nanoseconds;
/** Clave de un par. JSON y no `${t}_${a}`: `a_b` + `c` no tiene que chocar con `a` + `b_c`. */
const parId = (trainerId, athleteId) => JSON.stringify([trainerId, athleteId]);

/** El vínculo real que cerró el par: el de `terminatedAt` más tardía (los que no la tienen, al final). Puro. */
function ultimoReal(reales) {
  const ts = (l) => (esTs(l.terminatedAt) ? l.terminatedAt : null);
  return reales.reduce((mejor, l) => {
    if (!mejor || (!ts(mejor) && ts(l))) return l;
    return ts(l) && cmp(ts(l), ts(mejor)) > 0 ? l : mejor;
  }, null);
}

/**
 * Qué son los links de un par: 'vivo' | 'cuenta-borrada' | 'nunca-fue' | 'sin-decidir' | 'candidato'
 * (+ `cierre`: el vínculo real que terminó último). Puro.
 */
function evaluarVinculos(links) {
  if (links.some((l) => VIVOS.has(l.status))) return { tipo: 'vivo' };
  if (links.some((l) => CUENTA_BORRADA.has(l.reason))) return { tipo: 'cuenta-borrada' };
  const g = { conserva: [], borra: [], ambiguo: [] };
  for (const l of links) if (l.status === 'terminated') g[clasificar(l)].push(l);

  if (g.conserva.length) return { tipo: 'candidato', cierre: ultimoReal(g.conserva) };
  if (g.ambiguo.length) return { tipo: 'sin-decidir', motivo: 'terminated sin acceptedAt ni razón de rechazo' };
  return { tipo: 'nunca-fue' };
}

/** Quién cortó el vínculo y qué texto queda en el rastro. Espeja `terminatedBy` de la CF. Puro. */
function terminadoPor(link, trainerId, athleteId) {
  const r = link.terminationReason;
  if (r === 'trainer-terminated') return { byUid: trainerId, motivo: 'Vínculo terminado por el entrenador.' };
  const alumno = r === 'athlete-terminated' || r === 'switched_trainer';
  return { byUid: athleteId, motivo: alumno ? 'Vínculo terminado por el alumno.' : 'Vínculo terminado.' };
}

/** ¿Es `data` (`data()` o null) un turno abierto de ESTE par? Puro. */
function turnoAbierto(data, par) {
  return Boolean(data) && ABIERTOS.includes(data.status) && data.trainerId === par.trainerId && data.athleteId === par.athleteId;
}

/** Todos los `trainer_links`, paginados por id de documento, agrupados por par. */
async function leerPares(db, r, pagina) {
  const pares = new Map(); // parId -> { trainerId, athleteId, links }
  let cursor = null;
  for (;;) {
    let q = db.collection('trainer_links').orderBy(FieldPath.documentId()).limit(pagina);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if (!esTexto(d.trainerId) || !esTexto(d.athleteId)) {
        r.sinDecidir.push(`trainer_links/${doc.id}: sin trainerId/athleteId`);
        continue;
      }
      const id = parId(d.trainerId, d.athleteId);
      if (!pares.has(id)) pares.set(id, { trainerId: d.trainerId, athleteId: d.athleteId, links: [] });
      pares.get(id).links.push(d);
    }
    if (snap.size < pagina) return pares;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

/** Los ids de los turnos abiertos del par que todavía no empezaron. Igualdad pura: sin índice compuesto. */
async function turnosPorVenir(db, par, wallAhoraMs) {
  const delPar = db.collection('appointments').where('trainerId', '==', par.trainerId).where('athleteId', '==', par.athleteId);
  const snaps = await Promise.all(ABIERTOS.map((s) => delPar.where('status', '==', s).get()));
  return snaps
    .flatMap((s) => s.docs)
    .filter((d) => {
      const startsAt = d.data().startsAt;
      return typeof startsAt?.toMillis === 'function' && startsAt.toMillis() > wallAhoraMs;
    })
    .map((d) => d.id);
}

/**
 * Cancela los turnos de `ids` si, adentro de la transacción, el par sigue sin vínculo vivo.
 * Devuelve { cancelados, cambiaron }.
 */
function cancelar(db, par, ids, ahoraMs) {
  const links = db.collection('trainer_links').where('trainerId', '==', par.trainerId).where('athleteId', '==', par.athleteId);
  const refs = ids.map((id) => db.collection('appointments').doc(id));
  return db.runTransaction(async (tx) => {
    // Todas las lecturas antes de la primera escritura.
    const v = evaluarVinculos((await tx.get(links)).docs.map((d) => d.data()));
    const snaps = await tx.getAll(...refs);
    if (v.tipo !== 'candidato') return { cancelados: 0, cambiaron: ids.length };

    const { byUid, motivo } = terminadoPor(v.cierre, par.trainerId, par.athleteId);
    let cancelados = 0;
    snaps.forEach((snap, i) => {
      // Ya cancelado (el PF desde el cliente, #1809) o borrado: no se toca.
      if (!snap.exists || !turnoAbierto(snap.data(), par)) return;
      tx.update(refs[i], {
        status: 'cancelled',
        reason: LINK_TERMINADO, // la SEÑAL que lee `notify-appointment`
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: byUid,
        cancellationLog: FieldValue.arrayUnion({ byUid, atMs: ahoraMs, reason: motivo }), // un instante REAL, como `cancel()` del cliente
      });
      cancelados++;
    });
    return { cancelados, cambiaron: ids.length - cancelados };
  });
}

const FILAS = {
  pares: 'pares escaneados (por sus trainer_links)', vivos: 'con vínculo vivo (active/paused): intactos',
  cuentaBorrada: 'con un vínculo terminado por borrado de cuenta: intactos, los cubren las cascadas',
  nuncaFueron: 'sin ningún vínculo real (sólo solicitudes/rechazos): intactos',
  terminados: 'con el vínculo terminado', sinTurnos: 'terminados sin turnos futuros abiertos',
  paresConTurnos: 'terminados con turnos futuros abiertos', aCancelar: 'turnos a cancelar',
  cancelados: 'turnos CANCELADOS', sinDecidir: 'sin decidir (revisar a mano, NO se tocan)',
};
const IDS_A_MOSTRAR = 5;

/** `db`: Firestore; `opts`: { write, ahora?, pagina?, porTransaccion? }; `out`: { log, warn }. Devuelve los conteos. */
async function run(db, opts, out = console) {
  const r = { pares: 0, vivos: 0, cuentaBorrada: 0, nuncaFueron: 0, terminados: 0, sinTurnos: 0, paresConTurnos: 0,
    sinDecidir: [], aCancelar: [], cancelados: 0, cambiaron: 0 };
  const ahoraMs = (opts.ahora || new Date()).getTime();
  const wallAhoraMs = ahoraMs - ART_OFFSET_MS; // «ahora» en el marco de `startsAt`
  const porTransaccion = opts.porTransaccion || TURNOS_POR_TRANSACCION;

  const pares = await leerPares(db, r, opts.pagina || PAGE_SIZE);
  r.pares = pares.size;

  const candidatos = [];
  for (const [id, par] of pares) {
    const v = evaluarVinculos(par.links);
    if (v.tipo === 'candidato') candidatos.push({ id, par, cierre: v.cierre });
    else if (v.tipo === 'sin-decidir') r.sinDecidir.push(`${par.trainerId} -> ${par.athleteId}: ${v.motivo}`);
    else r[{ vivo: 'vivos', 'cuenta-borrada': 'cuentaBorrada', 'nunca-fue': 'nuncaFueron' }[v.tipo]]++;
  }
  r.terminados = candidatos.length;

  for (let i = 0; i < candidatos.length; i += PARES_POR_TANDA) {
    const tanda = candidatos.slice(i, i + PARES_POR_TANDA);
    const ids = await Promise.all(tanda.map((c) => turnosPorVenir(db, c.par, wallAhoraMs)));
    tanda.forEach((c, j) => {
      if (ids[j].length === 0) r.sinTurnos++;
      else r.aCancelar.push({ par: c.par, cierre: c.cierre, ids: ids[j] });
    });
  }
  r.paresConTurnos = r.aCancelar.length;

  // El plan se imprime ANTES de escribir: si la corrida se corta, queda a la vista qué se tocaba.
  for (const { par, cierre, ids } of r.aCancelar) {
    const quien = terminadoPor(cierre, par.trainerId, par.athleteId).motivo;
    const lista = ids.slice(0, IDS_A_MOSTRAR).join(', ') + (ids.length > IDS_A_MOSTRAR ? `, … (+${ids.length - IDS_A_MOSTRAR})` : '');
    out.log(`  ${opts.write ? 'cancelar' : 'cancelaría'} ${ids.length} turno(s)  ${par.trainerId} -> ${par.athleteId}  (${quien})  [${lista}]`);
  }
  for (const { par, ids } of opts.write ? r.aCancelar : []) {
    for (let i = 0; i < ids.length; i += porTransaccion) {
      const res = await cancelar(db, par, ids.slice(i, i + porTransaccion), ahoraMs);
      r.cancelados += res.cancelados;
      r.cambiaron += res.cambiaron;
    }
  }

  out.log(`\n──── ${opts.write ? 'SUMMARY' : 'DRY-RUN SUMMARY'} ────`);
  for (const [k, texto] of Object.entries(FILAS)) {
    if (k === 'cancelados' && !opts.write) continue;
    const n = k === 'aCancelar' ? r.aCancelar.reduce((s, { ids }) => s + ids.length, 0) : r[k].length ?? r[k];
    out.log(`${String(n).padStart(8)}  ${texto}`);
  }
  if (r.cambiaron) out.warn(`⚠ ${r.cambiaron} turnos cambiaron durante la corrida y NO se cancelaron; volvé a correr.`);
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

module.exports = { parseArgs, evaluarVinculos, terminadoPor, turnoAbierto, run, ART_OFFSET_MS, LINK_TERMINADO, CUENTA_BORRADA };

if (require.main === module) main();
