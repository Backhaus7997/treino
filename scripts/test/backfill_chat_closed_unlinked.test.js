/**
 * test/backfill_chat_closed_unlinked.test.js
 *
 * `scripts/backfill_chat_closed_unlinked.js` (#1697). Dos capas:
 *   - Firestore en memoria (`fakeDb`): corre siempre, también en CI (sin emulador).
 *   - emulador: se SALTEA sin `FIRESTORE_EMULATOR_HOST`. Para correrla:
 *       firebase emulators:exec --only firestore --project demo-treino \
 *         "node --test scripts/test/backfill_chat_closed_unlinked.test.js"
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { Timestamp } = require('firebase-admin/firestore');

const { parseArgs, evaluarVinculos, evaluarChat, run } = require('../backfill_chat_closed_unlinked');

const T = (s) => Timestamp.fromMillis(1_700_000_000_000 + s * 1000);
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
        update: (ref, data) => {
          escrituras.push(ref.path);
          store.set(ref.path, { ...store.get(ref.path), ...data });
        },
      }),
  };
}

const vinculo = (t, a, extra) => ({
  trainerId: t, athleteId: a, status: 'terminated', acceptedAt: T(0), terminatedAt: T(10), ...extra,
});
const rechazo = { acceptedAt: null, terminationReason: 'declined' };
const vivo = (status) => ({ status, terminatedAt: null });

/** Once pares, uno por caso. El chat de (t, a) es `a_t`. El corte de los vínculos reales es T(10). */
function escenario() {
  const antes = { createdAt: T(5) };
  return {
    'trainer_links/l1': vinculo('t1', 'a1'), 'chats/a1_t1': antes, // SE CIERRA
    'trainer_links/l2': vinculo('t2', 'a2'), 'chats/a2_t2': { createdAt: T(20) }, // social: nació después
    'trainer_links/l3': vinculo('t3', 'a3', rechazo), 'chats/a3_t3': antes, // sólo un rechazo
    'trainer_links/l4': vinculo('t4', 'a4'), 'chats/a4_t4': { ...antes, closedAt: T(12) }, // ya cerrado
    'trainer_links/l5': vinculo('t5', 'a5'), 'chats/a5_t5': antes, // vivo: se re-vinculó
    'trainer_links/l5b': vinculo('t5', 'a5', vivo('active')),
    'trainer_links/l6': vinculo('t6', 'a6'), // sin chat
    'trainer_links/l7': vinculo('t7', 'a7', { acceptedAt: null }), 'chats/a7_t7': antes, // ambiguo
    'trainer_links/l8': vinculo('t8', 'a8'), 'chats/a8_t8': { createdAt: T(20) }, // fin real T(10)...
    'trainer_links/l8b': vinculo('t8', 'a8', { ...rechazo, terminatedAt: T(30) }), // ...y un rechazo T(30)
    'trainer_links/l9': vinculo('t9', 'a9'), 'chats/a9_t9': antes, // vivo: pausado
    'trainer_links/l9b': vinculo('t9', 'a9', vivo('paused')),
    'trainer_links/l10': { trainerId: 't10', athleteId: 'a10', status: 'pending' }, 'chats/a10_t10': antes,
    'trainer_links/l11': vinculo('t11', 'a11'), 'chats/a11_t11': { createdAt: T(20) }, // se re-vinculó y terminó
    'trainer_links/l11b': vinculo('t11', 'a11', { terminatedAt: T(40) }), // otra vez: el corte es T(40)
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

test('evaluarVinculos / evaluarChat — los bordes que el escenario no cubre', () => {
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', { terminatedAt: undefined })]).tipo, 'sin-decidir');
  assert.strictEqual(evaluarChat(T(10), { createdAt: T(10) }), 'cerrar'); // creado EN el corte
  assert.strictEqual(evaluarChat(T(10), { createdAt: Timestamp.fromMillis(T(10).toMillis() + 1) }), 'social');
  assert.strictEqual(evaluarChat(T(10), { createdAt: T(5), closedAt: null }), 'cerrar'); // null = abierto
  assert.strictEqual(evaluarChat(T(10), {}), 'sin-decidir');
});

// ── run: el comportamiento completo ─────────────────────────────────────────

test('run — dry-run: cuenta todo y NO escribe una sola vez', async () => {
  const db = fakeDb(escenario());
  const antes = JSON.stringify([...db.store]);
  const r = await run(db, { write: false }, silencio);

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(JSON.stringify([...db.store]), antes);
  assert.deepStrictEqual(
    [r.pares, r.vivos, r.soloPendientes, r.rechazados, r.sinDecidir.length],
    [11, 2, 1, 1, 1],
  );
  assert.deepStrictEqual([r.noChat, r.yaCerrados, r.social, r.aCerrar.length, r.cerrados], [1, 1, 2, 2, 0]);
});

test('run --apply — cierra SOLO los chats que corresponden, con closedAt = el corte; y es idempotente', async () => {
  const db = fakeDb(escenario());
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual(db.escrituras, ['chats/a1_t1', 'chats/a11_t11']);
  assert.strictEqual(r.cerrados, 2);
  assert.ok(db.store.get('chats/a1_t1').closedAt.isEqual(T(10)));
  assert.ok(db.store.get('chats/a11_t11').closedAt.isEqual(T(40)), 'el corte es la ÚLTIMA terminación real');
  assert.ok(db.store.get('chats/a4_t4').closedAt.isEqual(T(12)), 'un chat ya cerrado no se pisa');
  for (const id of ['a2_t2', 'a3_t3', 'a5_t5', 'a7_t7', 'a8_t8', 'a9_t9', 'a10_t10']) {
    assert.strictEqual(db.store.get(`chats/${id}`).closedAt, undefined, `chats/${id} no se toca`);
  }
  assert.strictEqual(db.store.has('chats/a6_t6'), false, 'no crea el chat que no existe');

  const r2 = await run(db, { write: true }, silencio);
  assert.deepStrictEqual(db.escrituras, ['chats/a1_t1', 'chats/a11_t11']);
  assert.deepStrictEqual([r2.aCerrar.length, r2.cerrados, r2.yaCerrados], [0, 0, 3]);
});

test('run --apply — un re-vínculo entre la lectura y la escritura NO deja cerrado un chat vivo', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('trainer_links/nuevo', vinculo('t1', 'a1', vivo('active')));
    return tx(fn);
  };
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual(db.escrituras, ['chats/a11_t11']); // el otro par no se re-vinculó
  assert.deepStrictEqual([r.cerrados, r.cambiaron], [1, 1]);
});

