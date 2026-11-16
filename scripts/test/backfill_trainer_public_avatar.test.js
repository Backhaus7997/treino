/**
 * test/backfill_trainer_public_avatar.test.js
 *
 * `scripts/backfill_trainer_public_avatar.js` (#1718). Dos capas:
 *   - Firestore en memoria (`fakeDb`): corre siempre, también en CI (sin emulador).
 *   - emulador: se SALTEA sin `FIRESTORE_EMULATOR_HOST`. Para correrla:
 *       firebase emulators:exec --only firestore --project demo-treino \
 *         "node --test scripts/test/backfill_trainer_public_avatar.test.js"
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { parseArgs, decidir, run } = require('../backfill_trainer_public_avatar');

const silencio = { log() {}, warn() {} };
const TARJETAS = 'trainerPublicProfiles';

/** Firestore en memoria con lo justo que usa el script. `escrituras` = paths escritos. */
function fakeDb(semilla) {
  const store = new Map(Object.entries(semilla));
  const escrituras = [];
  const snap = (p) => ({ id: p.split('/').pop(), exists: store.has(p), data: () => store.get(p) });
  const consulta = (col, desde = null, tope = Infinity) => ({
    orderBy: () => consulta(col, desde, tope),
    limit: (n) => consulta(col, desde, n),
    startAfter: (s) => consulta(col, s.id, tope),
    get: async () => {
      const docs = [...store.keys()].sort()
        .filter((p) => p.startsWith(`${col}/`) && (!desde || p.slice(col.length + 1) > desde))
        .slice(0, tope).map(snap);
      return { docs, size: docs.length };
    },
  });
  return {
    store, escrituras,
    collection: (col) => ({ ...consulta(col), doc: (id) => ({ path: `${col}/${id}` }) }),
    getAll: async (...refs) => refs.map((r) => snap(r.path)),
    runTransaction: async (fn) => fn({
      get: async (ref) => snap(ref.path),
      update: (ref, data) => {
        escrituras.push(ref.path);
        store.set(ref.path, { ...store.get(ref.path), ...data });
      },
    }),
  };
}

const trainer = (avatarUrl) => ({ role: 'trainer', displayName: 'PF', avatarUrl });
const tarjeta = (avatarUrl) => ({ uid: 'x', displayName: 'PF', bio: 'Bio', avatarUrl });

/** Una tarjeta por caso. Las que se COPIAN son u2 y u3; las de foto quitada, u4 y u8. */
function escenario() {
  return {
    'users/u1': trainer('A'), [`${TARJETAS}/u1`]: tarjeta('A'), // ya coinciden
    'users/u2': trainer('B'), [`${TARJETAS}/u2`]: tarjeta(null), // la tarjeta no tenía foto
    'users/u3': trainer('C'), [`${TARJETAS}/u3`]: tarjeta('VIEJA'), // otra foto
    'users/u4': trainer(null), [`${TARJETAS}/u4`]: tarjeta('VIEJA'), // «Quitar foto» anterior a #1706
    'users/u5': { role: 'trainer' }, [`${TARJETAS}/u5`]: tarjeta(null), // sin foto en los dos (campo ausente en la cuenta)
    'users/u6': { role: 'athlete', avatarUrl: 'X' }, [`${TARJETAS}/u6`]: tarjeta(null), // tarjeta forjada por un alumno
    [`${TARJETAS}/u7`]: tarjeta(null), // sin users/
    'users/u8': trainer('   '), [`${TARJETAS}/u8`]: tarjeta('VIEJA'), // foto en blanco = sin foto
    'users/u9': trainer('D '), [`${TARJETAS}/u9`]: tarjeta('D'), // coincide salvo el espacio
    'users/u10': trainer(123), [`${TARJETAS}/u10`]: tarjeta(null), // no es un string
    'users/u11': trainer('E'), // el PF no tiene tarjeta: no se crea
  };
}

// ── Decisión pura ───────────────────────────────────────────────────────────

