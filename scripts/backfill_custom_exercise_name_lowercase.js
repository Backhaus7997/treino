/**
 * backfill_custom_exercise_name_lowercase.js
 *
 * #553 — Backfills the derived `nameLowercase` sort key on every doc under
 * `users/{trainerId}/customExercises/{exId}`.
 *
 * The app now derives `nameLowercase` on every create/update
 * (CustomExerciseRepository — callers never pass it) and alphabetizes "Mis
 * ejercicios" case- and accent-insensitively. Existing docs written before
 * the fix lack the field; the in-app Dart sort does not depend on it (it
 * folds the live `name`), so nothing breaks without this script — but the
 * stored data should carry the key so future server-side queries
 * (orderBy/startAt pagination) can rely on it being present everywhere.
 *
 * The normalizer is a literal JS port of `foldSearch`
 * (lib/features/workout/application/exercise_filter.dart) — the same
 * folding the exercise search uses (#209). MUST stay in lockstep with the
 * Dart source: a divergence would make the stored key disagree with what
 * the app derives on the next edit of the same doc.
 *
 * Idempotent: docs whose stored `nameLowercase` already matches are
 * skipped. Re-runs write nothing.
 *
 * Usage:
 *   # Producción (necesita $TREINO_SA_KEY, fuera del repo — ver scripts/README.md):
 *   cd scripts && node backfill_custom_exercise_name_lowercase.js           # writes
 *   cd scripts && node backfill_custom_exercise_name_lowercase.js --dry-run # logs only
 *
 *   # Emulator (no credentials — same pattern as backfill_athlete_counts.js):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_custom_exercise_name_lowercase.js
 */

'use strict';

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

const dryRun = process.argv.includes('--dry-run');

/**
 * Literal port of foldSearch (exercise_filter.dart): lowercase + strip
 * Spanish diacritics via the SAME character map — not a generic NFD strip,
 * so both sides fold identically by construction.
 */
const FOLD_FROM = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const FOLD_TO = 'aaaaaeeeeiiiiooooouuuunc';

function foldSearch(input) {
  const lower = input.toLowerCase();
  let out = '';
  for (const ch of lower) {
    const idx = FOLD_FROM.indexOf(ch);
    out += idx >= 0 ? FOLD_TO[idx] : ch;
  }
  return out;
}

(async () => {
  const snap = await db.collectionGroup('customExercises').get();
  console.log(`Found ${snap.size} customExercises doc(s).`);
  if (dryRun) console.log('(dry-run: no writes will be issued)');
  console.log('');

  let updated = 0;
  let alreadyOk = 0;
  let skippedNoName = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (typeof data.name !== 'string') {
      console.warn(`${doc.ref.path}: no string name — skipped`);
      skippedNoName++;
      continue;
    }

    const nameLowercase = foldSearch(data.name);
    if (data.nameLowercase === nameLowercase) {
      alreadyOk++;
      continue;
    }

    console.log(
      `${doc.ref.path}: "${data.name}" -> nameLowercase "${nameLowercase}"` +
      (dryRun ? ' (dry-run)' : ''),
    );

    if (!dryRun) {
      await doc.ref.set({ nameLowercase }, { merge: true });
    }
    updated++;
  }

  console.log('');
  console.log(
    `Done. ${updated} updated, ${alreadyOk} already ok, ` +
    `${skippedNoName} without name (skipped).`,
  );
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