test('run — paginar de a 2 da el mismo resultado que de a 500', async () => {
  const grande = await run(fakeDb(escenario()), { write: false }, silencio);
  assert.deepStrictEqual(await run(fakeDb(escenario()), { write: false, pagina: 2 }, silencio), grande);
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const PROJECT = 'demo-chat-closed'; // namespace propio del emulador
const SCRIPT = path.join(__dirname, '..', 'backfill_chat_closed_unlinked.js');
const skip = process.env.FIRESTORE_EMULATOR_HOST ? false : 'sin FIRESTORE_EMULATOR_HOST';

test('emulador — CLI: sin --apply no escribe; --apply cierra; la segunda corrida no hace nada', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }));
  const cli = (...flags) => {
    const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`, ...flags], { encoding: 'utf8' });
    assert.strictEqual(res.status, 0, res.stderr + res.stdout);
    return res.stdout;
  };
  const closedAt = async (id) => (await db.doc(`chats/${id}`).get()).data().closedAt;

  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data); // set: re-siembra limpio
  assert.match(cli(), /DRY-RUN SUMMARY/);
  assert.strictEqual(await closedAt('a1_t1'), undefined);
  assert.match(cli('--apply'), /2\s+chats CERRADOS/);
  assert.ok((await closedAt('a1_t1')).isEqual(T(10)));
  assert.match(cli('--apply'), /0\s+chats CERRADOS/);
});
