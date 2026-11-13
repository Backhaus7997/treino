/**
 * test/backfill_archive_orphan_assigned_routines.test.js
 *
 * `scripts/backfill_archive_orphan_assigned_routines.js` (#1723). Dos capas:
 *   - Firestore en memoria (`fakeDb`): corre siempre, también en CI (sin emulador).
 *   - emulador: se SALTEA sin `FIRESTORE_EMULATOR_HOST`. Para correrla:
 *       firebase emulators:exec --only firestore --project demo-treino \
 *         "node --test scripts/test/backfill_archive_orphan_assigned_routines.test.js"
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { Timestamp } = require('firebase-admin/firestore');

const { parseArgs, run } = require('../backfill_archive_orphan_assigned_routines');

const T = (s) => Timestamp.fromMillis(1_700_000_000_000 + s * 1000);
const silencio = { log() {}, warn() {} };

/** Firestore en memoria con lo justo que usa el script. `escrituras` = paths escritos, `transacciones` = cuántas. */
function fakeDb(semilla) {
  const store = new Map(Object.entries(semilla));
  const escrituras = [];
  const stats = { transacciones: 0 };
  const snap = (p) => ({ id: p.split('/').pop(), exists: store.has(p), data: () => store.get(p) });
  const consulta = (col, filtros = [], desde = null, tope = Infinity) => ({
    where: (campo, _op, valor) => consulta(col, [...filtros, [campo, valor]], desde, tope),
    orderBy: () => consulta(col, filtros, desde, tope),
    limit: (n) => consulta(col, filtros, desde, n),
    startAfter: (s) => consulta(col, filtros, s.id, tope),
    get: async () => {
      const docs = [...store.keys()].sort()
        .filter((p) => p.startsWith(`${col}/`) && filtros.every(([c, v]) => store.get(p)[c] === v))
        .filter((p) => !desde || p.slice(col.length + 1) > desde)
        .slice(0, tope).map(snap);
      return { docs, size: docs.length, empty: docs.length === 0 };
    },
  });
  return {
    store, escrituras, stats,
    collection: (col) => ({ ...consulta(col), doc: (id) => ({ path: `${col}/${id}` }) }),
    runTransaction: async (fn) => {
      stats.transacciones++;
      return fn({
        get: async (x) => (x.path ? snap(x.path) : x.get()),
        getAll: async (...refs) => refs.map((r) => snap(r.path)),
        update: (ref, data) => {
          escrituras.push(ref.path);
          store.set(ref.path, { ...store.get(ref.path), ...data });
        },
      });
    },
  };
}

const plan = (t, a, extra) => ({ source: 'trainer-assigned', assignedBy: t, assignedTo: a, name: 'Plan', status: 'active', ...extra });
const vinculo = (t, a, status, extra) => ({ trainerId: t, athleteId: a, status, ...extra });

/** Un par por caso. Los huérfanos (SE ARCHIVAN) son p1, p5, p6, p7, p8 y p14. r11 / r12 no entran ni a la query. */
function escenario() {
  const { status, ...sinStatus } = plan('t1', 'a1'); // sin `status`: cuenta como activo
  return {
    'trainer_links/l1': vinculo('t1', 'a1', 'terminated', { acceptedAt: T(0), terminationReason: 'athlete-terminated' }), // p1: terminó
    'routines/r1a': plan('t1', 'a1'), 'routines/r1b': sinStatus, 'routines/r1c': plan('t1', 'a1', { status: 'archived' }),
    'trainer_links/l2': vinculo('t2', 'a2', 'active', { acceptedAt: T(0) }), 'routines/r2': plan('t2', 'a2'), // p2: vivo
    'trainer_links/l3': vinculo('t3', 'a3', 'paused', { acceptedAt: T(0) }), 'routines/r3': plan('t3', 'a3'), // p3: pausado
    'trainer_links/l4': vinculo('t4', 'a4', 'terminated', { acceptedAt: T(0), reason: 'trainer-account-deleted' }), // p4: #1333
    'routines/r4': plan('t4', 'a4'),
    'routines/r5': plan('t5', 'a5'), // p5: ni un vínculo
    'trainer_links/l6': vinculo('t6', 'a6', 'pending'), 'routines/r6': plan('t6', 'a6'), // p6: sólo una solicitud
    'trainer_links/l7': vinculo('t7', 'a7', 'terminated', { acceptedAt: null, terminationReason: 'declined' }), // p7: sólo un rechazo
    'routines/r7': plan('t7', 'a7'),
    'trainer_links/l8': vinculo('t8', 'a8b', 'active', { acceptedAt: T(0) }), 'routines/r8': plan('t8', 'a8'), // p8: vivo, pero con OTRO alumno
    'routines/r9': plan('t9', 't9'), // un PF que se asigna un plan a sí mismo
    'routines/r10': { source: 'trainer-assigned', assignedBy: 't10', status: 'active' }, // sin assignedTo
    'routines/r11': { source: 'trainer-template', assignedBy: 't5', assignedTo: null, status: 'active' },
    'routines/r12': { source: 'user-created', createdBy: 'a5', status: 'active' },
    'trainer_links/l13': vinculo('t13', 'a13', 'terminated', { acceptedAt: T(0) }), // p13: terminó y se RE-VINCULÓ
    'trainer_links/l13b': vinculo('t13', 'a13', 'active', { acceptedAt: T(20) }), 'routines/r13': plan('t13', 'a13'),
    'trainer_links/l14': vinculo('t14', 'a14', 'terminated', { acceptedAt: T(0), reason: 'account-deleted' }), // p14: lo borró el ALUMNO
    'routines/r14': plan('t14', 'a14'),
    'trainer_links/l15': { status: 'active' }, // sin trainerId/athleteId: no entra a ningún par
  };
}

