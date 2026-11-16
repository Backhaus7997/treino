/**
 * test/backfill_cancel_appointments_unlinked.test.js
 *
 * `scripts/backfill_cancel_appointments_unlinked.js` (sigue a #1833). Tres capas:
 *   - Firestore en memoria (`fakeDb`): corre siempre, también en CI (sin emulador).
 *   - contrato con el TS: las copias del script (señal, razones de borrado de cuenta, textos del
 *     rastro) contra `functions/src/`. Corre siempre.
 *   - emulador: se SALTEA sin `FIRESTORE_EMULATOR_HOST`. Para correrla:
 *       firebase emulators:exec --only firestore --project demo-treino \
 *         "node --test scripts/test/backfill_cancel_appointments_unlinked.test.js"
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const {
  parseArgs, evaluarVinculos, terminadoPor, turnoAbierto, run, ART_OFFSET_MS, LINK_TERMINADO, CUENTA_BORRADA,
} = require('../backfill_cancel_appointments_unlinked');

const H = 3600000;
const DIA = 24 * H;
const AHORA = new Date('2026-11-13T15:00:00Z');
// `startsAt` se guarda como hora de pared argentina etiquetada UTC (ADR-7): el instante real MENOS 3 h.
const startsIn = (ms) => Timestamp.fromMillis(AHORA.getTime() + ms - 3 * H);
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
    runTransaction: async (fn) =>
      fn({
        get: async (x) => x.get(),
        getAll: async (...refs) => refs.map((r) => snap(r.path)),
        update: (ref, data) => {
          escrituras.push(ref.path);
          store.set(ref.path, { ...store.get(ref.path), ...data });
        },
      }),
  };
}

const turno = (t, a, extra) => ({
  trainerId: t, athleteId: a, athleteDisplayName: 'Alumno', durationMin: 60, status: 'confirmed', startsAt: startsIn(DIA), ...extra,
});
const vinculo = (t, a, extra) => ({
  trainerId: t, athleteId: a, status: 'terminated', acceptedAt: T(0), terminatedAt: T(10), terminationReason: 'athlete-terminated', ...extra,
});
const rechazo = { acceptedAt: null, terminationReason: 'declined' };
const vivo = (status) => ({ status, terminatedAt: null, terminationReason: undefined });
const delCliente = { byUid: 't1', atMs: 1, reason: 'Vínculo terminado por el entrenador.' };

/** Doce pares, uno por caso. Los turnos de cada par se llaman `pN-…`. */
function escenario() {
  return {
    // p1: el alumno terminó. Se cancelan 3; no se toca lo que ya empezó ni lo ya cancelado.
    'trainer_links/l1': vinculo('t1', 'a1'),
    'appointments/p1-cerca': turno('t1', 'a1', { startsAt: startsIn(2 * H) }), // en 2 h: guardado, queda ANTES de `ahora`
    'appointments/p1-serie': turno('t1', 'a1', { recurringId: 'serie', startsAt: startsIn(7 * DIA) }),
    'appointments/p1-req': turno('t1', 'a1', { status: 'requested' }),
    'appointments/p1-empezo': turno('t1', 'a1', { startsAt: startsIn(-1 * H) }),
    'appointments/p1-ya': turno('t1', 'a1', { status: 'cancelled', cancelledBy: 't1', cancellationLog: [delCliente] }),
    // p2 y p3: vínculo vivo (se re-vincularon / pausado). Intactos.
    'trainer_links/l2': vinculo('t2', 'a2'), 'trainer_links/l2b': vinculo('t2', 'a2', vivo('active')), 'appointments/p2-t': turno('t2', 'a2'),
    'trainer_links/l3': vinculo('t3', 'a3'), 'trainer_links/l3b': vinculo('t3', 'a3', vivo('paused')), 'appointments/p3-t': turno('t3', 'a3'),
    // p4 y p5: terminó por borrado de cuenta. Lo cubren las cascadas.
    'trainer_links/l4': vinculo('t4', 'a4', { reason: 'account-deleted' }), 'appointments/p4-t': turno('t4', 'a4'),
    'trainer_links/l5': vinculo('t5', 'a5', { reason: 'trainer-account-deleted' }), 'appointments/p5-t': turno('t5', 'a5'),
    // p6: sólo un rechazo. Nunca fue un vínculo.
    'trainer_links/l6': vinculo('t6', 'a6', rechazo), 'appointments/p6-t': turno('t6', 'a6'),
    // p7: ambiguo (terminated sin acceptedAt ni razón de rechazo).
    'trainer_links/l7': vinculo('t7', 'a7', { acceptedAt: null, terminationReason: undefined }), 'appointments/p7-t': turno('t7', 'a7'),
    // p8: terminó el PF.
    'trainer_links/l8': vinculo('t8', 'a8', { terminationReason: 'trainer-terminated' }), 'appointments/p8-t': turno('t8', 'a8'),
    // p9: terminó, y el alumno volvió a pedir (pending no es vivo).
    'trainer_links/l9': vinculo('t9', 'a9'), 'trainer_links/l9b': { trainerId: 't9', athleteId: 'a9', status: 'pending' },
    'appointments/p9-t': turno('t9', 'a9'),
    // p10: terminó, sin turnos.
    'trainer_links/l10': vinculo('t10', 'a10'),
    // p11: terminó sin motivo conocido: texto neutro.
    'trainer_links/l11': vinculo('t11', 'a11', { terminationReason: undefined }), 'appointments/p11-t': turno('t11', 'a11'),
    // p12: turno de un par sin ningún trainer_links: no hay evidencia, no se toca.
    'appointments/p12-t': turno('t12', 'a12'),
  };
}

