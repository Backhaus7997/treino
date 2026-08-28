/**
 * backfill_exercise_videos.js
 *
 * One-shot idempotent backfill of the `videoUrl` field on
 * `exercises/{exerciseId}` documents. Reads the canonical map from
 * `_video_map.js` (shared with the seed script) and updates each
 * document only if the field is currently missing or different.
 *
 * Usage:
 *   cd treino  (repo root)
 *   $env:TREINO_SA_KEY = "$HOME\.config\treino\sa-key.json"
 *   node scripts/backfill_exercise_videos.js
 *
 * Idempotent — re-running is safe:
 *   [updated]  bench-press    → https://musclewiki.com/...
 *   [skipped]  back-squat     (already up to date)
 *   [unmapped] custom-id      (no entry in _video_map.js)
 *
 * After the run, a summary line shows totals.
 *
 * Source style: musclewiki.com (3D animation with muscle highlight) — matches
 * user reference Pinterest pin. ExerciseVideoPlayer opens these URLs in an
 * in-app browser.
 */

'use strict';

const { inicializarAdmin } = require('./lib/admin');
const { videoMap } = require('./_video_map.js');

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { admin } = inicializarAdmin();
const db = admin.firestore();

async function backfill() {
  const snapshot = await db.collection('exercises').get();
  console.log(`Found ${snapshot.size} exercise docs.`);

  let updated = 0;
  let skipped = 0;
  let unmapped = 0;

  for (const doc of snapshot.docs) {
    const id = doc.id;
    const data = doc.data();
    const existingUrl = data.videoUrl;
    const targetUrl = videoMap[id];

    if (!targetUrl) {
      console.log(`[unmapped] ${id}`);
      unmapped += 1;
      continue;
    }

    if (existingUrl === targetUrl) {
      console.log(`[skipped]  ${id} (already up to date)`);
      skipped += 1;
      continue;
    }

    await doc.ref.update({ videoUrl: targetUrl });
    console.log(`[updated]  ${id} → ${targetUrl}`);
    updated += 1;
  }

  console.log('---');
  console.log(`Summary: ${updated} updated, ${skipped} skipped, ${unmapped} unmapped.`);
  console.log('Total:', snapshot.size);
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
