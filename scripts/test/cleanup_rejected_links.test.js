/**
 * test/cleanup_rejected_links.test.js
 *
 * `clasificar()` de `cleanup_rejected_links.js`: en qué grupo cae cada doc de
 * `trainer_links` con `status == 'terminated'`. Sin red, sin `firebase-admin`.
 *
 *   node --test scripts/test/
 *
 * Por qué existe: esa función decide QUÉ SE BORRA en producción. `terminated`
 * es el mismo estado para un rechazo (que nadie extraña) y para el fin de un
 * vínculo real (del que cuelgan pagos y sesiones), así que un error acá no se
 * nota hasta que un PF pierde historia. El grupo AMBIGUO existe porque
 * `acceptedAt` NO es hermético: el propio repo lo llama «un DEFECTO DE DATOS»
 * en `functions/src/subscriptions/select-blocked-links.ts:192`, o sea que un
 * vínculo real viejo pudo quedar sin stamp.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  clasificar,
  desglosePorRazon,
  parseArgs,
} = require('../cleanup_rejected_links');

test('clasificar — rechazo del PF: acceptedAt null + declined → borra', () => {
  assert.strictEqual(
    clasificar({ acceptedAt: null, terminationReason: 'declined' }),
    'borra',
  );
});

test('clasificar — cancelación del alumno → borra', () => {
  assert.strictEqual(
    clasificar({ acceptedAt: null, terminationReason: 'cancelled-by-athlete' }),
    'borra',
  );
});

test('clasificar — acceptedAt ausente (no null) también cuenta como null', () => {
  assert.strictEqual(clasificar({ terminationReason: 'declined' }), 'borra');
});

test('clasificar — vínculo real terminado: acceptedAt presente → conserva', () => {
  assert.strictEqual(
    clasificar({
      acceptedAt: { _seconds: 1700000000 },
      terminationReason: 'athlete-terminated',
    }),
    'conserva',
  );
});

test('clasificar — switched_trainer con acceptedAt → conserva', () => {
  assert.strictEqual(
    clasificar({
      acceptedAt: { _seconds: 1700000000 },
      terminationReason: 'switched_trainer',
    }),
    'conserva',
  );
});

test('clasificar — acceptedAt presente gana SIEMPRE, aun con razón de rechazo', () => {
  // Combinación imposible por diseño (decline sólo corre sobre `pending`), pero
  // si aparece en los datos es una anomalía y NO se borra: `acceptedAt` es la
  // señal de que hubo relación, y ante la duda se conserva.
  assert.strictEqual(
    clasificar({
      acceptedAt: { _seconds: 1700000000 },
      terminationReason: 'declined',
    }),
    'conserva',
  );
});

test('clasificar — EL CASO PELIGROSO: acceptedAt null sin razón → ambiguo, NO borra', () => {
  // Un vínculo real viejo que perdió el stamp cae acá. Si esto devolviera
  // 'borra', el script destruiría historia con pagos colgando.
  assert.strictEqual(clasificar({ acceptedAt: null }), 'ambiguo');
});

test('clasificar — acceptedAt null con razón de terminate real → ambiguo', () => {
  for (const razon of [
    'athlete-terminated',
    'trainer-terminated',
    'switched_trainer',
    'Alta voluntaria del atleta',
  ]) {
    assert.strictEqual(
      clasificar({ acceptedAt: null, terminationReason: razon }),
      'ambiguo',
      `reason=${razon} debería ser ambiguo, no borrable`,
    );
  }
});

test('desglosePorRazon — cuenta por razón y nombra el faltante', () => {
  const desglose = desglosePorRazon([
    { id: 'a', razon: 'declined' },
    { id: 'b', razon: 'declined' },
    { id: 'c', razon: 'cancelled-by-athlete' },
    { id: 'd', razon: undefined },
  ]);

  assert.deepStrictEqual(desglose, [
    ['declined', 2],
    ['cancelled-by-athlete', 1],
    ['(sin razón)', 1],
  ]);
});

test('requerir el módulo NO inicializa el Admin SDK ni toca la red', () => {
  // El script corre `main()` sólo bajo `require.main === module`. Si eso se
  // rompiera, este archivo de test intentaría resolver credenciales de
  // producción con sólo importarlo.
  assert.strictEqual(typeof clasificar, 'function');
  assert.strictEqual(typeof desglosePorRazon, 'function');
});

// ── parseArgs: la compuerta del borrado ─────────────────────────────────────
//
// `--dry-run` estaba en la allowlist del validador y NUNCA se leía, así que
// `--apply --dry-run` borraba. Es la peor forma de fallar: el validador acepta
// el flag —le confirma al operador que lo entendió— y después lo ignora.
//
// Ocho scripts hermanos de este directorio (backfill_gym_ids, backfill_gym_names,
// backfill_athlete_counts, backfill_racha_freshness, backfill_trainer_links_shared,
// backfill_custom_exercise_name_lowercase, upload_drive_exercise_videos,
// upload_enriched_videos) usan `--dry-run` como LA flag que frena las
// escrituras. El único script del directorio que BORRA documentos no puede ser
// el único donde esa palabra no significa nada.
//
// Regla: ante flags en conflicto, gana la que NO destruye.

test('parseArgs — sin flags: dry-run (no borra)', () => {
  assert.strictEqual(parseArgs(['node', 'x']).apply, false);
});

test('parseArgs — --apply solo: borra', () => {
  assert.strictEqual(parseArgs(['node', 'x', '--apply']).apply, true);
});

test('parseArgs — EL BUG: --apply --dry-run NO borra', () => {
  const args = parseArgs(['node', 'x', '--apply', '--dry-run']);
  assert.strictEqual(args.apply, false, '--dry-run tiene que ganarle a --apply');
  assert.strictEqual(args.dryRunExplicito, true);
});

test('parseArgs — el orden de las flags no cambia nada', () => {
  assert.strictEqual(parseArgs(['node', 'x', '--dry-run', '--apply']).apply, false);
});

test('parseArgs — --dry-run solo es válido y no borra', () => {
  assert.strictEqual(parseArgs(['node', 'x', '--dry-run']).apply, false);
});

test('parseArgs — --incluir-ambiguos no implica borrar', () => {
  assert.strictEqual(parseArgs(['node', 'x', '--incluir-ambiguos']).apply, false);
  assert.strictEqual(
    parseArgs(['node', 'x', '--incluir-ambiguos']).incluirAmbiguos,
    true,
  );
});