const CANCELADOS = ['p1-cerca', 'p1-serie', 'p1-req', 'p8-t', 'p9-t', 'p11-t'];
const ESCRITOS = CANCELADOS.map((id) => `appointments/${id}`);

// ── Decisión pura ───────────────────────────────────────────────────────────

test('parseArgs — dry-run por default; --apply escribe; --apply --dry-run NO; flag ajena aborta', () => {
  assert.strictEqual(parseArgs(['node', 'x']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--apply']).write, true);
  assert.strictEqual(parseArgs(['node', 'x', '--apply', '--dry-run']).write, false);
  assert.strictEqual(parseArgs(['node', 'x', '--dry-run', '--apply']).write, false);
  assert.throws(() => parseArgs(['node', 'x', '--write']), /Flag desconocida/);
});

test('evaluarVinculos — vivo gana a todo; borrado de cuenta; nunca fue; ambiguo; y el cierre es el ÚLTIMO real', () => {
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a'), vinculo('t', 'a', vivo('active'))]).tipo, 'vivo');
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', vivo('paused'))]).tipo, 'vivo');
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', { reason: 'account-deleted' })]).tipo, 'cuenta-borrada');
  // «alguno» y no «el último»: las cuentas borradas no vuelven.
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', { reason: 'trainer-account-deleted' }), vinculo('t', 'a')]).tipo, 'cuenta-borrada');
  assert.strictEqual(evaluarVinculos([]).tipo, 'nunca-fue');
  assert.strictEqual(evaluarVinculos([{ status: 'pending' }]).tipo, 'nunca-fue');
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', rechazo)]).tipo, 'nunca-fue');
  assert.strictEqual(evaluarVinculos([vinculo('t', 'a', { acceptedAt: null, terminationReason: undefined })]).tipo, 'sin-decidir');

  const viejo = vinculo('t', 'a', { terminatedAt: T(10), terminationReason: 'athlete-terminated' });
  const nuevo = vinculo('t', 'a', { terminatedAt: T(40), terminationReason: 'trainer-terminated' });
  const sinFecha = vinculo('t', 'a', { terminatedAt: undefined, terminationReason: 'switched_trainer' });
  // Un rechazo posterior (T(90)) no es un vínculo real: no cuenta como cierre.
  assert.strictEqual(evaluarVinculos([viejo, nuevo, vinculo('t', 'a', { ...rechazo, terminatedAt: T(90) })]).cierre, nuevo);
  assert.strictEqual(evaluarVinculos([nuevo, viejo]).cierre, nuevo);
  assert.strictEqual(evaluarVinculos([sinFecha, viejo]).cierre, viejo, 'uno sin terminatedAt no le gana a uno con fecha');
  assert.strictEqual(evaluarVinculos([sinFecha]).cierre, sinFecha);
});

test('terminadoPor — quién cortó y el texto del rastro (el mismo que escribe la CF)', () => {
  const quien = (terminationReason) => terminadoPor({ terminationReason }, 'PF', 'AL');
  assert.deepStrictEqual(quien('trainer-terminated'), { byUid: 'PF', motivo: 'Vínculo terminado por el entrenador.' });
  assert.deepStrictEqual(quien('athlete-terminated'), { byUid: 'AL', motivo: 'Vínculo terminado por el alumno.' });
  assert.deepStrictEqual(quien('switched_trainer'), { byUid: 'AL', motivo: 'Vínculo terminado por el alumno.' });
  assert.deepStrictEqual(quien(undefined), { byUid: 'AL', motivo: 'Vínculo terminado.' });
});

test('turnoAbierto — sólo confirmed/requested, y del par', () => {
  const par = { trainerId: 't', athleteId: 'a' };
  assert.strictEqual(turnoAbierto(turno('t', 'a'), par), true);
  assert.strictEqual(turnoAbierto(turno('t', 'a', { status: 'requested' }), par), true);
  assert.strictEqual(turnoAbierto(turno('t', 'a', { status: 'cancelled' }), par), false);
  assert.strictEqual(turnoAbierto(turno('t', 'otro'), par), false);
  assert.strictEqual(turnoAbierto(null, par), false);
});

// ── Contrato con la CF (TS) ─────────────────────────────────────────────────

const FUNCTIONS = path.join(__dirname, '..', '..', 'functions', 'src');
const fuente = (rel) => fs.readFileSync(path.join(FUNCTIONS, rel), 'utf8');

test('contrato — las copias del script coinciden con el TS que las produce y las consume', () => {
  const cf = fuente('cancel-appointments-on-unlink.ts');
  assert.match(cf, new RegExp(`LINK_TERMINATED_REASON = "${LINK_TERMINADO}"`), 'la señal de la CF');
  assert.match(cf, /OPEN_STATUSES: readonly string\[\] = \["confirmed", "requested"\]/, 'los estados abiertos');
  for (const texto of ['Vínculo terminado por el entrenador.', 'Vínculo terminado por el alumno.', 'Vínculo terminado.']) {
    assert.ok(cf.includes(`"${texto}"`), `el texto del rastro «${texto}»`);
  }
  // El notificador se calla con esa misma señal: sin su guard desplegado, el backfill avisaría N veces.
  assert.match(fuente('notifications/notify-appointment.ts'), /after\.reason === LINK_TERMINATED_REASON/);

  assert.deepStrictEqual([...CUENTA_BORRADA].sort(), ['account-deleted', 'trainer-account-deleted']);
  assert.match(fuente('cascade/trainer-links.ts'), /reason: "account-deleted"/);
  assert.match(fuente('cascade/trainer-data.ts'), /TRAINER_ACCOUNT_DELETED_REASON = "trainer-account-deleted"/);
  assert.match(fuente('notifications/weekly-streak.ts'), new RegExp(`ART_OFFSET_MS = ${ART_OFFSET_MS / H} \\* `));
});

// ── run: el comportamiento completo ─────────────────────────────────────────

test('run — dry-run: cuenta todo, lista el plan y NO escribe una sola vez', async () => {
  const db = fakeDb(escenario());
  const antes = JSON.stringify([...db.store]);
  const lineas = [];
  const r = await run(db, { write: false, ahora: AHORA }, { log: (s) => lineas.push(s), warn() {} });

  assert.deepStrictEqual(db.escrituras, []);
  assert.strictEqual(JSON.stringify([...db.store]), antes);
  assert.deepStrictEqual(
    [r.pares, r.vivos, r.cuentaBorrada, r.nuncaFueron, r.sinDecidir.length],
    [11, 2, 2, 1, 1],
  );
  assert.deepStrictEqual(
    [r.terminados, r.sinTurnos, r.paresConTurnos, r.aCancelar.reduce((s, c) => s + c.ids.length, 0), r.cancelados],
    [5, 1, 4, 6, 0],
  );
  assert.ok(lineas.some((l) => l.includes('cancelaría 3 turno(s)  t1 -> a1')), 'el plan nombra el par y la cantidad');
  assert.ok(lineas.every((l) => !l.includes('p12') && !l.includes('p2-t')), 'ni el par sin links ni el vivo figuran');
  assert.ok(lineas.some((l) => l.includes('DRY-RUN SUMMARY')));
});

test('run --apply — cancela SOLO lo que corresponde, con la forma de la CF; y es idempotente', async () => {
  const db = fakeDb(escenario());
  const r = await run(db, { write: true, ahora: AHORA }, silencio);

  assert.deepStrictEqual([...db.escrituras].sort(), [...ESCRITOS].sort());
  assert.strictEqual(r.cancelados, 6);
  assert.strictEqual(r.cambiaron, 0);

  const quien = { 'p8-t': ['t8', 'Vínculo terminado por el entrenador.'], 'p11-t': ['a11', 'Vínculo terminado.'] };
  for (const id of CANCELADOS) {
    const d = db.store.get(`appointments/${id}`);
    const [byUid, motivo] = quien[id] || [id.startsWith('p1-') ? 'a1' : 'a9', 'Vínculo terminado por el alumno.'];
    assert.strictEqual(d.status, 'cancelled', id);
    assert.strictEqual(d.reason, LINK_TERMINADO, `${id}: la señal que hace callar al notificador`);
    assert.strictEqual(d.cancelledBy, byUid, id);
    assert.ok(FieldValue.serverTimestamp().isEqual(d.cancelledAt), `${id}: cancelledAt es serverTimestamp`);
    assert.ok(
      FieldValue.arrayUnion({ byUid, atMs: AHORA.getTime(), reason: motivo }).isEqual(d.cancellationLog),
      `${id}: el rastro, con un instante REAL`,
    );
    assert.strictEqual(d.athleteDisplayName, 'Alumno', `${id}: el resto, intacto`);
  }
  // Lo que NO se toca.
  assert.strictEqual(db.store.get('appointments/p1-empezo').status, 'confirmed', 'ya empezó hace 1 h');
  assert.deepStrictEqual(db.store.get('appointments/p1-ya').cancellationLog, [delCliente], 'lo que el PF ya canceló (#1809)');
  for (const id of ['p2-t', 'p3-t', 'p4-t', 'p5-t', 'p6-t', 'p7-t', 'p12-t']) {
    assert.strictEqual(db.store.get(`appointments/${id}`).status, 'confirmed', `appointments/${id} no se toca`);
    assert.strictEqual(db.store.get(`appointments/${id}`).reason, undefined);
  }

  const r2 = await run(db, { write: true, ahora: AHORA }, silencio);
  assert.deepStrictEqual([r2.aCancelar.length, r2.cancelados, r2.sinTurnos], [0, 0, 5]);
  assert.strictEqual(db.escrituras.length, 6, 'la segunda corrida no escribe');
});

test('run — «por venir» se mide en el marco de startsAt: en 10 min y 2 h 50 min sí; hace 10 min, no', async () => {
  const db = fakeDb({
    'trainer_links/l': vinculo('t', 'a'),
    'appointments/en-10': turno('t', 'a', { startsAt: startsIn(10 * 60000) }),
    'appointments/en-2h50': turno('t', 'a', { startsAt: startsIn(170 * 60000) }),
    'appointments/hace-10': turno('t', 'a', { startsAt: startsIn(-10 * 60000) }),
  });
  // Premisa: guardado como la app, un turno en 10 min queda ANTES de `ahora` en instante real.
  assert.ok(startsIn(10 * 60000).toMillis() < AHORA.getTime());
  assert.strictEqual(ART_OFFSET_MS, 3 * H);

  await run(db, { write: true, ahora: AHORA }, silencio);

  assert.deepStrictEqual(
    ['en-10', 'en-2h50', 'hace-10'].map((id) => db.store.get(`appointments/${id}`).status),
    ['cancelled', 'cancelled', 'confirmed'],
  );
});

test('run --apply — un re-vínculo entre la lectura y la escritura NO cancela turnos de un vínculo vivo', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('trainer_links/nuevo', vinculo('t1', 'a1', vivo('active'))); // sólo el par de p1
    return tx(fn);
  };
  const r = await run(db, { write: true, ahora: AHORA }, silencio);

  assert.ok(!db.escrituras.some((p) => p.startsWith('appointments/p1-')), 'p1 se re-vinculó: no se cancela nada');
  assert.deepStrictEqual(db.escrituras.length, 3, 'p8, p9 y p11 siguen sin vínculo vivo'); // `nuevo` es de t1/a1: los demás pares no cambian
  assert.deepStrictEqual([r.cancelados, r.cambiaron], [3, 3]);
});

