/**
 * upload_drive_exercise_videos.js
 *
 * Takes the demonstration clips from the shared Google Drive and attaches them
 * to our catalogue exercises so each one plays INLINE in the app.
 *
 * Pipeline per exercise:
 *   1. download the recommended clip from Drive (public file id)
 *   2. upload it to Firebase Storage at `exerciseVideos/{id}.mp4`
 *   3. write the Storage download URL into `exercises/{id}.videoUrl`
 *
 * Source list: docs/video-catalog-audit/video-recommendations-high-confidence.csv
 * (one recommended clip per exercise, score 1.000).
 *
 * Idempotent: skips an exercise that already has a Storage-hosted video unless
 * --force is passed. Only touches docs that actually exist in `exercises`.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/upload_drive_exercise_videos.js [flags]
 * Flags:
 *   --dry-run        show what would happen, write NOTHING
 *   --limit=N        process at most N exercises (pilot)
 *   --only=id1,id2   process only these exercise ids
 *   --force          overwrite an existing videoUrl
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { randomUUID } = require('crypto');
const admin = require('firebase-admin');

const BUCKET = 'treino-dev.firebasestorage.app';

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const FORCE = args.includes('--force');
const limitArg = args.find((a) => a.startsWith('--limit='));
const onlyArg = args.find((a) => a.startsWith('--only='));
const LIMIT = limitArg ? parseInt(limitArg.split('=')[1], 10) : Infinity;
const ONLY = onlyArg ? new Set(onlyArg.split('=')[1].split(',').map((s) => s.trim())) : null;

admin.initializeApp({ storageBucket: BUCKET });
const db = admin.firestore();
const bucket = admin.storage().bucket();

const FROM_MATCHES = args.includes('--from-matches');

function loadRows() {
  if (FROM_MATCHES) {
    // Full-coverage matches produced by match_drive_videos_to_catalog.js.
    return require(path.join('..', 'docs', 'video-catalog-audit', 'video-matches-full.json'))
      .map((m) => ({ id: m.id, filename: m.filename, fileId: m.fileId }));
  }
  const csv = fs.readFileSync(
    path.join(__dirname, '..', 'docs', 'video-catalog-audit', 'video-recommendations-high-confidence.csv'),
    'utf8',
  );
  const lines = csv.trim().split('\n');
  const header = lines[0].split(',');
  const iId = header.indexOf('exercise_id');
  const iVid = header.indexOf('recommended_video');
  const iFid = header.indexOf('drive_file_id');
  return lines.slice(1).map((line) => {
    const c = line.split(',');
    return { id: c[iId].trim(), filename: c[iVid].trim(), fileId: c[iFid].trim() };
  });
}

function downloadDrive(fileId, dest) {
  // Small public clips download directly from the uc endpoint (curl follows
  // the redirect). Validate it's really an MP4, not an HTML interstitial.
  execFileSync('curl', ['-sL', '-o', dest, `https://drive.google.com/uc?export=download&id=${fileId}`]);
  const stat = fs.statSync(dest);
  if (stat.size < 10000) throw new Error(`download too small (${stat.size} bytes) — likely not the video`);
  const head = fs.readFileSync(dest).slice(4, 8).toString('ascii');
  if (head !== 'ftyp') throw new Error(`not an MP4 (magic='${head}')`);
  return stat.size;
}

async function uploadToStorage(localPath, id) {
  const token = randomUUID();
  const dest = `exerciseVideos/${id}.mp4`;
  await bucket.upload(localPath, {
    destination: dest,
    metadata: {
      contentType: 'video/mp4',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
}

async function run() {
  let rows = loadRows();
  if (ONLY) rows = rows.filter((r) => ONLY.has(r.id));

  console.log(`${DRY ? '[DRY RUN] ' : ''}candidates: ${rows.length}`);
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'drivevid-'));

  let done = 0, skippedMissing = 0, skippedHasVideo = 0, failed = 0;
  for (const r of rows) {
    if (done >= LIMIT) break;
    const ref = db.collection('exercises').doc(r.id);
    const snap = await ref.get();
    if (!snap.exists) { console.log(`[missing-doc] ${r.id}`); skippedMissing += 1; continue; }
    const existing = snap.data().videoUrl;
    if (existing && existing.includes('firebasestorage') && !FORCE) {
      console.log(`[has-video]   ${r.id} (use --force to replace)`); skippedHasVideo += 1; continue;
    }

    try {
      const local = path.join(tmpDir, `${r.id}.mp4`);
      const size = downloadDrive(r.fileId, local);
      if (DRY) {
        console.log(`[would-do]    ${r.id}  ← ${r.filename} (${(size / 1024).toFixed(0)} KB)`);
        done += 1; continue;
      }
      const url = await uploadToStorage(local, r.id);
      await ref.update({ videoUrl: url });
      console.log(`[uploaded]    ${r.id}  ← ${r.filename}\n              ${url}`);
      done += 1;
    } catch (e) {
      console.log(`[FAILED]      ${r.id}: ${e.message}`);
      failed += 1;
    }
  }

  console.log('---');
  console.log(`${DRY ? 'would process' : 'uploaded'}: ${done} | skipped (no doc): ${skippedMissing} | skipped (has video): ${skippedHasVideo} | failed: ${failed}`);
  process.exit(0);
}

run().catch((e) => { console.error(e); process.exit(1); });