const ARCHIVADOS = ['r1a', 'r1b', 'r5', 'r6', 'r7', 'r8', 'r14'].map((id) => `routines/${id}`).sort();
const INTACTOS = ['r1c', 'r2', 'r3', 'r4', 'r9', 'r10', 'r11', 'r12', 'r13'];
const estado = (db, id) => db.store.get(`routines/${id}`).status;

// ── Decisión pura ───────────────────────────────────────────────────────────

test('parseArgs — dry-run por default; --apply escribe; --apply --dry-run NO; flag ajena aborta', () => {
  assert.strictEqual(parseArgs(['node', 'x']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--apply']).write, true);
  assert.strictEqual(parseArgs(['node', 'x', '--apply', '--dry-run']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--dry-run', '--apply']).write, false);
  assert.throws(() => parseArgs(['node', 'x', '--write']), /Flag desconocida/);
});

// ── run: el comportamiento completo ─────────────────────────────────────────

test('run — dry-run: cuenta todo y NO escribe una sola vez', async () => {
  const db = fakeDb(escenario());
  const antes = JSON.stringify([...db.store]);
  const r = await run(db, { write: false }, silencio);

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(db.stats.transacciones, 0);
  assert.strictEqual(JSON.stringify([...db.store]), antes);
  assert.deepStrictEqual([r.planes, r.yaArchivados, r.autoasignados, r.sinDecidir.length, r.pares, r.linksSinPar], [14, 1, 1, 1, 10, 1]);
  assert.deepStrictEqual([r.vivos, r.cuentaBorrada], [3, 1]);
  assert.deepStrictEqual(
    [r.huerfanosTerminado, r.huerfanosSolicitudes, r.huerfanosSinVinculo, r.aArchivar.length, r.archivados],
    [2, 2, 2, 6, 0],
  );
});

test('run --apply — archiva SOLO los planes huérfanos; no borra ni toca nada más; y es idempotente', async () => {
  const db = fakeDb(escenario());
  const antes = new Map(db.store);
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual([...db.escrituras].sort(), ARCHIVADOS);
  assert.deepStrictEqual([r.archivados, r.cambiaron], [7, 0]);
  // Archivar es `status` y nada más: el doc se conserva entero (las sesiones apuntan a él).
  for (const p of ARCHIVADOS) assert.deepStrictEqual(db.store.get(p), { ...antes.get(p), status: 'archived' }, p);
  for (const id of INTACTOS) assert.deepStrictEqual(db.store.get(`routines/${id}`), antes.get(`routines/${id}`), id);
  assert.deepStrictEqual([...db.store.keys()].sort(), [...antes.keys()].sort(), 'no crea ni borra docs');

  const r2 = await run(db, { write: true }, silencio);
  assert.deepStrictEqual([...db.escrituras].sort(), ARCHIVADOS, 'la segunda corrida no escribe');
  assert.deepStrictEqual([r2.aArchivar.length, r2.archivados, r2.yaArchivados], [0, 0, 8]);
});

test('run --apply — lo que cambia entre la lectura y la escritura se respeta (re-vínculo, plan archivado o reasignado)', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('trainer_links/nuevo', vinculo('t1', 'a1', 'active')); // el PF y a1 se re-vinculan
    db.store.set('routines/r5', { ...db.store.get('routines/r5'), status: 'archived' }); // lo archivó el PF a mano
    db.store.set('routines/r6', { ...db.store.get('routines/r6'), assignedTo: 'otro-alumno' }); // lo reasignaron
    return tx(fn);
  };
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual([...db.escrituras].sort(), ['routines/r14', 'routines/r7', 'routines/r8']);
  assert.deepStrictEqual([estado(db, 'r1a'), estado(db, 'r1b'), db.store.get('routines/r6').assignedTo], ['active', undefined, 'otro-alumno']);
  assert.deepStrictEqual([r.archivados, r.cambiaron], [3, 4]);
});

test('run --apply — un par con más planes que el tope de la transacción se archiva en varias', async () => {
  const db = fakeDb(Object.fromEntries([0, 1, 2, 3, 4].map((i) => [`routines/p${i}`, plan('t', 'a')])));
  const r = await run(db, { write: true, porTransaccion: 2 }, silencio);

  assert.deepStrictEqual([db.stats.transacciones, r.archivados], [3, 5]); // 2 + 2 + 1
});

test('run — un uid con "_" no choca con otro par: a_b + c  vs  a + b_c', async () => {
  const db = fakeDb({ 'trainer_links/l1': vinculo('a_b', 'c', 'active'), 'routines/x1': plan('a_b', 'c'), 'routines/x2': plan('a', 'b_c') });
  await run(db, { write: true }, silencio);

  assert.deepStrictEqual([estado(db, 'x1'), estado(db, 'x2')], ['active', 'archived']);
});

test('run — paginar de a 2 da el mismo resultado que de a 500', async () => {
  const grande = await run(fakeDb(escenario()), { write: false }, silencio);
  assert.deepStrictEqual(await run(fakeDb(escenario()), { write: false, pagina: 2 }, silencio), grande);
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const PROJECT = 'demo-archive-orphans'; // namespace propio del emulador
const SCRIPT = path.join(__dirname, '..', 'backfill_archive_orphan_assigned_routines.js');
const skip = process.env.FIRESTORE_EMULATOR_HOST ? false : 'sin FIRESTORE_EMULATOR_HOST';

test('emulador — CLI: sin --apply no escribe; --apply archiva; la segunda corrida no hace nada', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }));
  const cli = (...flags) => {
    const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`, ...flags], { encoding: 'utf8' });
    assert.strictEqual(res.status, 0, res.stderr + res.stdout);
    return res.stdout;
  };
  const status = async (id) => (await db.doc(`routines/${id}`).get()).data().status;

  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data); // set: re-siembra limpio
  assert.match(cli(), /DRY-RUN SUMMARY/);
  assert.strictEqual(await status('r1a'), 'active');
  assert.match(cli('--apply'), /7\s+planes ARCHIVADOS/);
  for (const p of ARCHIVADOS) assert.strictEqual(await status(p.split('/')[1]), 'archived', p);
  for (const id of ['r2', 'r3', 'r4', 'r9', 'r10', 'r13']) assert.strictEqual(await status(id), 'active', id);
  assert.match(cli('--apply'), /0\s+planes ARCHIVADOS/);
  assert.strictEqual((await db.doc('routines/r1a').get()).data().name, 'Plan'); // archivar no borra
});

test('emulador — run con el Firestore REAL: paginar de a 2 = de a 500, y la query/transacción corren', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }, 'paginado'));
  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data);

  const grande = await run(db, { write: false }, silencio);
  assert.deepStrictEqual(await run(db, { write: false, pagina: 2 }, silencio), grande);
  assert.deepStrictEqual([grande.planes, grande.pares, grande.aArchivar.length], [14, 10, 6]);
  assert.strictEqual((await run(db, { write: true, pagina: 2, porTransaccion: 1 }, silencio)).archivados, 7);
  assert.strictEqual((await db.doc('routines/r1b').get()).data().status, 'archived');
});