test('parseArgs — dry-run por default; --apply escribe; --apply --dry-run NO; flag ajena aborta', () => {
  assert.deepStrictEqual([parseArgs(['n', 'x']).write, parseArgs(['n', 'x']).limpiar], [false, false]);
  assert.strictEqual(parseArgs(['n', 'x', '--apply']).write, true);
  assert.strictEqual(parseArgs(['n', 'x', '--apply', '--dry-run']).write, false);
  assert.strictEqual(parseArgs(['n', 'x', '--dry-run', '--apply']).write, false);
  assert.strictEqual(parseArgs(['n', 'x', '--limpiar-fotos-quitadas']).limpiar, true);
  assert.throws(() => parseArgs(['n', 'x', '--write']), /Flag desconocida/);
});

test('decidir — copia sólo con foto en la cuenta; sin foto en la cuenta NUNCA copia; un no-entrenador no entra', () => {
  assert.deepStrictEqual(decidir(trainer('B'), tarjeta(null)), { accion: 'copiar-sin-foto', valor: 'B' });
  assert.deepStrictEqual(decidir(trainer(' B '), tarjeta('A')), { accion: 'copiar-otra-foto', valor: 'B' });
  assert.deepStrictEqual(decidir(trainer(null), tarjeta('A')), { accion: 'foto-quitada', valor: null });
  assert.strictEqual(decidir(trainer(''), tarjeta('')).accion, 'igual');
  assert.strictEqual(decidir({ role: 'trainer' }, {}).accion, 'igual'); // ni la cuenta ni la tarjeta tienen el campo
  assert.strictEqual(decidir({ role: 'athlete', avatarUrl: 'B' }, tarjeta(null)).accion, 'no-entrenador');
  assert.strictEqual(decidir(null, tarjeta(null)).accion, 'no-entrenador');
  assert.strictEqual(decidir({ role: 'trainer', avatarUrl: {} }, tarjeta(null)).accion, 'sin-decidir');
});

// ── run: el comportamiento completo ─────────────────────────────────────────

test('run — dry-run: cuenta todo y NO escribe una sola vez', async () => {
  const db = fakeDb(escenario());
  const antes = JSON.stringify([...db.store]);
  const r = await run(db, { write: false }, silencio);

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(JSON.stringify([...db.store]), antes);
  assert.deepStrictEqual([r.tarjetas, r.noEntrenador, r.iguales, r.sinDecidir.length], [10, 2, 3, 1]);
  assert.deepStrictEqual([r.copiarSinFoto, r.copiarOtraFoto, r.fotoQuitada, r.escritas], [1, 1, 2, 0]);
});