test('run --apply — un turno que se canceló entre la lectura y la escritura no se pisa', async () => {
  const db = fakeDb(escenario());
  const tx = db.runTransaction;
  db.runTransaction = (fn) => {
    db.store.set('appointments/p8-t', { ...db.store.get('appointments/p8-t'), status: 'cancelled', cancelledBy: 't8' });
    return tx(fn);
  };
  const r = await run(db, { write: true, ahora: AHORA }, silencio);

  assert.ok(!db.escrituras.includes('appointments/p8-t'));
  assert.strictEqual(db.store.get('appointments/p8-t').reason, undefined);
  assert.deepStrictEqual([r.cancelados, r.cambiaron], [5, 1]);
});

test('run — más de un lote por transacción y paginar chico dan el mismo resultado', async () => {
  const grande = await run(fakeDb(escenario()), { write: false, ahora: AHORA }, silencio);
  assert.deepStrictEqual(await run(fakeDb(escenario()), { write: false, ahora: AHORA, pagina: 2 }, silencio), grande);

  const db = fakeDb(escenario());
  const r = await run(db, { write: true, ahora: AHORA, porTransaccion: 1, pagina: 3 }, silencio);
  assert.strictEqual(r.cancelados, 6);
  assert.deepStrictEqual([...db.escrituras].sort(), [...ESCRITOS].sort());
});

