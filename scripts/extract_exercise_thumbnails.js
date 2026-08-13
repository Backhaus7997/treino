#!/usr/bin/env node
/**
 * extract_exercise_thumbnails.js
 *
 * Genera un thumbnail identificatorio por ejercicio extrayendo un frame del
 * video que ya tiene cada uno (mismos mp4 de Storage que reproduce la app).
 * Resuelve el gap de #542: el catálogo (793) no tiene ningún campo de imagen.
 *
 * Dos fases:
 *
 *   FASE A — extracción (sin credenciales; las URLs de video son públicas con token):
 *     node extract_exercise_thumbnails.js --extract \
 *       --catalog=/path/docs/video-catalog-audit/enriched-catalog.json \
 *       --out=/path/thumbs
 *
 *   FASE B — upload + patch Firestore (requiere sa-key o emulador):
 *     GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json \
 *       node extract_exercise_thumbnails.js --upload --thumbs=/path/thumbs [--dry-run]
 *
 * Detalles de la fase A:
 *   - Frame al 50% de la duración (el primer frame suele ser pose neutra).
 *     Overrides puntuales via --overrides=<csv> con lineas `id,fraccion` (0..1)
 *     para ejercicios donde el frame del medio no identifica bien (ej. bisagras).
 *   - Recorte cuadrado con sesgo hacia arriba (y = 35% del excedente) para
 *     dejar afuera el watermark del borde inferior y centrar el torso.
 *   - 256x256 JPEG (~8-15 KB). Resumible: saltea los .jpg ya generados.
 *   - Reporta fallas en <out>/failures.csv y resumen al final.
 *
 * Fase B (patrón backfill_athlete_counts.js post-#490: nunca sa-key incondicional):
 *   - Contra emulador: FIRESTORE_EMULATOR_HOST seteado -> no exige credenciales.
 *   - Contra prod: exige GOOGLE_APPLICATION_CREDENTIALS.
 *   - Sube exercises/thumbs/{id}.jpg al bucket con download token (mismo esquema
 *     que upload_enriched_videos.js) y setea `thumbnailUrl` en exercises/{id}.
 *   - La app ignora campos desconocidos en fromJson: escribir thumbnailUrl es
 *     seguro antes de que exista el cambio de UI que lo consuma.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync, execFile } = require('child_process');

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const opt = (name, dflt) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : dflt;
};

const CONCURRENCY = parseInt(opt('concurrency', '4'), 10);
const BUCKET = 'treino-dev.firebasestorage.app';

// ── Fase A ───────────────────────────────────────────────────────────────────

async function extract() {
  const catalogPath = opt('catalog');
  const outDir = opt('out');
  if (!catalogPath || !outDir) {
    console.error('Faltan --catalog y/o --out');
    process.exit(1);
  }
  fs.mkdirSync(outDir, { recursive: true });

  const raw = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
  const list = Array.isArray(raw) ? raw : raw.exercises;

  // Overrides de fracción de frame por id (csv `id,fraccion`)
  const overrides = new Map();
  const ovPath = opt('overrides');
  if (ovPath && fs.existsSync(ovPath)) {
    for (const line of fs.readFileSync(ovPath, 'utf8').split('\n')) {
      const [id, frac] = line.trim().split(',');
      if (id && frac && !Number.isNaN(parseFloat(frac))) overrides.set(id, parseFloat(frac));
    }
  }

  const todo = list.filter((e) => e && e.id && e.videoUrl);
  const sinVideo = list.filter((e) => e && e.id && !e.videoUrl).map((e) => e.id);
  console.log(`catálogo: ${list.length} · con video: ${todo.length} · sin video: ${sinVideo.length}`);

  const failures = [];
  let done = 0;
  let skipped = 0;

  async function one(e) {
    const jpg = path.join(outDir, `${e.id}.jpg`);
    if (fs.existsSync(jpg)) { skipped++; return; }
    const tmp = path.join(outDir, `.${e.id}.mp4`);
    try {
      execFileSync('curl', ['-sL', '--max-time', '90', '-o', tmp, e.videoUrl]);
      const dur = parseFloat(
        execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', tmp])
          .toString().trim(),
      ) || 4;
      const frac = overrides.get(e.id) ?? 0.5;
      const ts = Math.max(0.1, dur * frac).toFixed(2);
      execFileSync('ffmpeg', [
        '-nostdin', '-y', '-v', 'error',
        '-ss', String(ts), '-i', tmp, '-frames:v', '1',
        // cuadrado con sesgo hacia arriba (35% del excedente vertical) — esquiva
        // el watermark inferior y centra el torso
        '-vf', "crop=w='min(iw,ih)':h='min(iw,ih)':x='(iw-min(iw,ih))/2':y='(ih-min(iw,ih))*0.35',scale=256:256",
        '-q:v', '4', jpg,
      ]);
      done++;
      if ((done + skipped) % 50 === 0) console.log(`  progreso: ${done + skipped}/${todo.length}`);
    } catch (err) {
      failures.push(`${e.id},${String(err.message || err).split('\n')[0].replace(/,/g, ';')}`);
    } finally {
      fs.rmSync(tmp, { force: true });
    }
  }

  // pool simple de N workers
  const queue = [...todo];
  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (queue.length) await one(queue.shift());
    }),
  );

  if (failures.length) fs.writeFileSync(path.join(outDir, 'failures.csv'), failures.join('\n') + '\n');
  if (sinVideo.length) fs.writeFileSync(path.join(outDir, 'sin-video.txt'), sinVideo.join('\n') + '\n');
  console.log(`\n✓ extraídos: ${done} · salteados (ya existían): ${skipped} · fallas: ${failures.length}`);
  if (failures.length) console.log(`  detalle: ${path.join(outDir, 'failures.csv')}`);
}

// ── Fase B ───────────────────────────────────────────────────────────────────

async function upload() {
  const thumbsDir = opt('thumbs');
  if (!thumbsDir) {
    console.error('Falta --thumbs');
    process.exit(1);
  }
  const dryRun = flag('dry-run');
  const onEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

  if (!onEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      'Contra producción hace falta GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json\n' +
      '(o FIRESTORE_EMULATOR_HOST para correr contra el emulador).',
    );
    process.exit(1);
  }

  const admin = require('firebase-admin');
  admin.initializeApp({ storageBucket: BUCKET });
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const jpgs = fs.readdirSync(thumbsDir).filter((f) => f.endsWith('.jpg'));
  console.log(`thumbs a subir: ${jpgs.length} · destino: ${onEmulator ? 'EMULADOR' : `prod (${BUCKET})`}${dryRun ? ' · DRY-RUN' : ''}`);

  let ok = 0;
  const failures = [];
  for (const f of jpgs) {
    const id = f.replace(/\.jpg$/, '');
    try {
      const snap = await db.collection('exercises').doc(id).get();
      if (!snap.exists) { failures.push(`${id},doc no existe en exercises`); continue; }
      if (dryRun) { ok++; continue; }

      const token = crypto.randomUUID();
      const dest = `exercises/thumbs/${id}.jpg`;
      await bucket.upload(path.join(thumbsDir, f), {
        destination: dest,
        metadata: {
          contentType: 'image/jpeg',
          cacheControl: 'public, max-age=31536000, immutable',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      const url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
      await snap.ref.update({ thumbnailUrl: url });
      ok++;
      if (ok % 50 === 0) console.log(`  progreso: ${ok}/${jpgs.length}`);
    } catch (err) {
      failures.push(`${id},${String(err.message || err).split('\n')[0].replace(/,/g, ';')}`);
    }
  }

  if (failures.length) fs.writeFileSync(path.join(thumbsDir, 'upload-failures.csv'), failures.join('\n') + '\n');
  console.log(`\n✓ ${dryRun ? 'verificados' : 'subidos + patcheados'}: ${ok} · fallas: ${failures.length}`);
  if (failures.length) console.log(`  detalle: ${path.join(thumbsDir, 'upload-failures.csv')}`);
}

(async () => {
  if (flag('extract')) await extract();
  else if (flag('upload')) await upload();
  else {
    console.error('Usá --extract o --upload (ver header del archivo).');
    process.exit(1);
  }
})();
