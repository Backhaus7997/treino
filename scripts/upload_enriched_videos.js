/**
 * upload_enriched_videos.js
 *
 * Sube a Firebase Storage los clips de demostración (hoy en Google Drive) de
 * los 793 ejercicios de docs/video-catalog-audit/enriched-catalog.json y
 * escribe la `videoUrl` de Storage DE VUELTA en ese mismo JSON (no toca
 * Firestore — el import posterior ya lleva la videoUrl adentro).
 *
 * Pipeline por ejercicio:
 *   1. descarga el clip de Drive (campo _driveFileId)
 *   2. lo sube a Storage en exerciseVideos/{id}.mp4
 *   3. escribe la download URL en el campo videoUrl del JSON
 *
 * Idempotente: saltea ejercicios que ya tienen videoUrl salvo --force.
 * Guarda el JSON tras cada subida (sobrevive a una interrupción).
 *
 * Uso:
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json \
 *   NODE_PATH=functions/node_modules \
 *   node scripts/upload_enriched_videos.js [--limit=N] [--only=id1,id2] [--force] [--dry-run]
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { randomUUID } = require('crypto');
const admin = require('firebase-admin');

const BUCKET = 'treino-dev.firebasestorage.app';
const CATALOG = path.resolve(__dirname, '../docs/video-catalog-audit/enriched-catalog.json');

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const FORCE = args.includes('--force');
const limitArg = args.find((a) => a.startsWith('--limit='));
const onlyArg = args.find((a) => a.startsWith('--only='));
const LIMIT = limitArg ? parseInt(limitArg.split('=')[1], 10) : Infinity;
const ONLY = onlyArg ? new Set(onlyArg.split('=')[1].split(',').map((s) => s.trim())) : null;

function downloadDrive(fileId, dest) {
  execFileSync('curl', ['-sL', '-o', dest, `https://drive.google.com/uc?export=download&id=${fileId}`]);
  const stat = fs.statSync(dest);
  if (stat.size < 10000) throw new Error(`descarga muy chica (${stat.size} bytes) — probablemente no es el video`);
  const head = fs.readFileSync(dest).slice(4, 8).toString('ascii');
  if (head !== 'ftyp') throw new Error(`no es MP4 (magic='${head}')`);
  return stat.size;
}

async function main() {
  const catalog = JSON.parse(fs.readFileSync(CATALOG, 'utf8'));

  let bucket = null;
  if (!DRY) {
    admin.initializeApp({ storageBucket: BUCKET });
    bucket = admin.storage().bucket();
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'exvid-'));
  let done = 0;
  let skipped = 0;
  let failed = 0;
  const failures = [];

  for (const ex of catalog) {
    if (done >= LIMIT) break;
    if (ONLY && !ONLY.has(ex.id)) continue;
    if (ex.videoUrl && !FORCE) { skipped++; continue; }
    if (!ex._driveFileId) { skipped++; continue; }

    const dest = `exerciseVideos/${ex.id}.mp4`;
    if (DRY) {
      console.log(`[dry] ${ex.id} <- Drive ${ex._driveFileId} -> ${dest}`);
      done++;
      continue;
    }

    const local = path.join(tmpDir, `${ex.id}.mp4`);
    try {
      const size = downloadDrive(ex._driveFileId, local);
      const token = randomUUID();
      await bucket.upload(local, {
        destination: dest,
        metadata: {
          contentType: 'video/mp4',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      ex.videoUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
      fs.unlinkSync(local);
      // guardado incremental
      fs.writeFileSync(CATALOG, JSON.stringify(catalog, null, 2));
      done++;
      console.log(`✓ ${done}  ${ex.id}  (${(size / 1024).toFixed(0)} KB)`);
    } catch (e) {
      failed++;
      failures.push({ id: ex.id, fileId: ex._driveFileId, error: e.message });
      console.warn(`✗ ${ex.id}: ${e.message}`);
    }
  }

  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log(`\nSubidos: ${done} | Salteados (ya tenían / sin fileId): ${skipped} | Fallidos: ${failed}`);
  if (failures.length) {
    fs.writeFileSync(
      path.resolve(__dirname, '../docs/video-catalog-audit/video-upload-failures.json'),
      JSON.stringify(failures, null, 2),
    );
    console.log('Fallidos guardados en docs/video-catalog-audit/video-upload-failures.json');
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
