/**
 * test/audit_forged_trainer_links.test.js
 *
 * `clasificar()` de `audit_forged_trainer_links.js`: en qué grupo cae un
 * vínculo según el doc de usuario de su `trainerId`. Sin red, sin
 * `firebase-admin`.
 *
 *   node --test scripts/test/
 *
 * Por qué existe: esa función decide QUÉ SE BORRA en producción, y los dos
 * errores posibles duelen en direcciones opuestas. Clasificar de más borra el
 * vínculo de un PF real y le corta el servicio a él y a su alumno; clasificar
 * de menos deja vivo un vínculo forjado, que apaga el paywall del alumno y le
 * da a un desconocido lectura de sus sesiones y mediciones.
 *
 * El grupo AMBIGUO existe porque el `role` NO es hermético para los docs
 * viejos: `paywallEnforcedFor` en `firestore.rules` ya falla ABIERTO ante un
 * rol ausente, y `promote-link.ts` toma la misma decisión por el mismo motivo.
 * Un rol que falta es un doc legacy, no un atacante — el signup público escribe
 * `role: 'athlete'` explícito.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  clasificar,
  desglosePor,
  parseArgs,
  contarBorradosReales,
  paginasDe,
} = require('../audit_forged_trainer_links');

// ── clasificar ──────────────────────────────────────────────────────────────

test('clasificar — role athlete explícito → trucho', () => {
  assert.strictEqual(clasificar({ exists: true, role: 'athlete' }), 'trucho');
});

test('clasificar — role trainer → ok', () => {
  assert.strictEqual(clasificar({ exists: true, role: 'trainer' }), 'ok');
});

test('clasificar — un rol desconocido tampoco es trainer → trucho', () => {
  assert.strictEqual(clasificar({ exists: true, role: 'admin' }), 'trucho');
});

// Las tres formas de "no me consta". Ninguna se borra: ver el header.
test('clasificar — sin doc de usuario → ambiguo', () => {
  assert.strictEqual(clasificar({ exists: false }), 'ambiguo');
  assert.strictEqual(clasificar(undefined), 'ambiguo');
});

test('clasificar — doc sin campo role → ambiguo, NO trucho', () => {
  assert.strictEqual(clasificar({ exists: true }), 'ambiguo');
  assert.strictEqual(clasificar({ exists: true, role: undefined }), 'ambiguo');
  assert.strictEqual(clasificar({ exists: true, role: null }), 'ambiguo');
  assert.strictEqual(clasificar({ exists: true, role: '' }), 'ambiguo');
});

// ── parseArgs: la compuerta ─────────────────────────────────────────────────

test('parseArgs — el default NO escribe', () => {
  assert.strictEqual(parseArgs(['node', 'x']).apply, false);
});

test('parseArgs — --apply habilita el borrado', () => {
  assert.strictEqual(parseArgs(['node', 'x', '--apply']).apply, true);
});

// La regla del repo: ante flags en conflicto gana la que NO destruye. En
// `cleanup_rejected_links.js` esto fue un bug real —`--dry-run` estaba en la
// allowlist y nunca se leía, así que `--apply --dry-run` BORRABA—, así que acá
// se fija desde el primer día.
test('parseArgs — --apply + --dry-run: gana el que no destruye', () => {
  const r = parseArgs(['node', 'x', '--apply', '--dry-run']);
  assert.strictEqual(r.apply, false);
  assert.strictEqual(r.dryRunExplicito, true);
});

test('parseArgs — --ids no habilita escrituras', () => {
  const r = parseArgs(['node', 'x', '--ids']);
  assert.strictEqual(r.apply, false);
  assert.strictEqual(r.ids, true);
});

// ── helpers de reporte y de borrado ─────────────────────────────────────────

test('desglosePor — agrupa y marca el faltante', () => {
  const d = desglosePor(
    [{ status: 'active' }, { status: 'active' }, { status: 'pending' }, {}],
    'status',
  );
  assert.deepStrictEqual(d, [
    ['active', 2],
    ['pending', 1],
    ['(ninguno)', 1],
  ]);
});

test('paginasDe — parte en páginas del tamaño pedido', () => {
  assert.deepStrictEqual(paginasDe([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepStrictEqual(paginasDe([], 500), []);
});

// Cuenta borrados REALES y no operaciones emitidas: `batch.delete()` sobre un
// doc que ya no está resuelve OK, así que contar intentos informa de más.
test('contarBorradosReales — ignora los que ya no estaban', () => {
  const chunk = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
  assert.strictEqual(contarBorradosReales(chunk, new Set(['a', 'c'])), 2);
  assert.strictEqual(contarBorradosReales(chunk, new Set()), 0);
});
