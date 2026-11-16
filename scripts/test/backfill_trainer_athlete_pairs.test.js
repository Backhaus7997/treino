/**
 * test/backfill_trainer_athlete_pairs.test.js
 *
 * `scripts/backfill_trainer_athlete_pairs.js` (#1806). Dos capas:
 *   - Firestore en memoria (`fakeDb`): corre siempre, también en CI (sin emulador).
 *   - emulador: se SALTEA sin `FIRESTORE_EMULATOR_HOST`. Para correrla:
 *       firebase emulators:exec --only firestore --project demo-treino \
 *         "node --test scripts/test/backfill_trainer_athlete_pairs.test.js"
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { parseArgs, parEsperado, alDia, run } = require('../backfill_trainer_athlete_pairs');

const silencio = { log() {}, warn() {} };

/** Firestore en memoria con lo justo que usa el script. `escrituras` = paths escritos. */
function fakeDb(semilla) {
  const store = new Map(Object.entries(semilla));
  const escrituras = [];
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
    store,
    escrituras,
    collection: (col) => ({ ...consulta(col), doc: (id) => ({ path: `${col}/${id}` }) }),
    getAll: async (...refs) => refs.map((r) => snap(r.path)),
    runTransaction: async (fn) =>
      fn({
        get: async (x) => (x.path ? snap(x.path) : x.get()),
        set: (ref, data) => {
          escrituras.push(ref.path);
          store.set(ref.path, data);
        },
      }),
  };
}

const vinculo = (t, a, status) => ({ trainerId: t, athleteId: a, status });
const par = (t, a, live, status) => ({ trainerId: t, athleteId: a, live, status });

/** Un par por caso. El doc del par es `t_a` (PF primero). */
function escenario() {
  return {
    'trainer_links/l1': vinculo('t1', 'a1', 'active'), // vivo sin doc: SE ESCRIBE
    'trainer_links/l2': vinculo('t2', 'a2', 'paused'), // pausado sin doc: SE ESCRIBE, vivo
    'trainer_links/l3a': vinculo('t3', 'a3', 'terminated'), // terminó y se re-vinculó: vivo
    'trainer_links/l3b': vinculo('t3', 'a3', 'active'),
    'trainer_links/l4': vinculo('t4', 'a4', 'terminated'), // ex-alumno sin doc: SE ESCRIBE, no vivo
    'trainer_links/l5': vinculo('t5', 'a5', 'pending'), // solicitud: no vivo
    'trainer_links/l6': vinculo('t6', 'a6', 'active'), 'trainer_athlete_pairs/t6_a6': par('t6', 'a6', true, 'active'),
    'trainer_links/l7': vinculo('t7', 'a7', 'terminated'), // doc desfasado: decía vivo
    'trainer_athlete_pairs/t7_a7': par('t7', 'a7', true, 'active'),
    'trainer_links/l8': { trainerId: 't8', status: 'active' }, // sin athleteId: sin decidir
    'trainer_athlete_pairs/t9_a9': par('t9', 'a9', false, 'terminated'), // sin vínculos: NO se toca
  };
}

// ── Decisión pura ───────────────────────────────────────────────────────────