test('run --apply — copia SOLO avatarUrl; la foto quitada no se toca; no crea tarjetas; idempotente', async () => {
  const db = fakeDb(escenario());
  const antes = new Map(db.store);
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual(db.escrituras, [`${TARJETAS}/u2`, `${TARJETAS}/u3`]);
  assert.deepStrictEqual([r.escritas, r.cambiaron], [2, 0]);
  assert.deepStrictEqual(db.store.get(`${TARJETAS}/u2`), { ...antes.get(`${TARJETAS}/u2`), avatarUrl: 'B' }); // lo demás, intacto
  assert.strictEqual(db.store.get(`${TARJETAS}/u3`).avatarUrl, 'C');
  for (const id of ['u1', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9', 'u10']) {
    assert.deepStrictEqual(db.store.get(`${TARJETAS}/${id}`), antes.get(`${TARJETAS}/${id}`), id);
  }
  assert.strictEqual(db.store.has(`${TARJETAS}/u11`), false, 'no crea la tarjeta que no existe');
  assert.deepStrictEqual([...db.store.keys()].filter((k) => k.startsWith('users/')), [...antes.keys()].filter((k) => k.startsWith('users/')));

  await run(db, { write: true }, silencio);
  assert.deepStrictEqual(db.escrituras, [`${TARJETAS}/u2`, `${TARJETAS}/u3`], 'la segunda corrida no escribe');
});

test('run --apply --limpiar-fotos-quitadas — pone en null la foto quitada (también la en blanco) y nada más', async () => {
  const db = fakeDb(escenario());
  const r = await run(db, { write: true, limpiar: true }, silencio);

  assert.deepStrictEqual(db.escrituras, ['u2', 'u3', 'u4', 'u8'].map((id) => `${TARJETAS}/${id}`));
  assert.deepStrictEqual([db.store.get(`${TARJETAS}/u4`).avatarUrl, db.store.get(`${TARJETAS}/u8`).avatarUrl], [null, null]);
  assert.strictEqual(db.store.get(`${TARJETAS}/u4`).bio, 'Bio');
  assert.strictEqual(r.escritas, 4);
});

test('run --apply — lo que cambia entre la lectura y la escritura se respeta (y una tarjeta borrada no se resucita)', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('users/u2', trainer(null)); // el PF quitó la foto: ya no hay nada que copiar
    db.store.delete(`${TARJETAS}/u3`); // y borró su tarjeta
    return tx(fn);
  };
  const r = await run(db, { write: true }, silencio);

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(db.store.has(`${TARJETAS}/u3`), false);
  assert.deepStrictEqual([r.escritas, r.cambiaron], [0, 2]);
});

test('run — paginar de a 2 da el mismo resultado que de a 500', async () => {
  const grande = await run(fakeDb(escenario()), { write: false }, silencio);
  assert.deepStrictEqual(await run(fakeDb(escenario()), { write: false, pagina: 2 }, silencio), grande);
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const PROJECT = 'demo-trainer-avatar'; // namespace propio del emulador
const SCRIPT = path.join(__dirname, '..', 'backfill_trainer_public_avatar.js');
const skip = process.env.FIRESTORE_EMULATOR_HOST ? false : 'sin FIRESTORE_EMULATOR_HOST';

test('emulador — CLI: sin --apply no escribe; --apply copia; la 2da corrida no hace nada; el flag limpia', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }));
  const cli = (...flags) => {
    const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`, ...flags], { encoding: 'utf8' });
    assert.strictEqual(res.status, 0, res.stderr + res.stdout);
    return res.stdout;
  };
  const avatar = async (id) => (await db.doc(`${TARJETAS}/${id}`).get()).data().avatarUrl;

  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data); // set: re-siembra limpio
  assert.match(cli(), /DRY-RUN SUMMARY/);
  assert.strictEqual(await avatar('u2'), null);
  assert.match(cli('--apply'), /2\s+tarjetas ESCRITAS/);
  assert.deepStrictEqual([await avatar('u2'), await avatar('u3'), await avatar('u4')], ['B', 'C', 'VIEJA']);
  assert.match(cli('--apply'), /0\s+tarjetas ESCRITAS/);
  assert.match(cli('--apply', '--limpiar-fotos-quitadas'), /2\s+tarjetas ESCRITAS/);
  assert.deepStrictEqual([await avatar('u4'), await avatar('u8')], [null, null]);
  assert.strictEqual((await db.doc(`${TARJETAS}/u11`).get()).exists, false); // no crea tarjetas
  assert.strictEqual((await db.doc(`${TARJETAS}/u2`).get()).data().bio, 'Bio'); // sólo avatarUrl
});

test('emulador — run con el Firestore REAL: paginar de a 2 = de a 500, y la transacción corre', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }, 'paginado'));
  for (const [p, data] of Object.entries(escenario())) await db.doc(p).set(data);

  const grande = await run(db, { write: false }, silencio);
  assert.deepStrictEqual(await run(db, { write: false, pagina: 2 }, silencio), grande);
  assert.deepStrictEqual([grande.tarjetas, grande.iguales, grande.fotoQuitada], [10, 3, 2]);
  assert.strictEqual((await run(db, { write: true, pagina: 2 }, silencio)).escritas, 2);
});