// ── Contra el emulador ──────────────────────────────────────────────────────

const PROJECT = 'demo-cancel-appts'; // namespace propio del emulador
const SCRIPT = path.join(__dirname, '..', 'backfill_cancel_appointments_unlinked.js');
const skip = process.env.FIRESTORE_EMULATOR_HOST ? false : 'sin FIRESTORE_EMULATOR_HOST';

test('emulador — CLI: sin --apply no escribe; --apply cancela con la forma real; la segunda corrida no hace nada', { skip }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const db = require('firebase-admin/firestore').getFirestore(initializeApp({ projectId: PROJECT }));
  const cli = (...flags) => {
    const res = spawnSync(process.execPath, [SCRIPT, `--project=${PROJECT}`, ...flags], { encoding: 'utf8' });
    assert.strictEqual(res.status, 0, res.stderr + res.stdout);
    return res.stdout;
  };
  const leer = async (id) => (await db.doc(`appointments/${id}`).get()).data();

  // El CLI usa el reloj real: se corre todo el escenario de `AHORA` al ahora de verdad, conservando cada desfase
  // (p1-cerca en 2 h, p1-empezo hace 1 h...), que ya viene en el marco de `startsAt`.
  const corrimiento = Date.now() - AHORA.getTime();
  const alReloj = (ts) => Timestamp.fromMillis(ts.toMillis() + corrimiento);
  // Firestore rechaza `undefined` (el escenario lo usa para «sin campo»): se descartan al sembrar.
  const sinUndefined = (d) => Object.fromEntries(Object.entries(d).filter(([, v]) => v !== undefined));
  const semilla = Object.entries(escenario()).map(([p, d]) => [p, sinUndefined(d.startsAt ? { ...d, startsAt: alReloj(d.startsAt) } : d)]);
  for (const [p, data] of semilla) await db.doc(p).set(data); // set: re-siembra limpio

  assert.match(cli(), /DRY-RUN SUMMARY/);
  assert.strictEqual((await leer('p1-serie')).status, 'confirmed');
  assert.strictEqual((await leer('p1-cerca')).status, 'confirmed');

  assert.match(cli('--apply'), /6\s+turnos CANCELADOS/);
  const d = await leer('p1-serie');
  assert.deepStrictEqual(
    [d.status, d.reason, d.cancelledBy, d.athleteId, d.durationMin],
    ['cancelled', LINK_TERMINADO, 'a1', 'a1', 60],
  );
  assert.ok(d.cancelledAt instanceof Timestamp);
  assert.strictEqual(d.cancellationLog.length, 1);
  assert.deepStrictEqual(
    [d.cancellationLog[0].byUid, d.cancellationLog[0].reason, typeof d.cancellationLog[0].atMs],
    ['a1', 'Vínculo terminado por el alumno.', 'number'],
  );
  assert.strictEqual((await leer('p8-t')).cancelledBy, 't8');
  assert.strictEqual((await leer('p2-t')).status, 'confirmed');
  assert.strictEqual((await leer('p1-empezo')).status, 'confirmed', 'ya empezó: no se toca');
  assert.strictEqual((await leer('p1-cerca')).status, 'cancelled', 'en 2 h: el marco de startsAt lo cuenta como futuro');
  assert.strictEqual((await leer('p1-ya')).cancellationLog.length, 1, 'lo ya cancelado no suma entradas');

  assert.match(cli('--apply'), /0\s+turnos CANCELADOS/);
  assert.strictEqual((await leer('p1-serie')).cancellationLog.length, 1);
});
