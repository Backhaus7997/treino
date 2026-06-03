/**
 * Single source of truth for exercise → videoUrl mapping.
 *
 * Used by both `seed_workout_catalog.js` (catalog seed) and
 * `backfill_exercise_videos.js` (one-shot prod backfill).
 *
 * Format: { exerciseId: 'https://firebasestorage.googleapis.com/...' }
 *
 * Videos are user-curated 3D muscle-highlight animations (matching the
 * reference Pinterest style — gray-white 3D mannequin with the active
 * muscle highlighted in red/orange over a dark background). Hosted in our
 * Firebase Storage bucket at `exercises/videos/{exerciseId}.mp4`.
 *
 * The ExerciseVideoPlayer widget detects Firebase Storage URLs and renders
 * a native inline VideoPlayer with play/pause controls (no redirect, no
 * external browser).
 *
 * Workflow per video:
 *   1. Download MP4 (yt-dlp from Pinterest pin URL)
 *   2. Upload to Firebase Storage under exercises/videos/{exerciseId}.mp4
 *   3. Copy the access token from the Firebase Storage object detail panel
 *   4. Add the entry below (URL is reconstructed from the token)
 *   5. Run scripts/backfill_exercise_videos.js to stamp Firestore docs
 *
 * Unmapped exercises (currently `hanging-leg-raise` and `hammer-curl`)
 * stay without the field — the player falls back to the exercise PNG
 * illustration at assets/exercises/{id}.png. Add them here when sourced.
 */

'use strict';

// Bucket + path are constant across the catalog. Only the token varies per
// upload — kept in this map for easy review/swap. Reconstructed inline below
// to keep entries readable and short.
const BUCKET = 'treino-dev.firebasestorage.app';
const PATH_PREFIX =
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/exercises%2Fvideos%2F`;

function url(filename, token) {
  return `${PATH_PREFIX}${filename}?alt=media&token=${token}`;
}

const videoMap = Object.freeze({
  // ── Pecho ───────────────────────────────────────────────────────────────
  'bench-press': url(
    'bench-press.mp4',
    '32161805-5de1-417e-80fd-eaa736e47463',
  ),
  'incline-dumbbell-press': url(
    'incline-dumbbell-press.mp4',
    'a8d9b321-0490-4958-b1f3-71c3554d53f9',
  ),
  'cable-fly': url(
    'cable-fly.mp4',
    'a8c57672-7734-495e-bc5b-a4070d1c1859',
  ),

  // ── Espalda ─────────────────────────────────────────────────────────────
  'deadlift': url(
    'deadlift.mp4',
    '44fc5a8f-64f5-4993-b744-54730373fd94',
  ),
  'barbell-row': url(
    'barbell-row.mp4',
    'fb2cdd23-fe78-4831-8bce-f60f0f0ee228',
  ),
  'pull-up': url(
    'pull-up.mp4',
    '6d86f6a9-bff6-4d92-b46a-6a9afa0b1f7c',
  ),
  'lat-pulldown': url(
    'lat-pulldown.mp4',
    '98376c3d-b355-47be-bdc3-a6355f52cfbb',
  ),
  'face-pull': url(
    'face-pull.mp4',
    'a2e91dd5-6ccc-4848-84ff-ec3be90125b7',
  ),

  // ── Hombros ─────────────────────────────────────────────────────────────
  'overhead-press': url(
    'overhead-press.mp4',
    '707b2170-edaf-40d7-ae11-ce2837c4a301',
  ),
  'lateral-raise': url(
    'lateral-raise.mp4',
    '3047942f-7399-46fb-8316-86b05454df3f',
  ),

  // ── Piernas ─────────────────────────────────────────────────────────────
  'back-squat': url(
    'back-squat.mp4',
    '2e7b5108-c2e9-483b-8b2f-31727f5e3bed',
  ),
  'leg-press': url(
    'leg-press.mp4',
    '9693077a-8050-4822-9d63-df9f622c3489',
  ),
  'leg-extension': url(
    'leg-extension.mp4',
    '82596152-cbb3-41a4-adf5-38e6a829e1df',
  ),
  'romanian-deadlift': url(
    'romanian-deadlift.mp4',
    '31fab221-1294-4b1f-a871-d91a1e6140d5',
  ),
  'leg-curl': url(
    'leg-curl.mp4',
    '39b27aa1-33a5-4146-a334-49a5d463d5e6',
  ),
  'hip-thrust': url(
    'hip-thrust.mp4',
    '5a4db326-61c5-49eb-ade3-1db4fa4b0289',
  ),
  'calf-raise': url(
    'calf-raise.mp4',
    '30662daa-cf36-4d97-982f-8c81978a845e',
  ),

  // ── Bíceps ──────────────────────────────────────────────────────────────
  'barbell-curl': url(
    'barbell-curl.mp4',
    'ae6aaf92-511a-46ad-b167-b19f668a277c',
  ),
  // 'hammer-curl': pending — user did not find a fitting Pinterest source.

  // ── Tríceps ─────────────────────────────────────────────────────────────
  'tricep-pushdown': url(
    'tricep-pushdown.mp4',
    'f6208e1f-7de0-4e51-bfe4-72248cdca3e2',
  ),
  'skull-crusher': url(
    'skull-crusher.mp4',
    '7106064e-9711-4d80-9165-2bcf144a6500',
  ),

  // ── Core ────────────────────────────────────────────────────────────────
  'plank': url(
    'plank.mp4',
    '4ffc129b-6fe3-4835-8815-fb958877080a',
  ),
  'cable-crunch': url(
    'cable-crunch.mp4',
    '1e23e168-732c-4f54-b20f-1b98e368f906',
  ),
  // 'hanging-leg-raise': pending — user did not find a fitting Pinterest source.
});

module.exports = { videoMap };