test('parseArgs — dry-run por default; --apply escribe; --apply --dry-run NO; flag ajena aborta', () => {
  assert.strictEqual(parseArgs(['node', 'x']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--apply']).write, true);
  assert.strictEqual(parseArgs(['node', 'x', '--apply', '--dry-run']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--dry-run', '--apply']).write, false);
  assert.throws(() => parseArgs(['node', 'x', '--write']), /Flag desconocida/);
});

test('parEsperado / alDia — el mismo orden que la CF, y un status raro no prende nada', () => {
  assert.deepStrictEqual(parEsperado('t', 'a', ['terminated', 'paused', 'pending']), par('t', 'a', true, 'paused'));
  assert.deepStrictEqual(parEsperado('t', 'a', ['pending', 'terminated']), par('t', 'a', false, 'pending'));
  assert.deepStrictEqual(parEsperado('t', 'a', ['raro', undefined]), par('t', 'a', false, 'terminated'));
  assert.strictEqual(alDia(par('t', 'a', true, 'active'), null), false);
  assert.strictEqual(alDia(par('t', 'a', true, 'active'), { ...par('t', 'a', true, 'active'), updatedAt: 1 }), true);
  assert.strictEqual(alDia(par('t', 'a', true, 'active'), par('t', 'a', true, 'paused')), false);
});

// ── run: el comportamiento completo ─────────────────────────────────────────

test('run — dry-run: cuenta todo y NO escribe una sola vez', async () => {
  const db = fakeDb(escenario());
  const antes = JSON.stringify([...db.store]);
  const r = await run(db, { write: false }, silencio);

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(JSON.stringify([...db.store]), antes);
  assert.deepStrictEqual([r.pares, r.vivos, r.noVivos, r.alDia, r.aEscribir.length], [7, 4, 3, 1, 6]);
  assert.deepStrictEqual(r.sinDecidir, ['trainer_links/l8: sin trainerId/athleteId']);
});

test('run --apply — escribe SOLO los pares desfasados, con live/status correctos; y es idempotente', async () => {
  const db = fakeDb(escenario());
  const r = await run(db, { write: true }, silencio);

  const escritos = ['t1_a1', 't2_a2', 't3_a3', 't4_a4', 't5_a5', 't7_a7'].map((id) => `trainer_athlete_pairs/${id}`);
  assert.deepStrictEqual([...db.escrituras].sort(), escritos);
  assert.strictEqual(r.escritos, 6);
  const leer = (id) => {
    const { updatedAt, ...resto } = db.store.get(`trainer_athlete_pairs/${id}`);
    assert.ok(updatedAt, `${id} lleva updatedAt`);
    return resto;
  };
  assert.deepStrictEqual(leer('t1_a1'), par('t1', 'a1', true, 'active'));
  assert.deepStrictEqual(leer('t2_a2'), par('t2', 'a2', true, 'paused'));
  assert.deepStrictEqual(leer('t3_a3'), par('t3', 'a3', true, 'active'));
  assert.deepStrictEqual(leer('t4_a4'), par('t4', 'a4', false, 'terminated'));
  assert.deepStrictEqual(leer('t5_a5'), par('t5', 'a5', false, 'pending'));
  assert.deepStrictEqual(leer('t7_a7'), par('t7', 'a7', false, 'terminated'));
  assert.deepStrictEqual(db.store.get('trainer_athlete_pairs/t9_a9'), par('t9', 'a9', false, 'terminated'));
  assert.strictEqual(db.store.has('trainer_athlete_pairs/a1_t1'), false, 'el id NO va ordenado');

  const r2 = await run(db, { write: true }, silencio);
  assert.strictEqual(db.escrituras.length, 6);
  assert.deepStrictEqual([r2.aEscribir.length, r2.escritos, r2.alDia], [0, 0, 7]);
});

test('run --apply — si la CF escribió el par entre la lectura y la escritura, no se pisa', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('trainer_links/l1', vinculo('t1', 'a1', 'terminated')); // terminó en el medio
    db.store.set('trainer_athlete_pairs/t1_a1', par('t1', 'a1', false, 'terminated')); // y la CF lo escribió
    return tx(fn);
  };
  const r = await run(db, { write: true }, silencio);

  assert.ok(!db.escrituras.includes('trainer_athlete_pairs/t1_a1'));
  assert.deepStrictEqual(db.store.get('trainer_athlete_pairs/t1_a1'), par('t1', 'a1', false, 'terminated'));
  assert.deepStrictEqual([r.escritos, r.cambiaron], [5, 1]);
});

test('run — paginar de a 2 da el mismo resultado que de a 500', async () => {
  const grande = await run(fakeDb(escenario()), { write: false }, silencio);
  assert.deepStrictEqual(await run(fakeDb(escenario()), { write: false, pagina: 2 }, silencio), grande);
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const PROJECT = 'demo-trainer-pairs'; // namespace propio del emulador
const SCRIPT = path.join(__dirname, '..', 'backfill_trainer_athlete_pairs.js');
const skip = process.env.FIRESTORE_EMULATOR_HOST ? false : 'sin FIRESTORE_EMULATOR_HOST';

test('emulador — CLI: sin --apply no escribe; --apply escribe; la segunda corrida no hace nada', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }));
  const cli = (...flags) => {
    const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`, ...flags], { encoding: 'utf8' });
    assert.strictEqual(res.status, 0, res.stderr + res.stdout);
    return res.stdout;
  };
  const leer = async (id) => (await db.doc(`trainer_athlete_pairs/${id}`).get()).data();

  for (const p of (await db.collection('trainer_athlete_pairs').get()).docs) await p.ref.delete();
  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data);
  assert.match(cli(), /DRY-RUN SUMMARY/);
  assert.strictEqual(await leer('t1_a1'), undefined);
  assert.match(cli('--apply'), /6\s+pares ESCRITOS/);
  assert.deepStrictEqual({ ...(await leer('t1_a1')), updatedAt: null }, { ...par('t1', 'a1', true, 'active'), updatedAt: null });
  assert.match(cli('--apply'), /0\s+pares ESCRITOS/);
});
