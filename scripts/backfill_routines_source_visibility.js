/**
 * backfill_routines_source_visibility.js
 *
 * Backfill script: ensures every doc in the `routines` collection has explicit
 * `source` and `visibility` fields. Fixes a latent bug exposed when the per-doc
 * `routines` read rule from coach-plans-mobile (PR #64) was first deployed —
 * `listAll()` queries without a `where('visibility', ...)` filter were rejected
 * by Firestore because the rule could not be proven for all matched docs.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * WHAT IT DOES
 * ────────────────────────────────────────────────────────────────────────────
 * For each routine doc:
 *   - If `source` is missing → set `source: 'system'` (matches the freezed
 *     model default `RoutineSource.system` for plantillas seedeadas in Fase 2)
 *   - If `visibility` is missing → set `visibility: 'public'` (matches the
 *     freezed model default `RoutineVisibility.public`)
 *   - Docs with both fields already set are skipped (no write performed).
 *
 * The new explicit `visibility` field lets the plantillas screen issue
 * `where('visibility', '==', 'public')` queries that satisfy the per-doc
 * rule and Firestore's list-query symbolic check.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE (from project root)
 * ────────────────────────────────────────────────────────────────────────────
 * 1. Install dependencies:
 *      npm install firebase-admin
 *
 * 2. Credenciales (#834). La clave NO va adentro del repo: se guarda afuera y
 *    la ruta sale de `$TREINO_SA_KEY`. Toda ruta adentro de un árbol de git
 *    —incluido cualquier worktree— se rechaza.
 *      mkdir -p ~/.config/treino && chmod 600 ~/.config/treino/sa-key.json
 *      export TREINO_SA_KEY="~/.config/treino/sa-key.json"
 *    Detalle y migración: scripts/README.md → "Credenciales (#834)".
 *
 * 3. Run:
 *      node scripts/backfill_routines_source_visibility.js
 *
 *    Against the local emulator no key is needed — step 2 is skippable:
 *      FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *      node scripts/backfill_routines_source_visibility.js
 *
 * 4. Verify: check logs for "Backfill complete" and the count of docs
 *    updated vs skipped.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SAFETY
 * ────────────────────────────────────────────────────────────────────────────
 * - Uses `{ merge: true }` — existing fields are NEVER overwritten.
 * - Idempotent. Safe to re-run any number of times.
 * - Halts on any Firestore error — fix the error and re-run.
 * - Processes routines in pages of 500 (Firestore WriteBatch limit).
 * - Never run from client-side code — requires firebase-admin privileges.
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();

const db = admin.firestore();

async function backfill() {
  const routinesRef = db.collection('routines');

  let lastDoc = null;
  let processedCount = 0;
  let updatedCount = 0;
  let skippedCount = 0;
  const PAGE_SIZE = 500; // Firestore WriteBatch limit

  console.log('Starting backfill of routines source + visibility...');

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let query = routinesRef.limit(PAGE_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let writesInBatch = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const patch = {};

      if (!('source' in data)) {
        patch.source = 'system';
      }
      if (!('visibility' in data)) {
        patch.visibility = 'public';
      }

      processedCount++;

      if (Object.keys(patch).length === 0) {
        skippedCount++;
        continue;
      }

      batch.set(doc.ref, patch, { merge: true });
      writesInBatch++;
      updatedCount++;
    }

    if (writesInBatch > 0) {
      await batch.commit();
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    if (processedCount % 100 === 0 || snapshot.docs.length < PAGE_SIZE) {
      console.log(
        `Processed ${processedCount} routines (updated: ${updatedCount}, skipped: ${skippedCount})...`,
      );
    }
  }

  console.log(
    `Backfill complete. Total: ${processedCount} | Updated: ${updatedCount} | Skipped (already had both fields): ${skippedCount}`,
  );
}

backfill().catch((err) => {
  console.error('Backfill FAILED:', err);
  process.exit(1);
});
