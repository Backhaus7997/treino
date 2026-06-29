/**
 * apply_catalog_video_fill.js
 *
 * Two modes (read-only unless --apply):
 *   --add-safe    attach a Drive clip where movement+equipment match exactly
 *                 (light synonym/plural normalisation). Equipment unchanged.
 *   --fill-empty  ONLY for exercises with NO equipment defined (no equip token
 *                 in the id AND empty equipment field): match by movement and
 *                 set the equipment the clip indicates. Never overwrites a
 *                 defined equipment.
 *
 * Run: GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/apply_catalog_video_fill.js --add-safe --fill-empty [--apply]
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { randomUUID } = require('crypto');
const admin = require('firebase-admin');

const BUCKET = 'treino-dev.firebasestorage.app';
const APPLY = process.argv.includes('--apply');
const DO_ADD = process.argv.includes('--add-safe');
const DO_FILL = process.argv.includes('--fill-empty');

admin.initializeApp({ storageBucket: BUCKET });
const db = admin.firestore();
const bucket = admin.storage().bucket();

const FOLDER_EQUIP = { dumbbells: 'dumbbell', barbell: 'barbell', bodyweight: 'bodyweight', kettlebells: 'kettlebell', cables: 'cable', band: 'band', machine: 'machine', plate: 'plate', 'smith-machine': 'smith-machine', 'medicine-ball': 'medicine-ball', medicineball: 'medicine-ball', trx: 'suspension', 'bosu-ball': 'bosu-ball', vitruvian: 'machine', cardio: 'cardio' };
const EQUIP_JSON = { barbell: 'barra', dumbbell: 'mancuerna', machine: 'maquina', cable: 'cable', band: 'banda', bodyweight: 'peso_corporal', kettlebell: 'otro', plate: 'otro', 'smith-machine': 'maquina', suspension: 'otro', 'medicine-ball': 'otro', 'bosu-ball': 'otro', cardio: 'cardio' };
const SKIP_FOLDERS = new Set(['recovery', 'yoga', 'stretches', 'pilates']);
const ID_EQUIP_SUFFIXES = ['smith-machine', 'trap-bar', 'medicine-ball', 'bosu-ball', 'barbell', 'dumbbell', 'dumbbells', 'machine', 'cable', 'band', 'bodyweight', 'suspension', 'kettlebell', 'plate'];
const ID_EQUIP_PREFIXES = ['barbell', 'dumbbell', 'cable', 'band', 'machine', 'kettlebell', 'plate'];
const EQUIP_NORM = { dumbbells: 'dumbbell', 'trap-bar': 'barbell' };
const ne = (e) => EQUIP_NORM[e] || e;
const isView = (t) => /^(side|front)(_.*)?$/.test(t);
const SYN = { bicep: 'biceps', tricep: 'triceps', ab: 'abs', flys: 'fly', flyes: 'fly', crossovers: 'crossover' };
function normMovement(tokens) {
  const out = [];
  for (let t of tokens) { t = SYN[t] || t; if (t.length > 3 && t.endsWith('s') && !['press', 'triceps', 'biceps', 'abs'].includes(t)) t = t.replace(/s$/, ''); out.push(t); }
  return out.filter(Boolean).sort().join('-');
}
function exerciseKey(id) {
  let equip = null, movement = id; // null = no equipment token in id
  for (const suf of ID_EQUIP_SUFFIXES) { if (id !== suf && id.endsWith('-' + suf)) { equip = ne(suf); movement = id.slice(0, -(suf.length + 1)); break; } }
  if (!equip) for (const pre of ID_EQUIP_PREFIXES) { if (id.startsWith(pre + '-')) { equip = ne(pre); movement = id.slice(pre.length + 1); break; } }
  return { equip, mvt: normMovement(movement.split('-').filter(Boolean)) };
}
function videoKey(v) {
  const folder = v.folder.toLowerCase();
  const equip = ne(FOLDER_EQUIP[folder] || folder);
  let toks = v.title.replace(/\.mp4$/i, '').split('-').map((t) => t.toLowerCase());
  if (toks[0] === 'female' || toks[0] === 'male') toks.shift();
  if (toks.length && isView(toks[toks.length - 1])) toks.pop();
  if (toks.length && toks[0] === folder) toks.shift();
  if (toks.length && (toks[0] === FOLDER_EQUIP[folder] || toks[0] === equip)) toks.shift();
  return { equip, mvt: normMovement(toks), view: /side/.test(v.title.toLowerCase()) ? 'side' : 'front' };
}
async function uploadVideo(fileId, id) {
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'fill-')), `${id}.mp4`);
  execFileSync('curl', ['-sL', '-o', tmp, `https://drive.google.com/uc?export=download&id=${fileId}`]);
  if (fs.statSync(tmp).size < 10000 || fs.readFileSync(tmp).slice(4, 8).toString('ascii') !== 'ftyp') throw new Error('bad download');
  const token = randomUUID();
  const dest = `exerciseVideos/${id}.mp4`;
  await bucket.upload(tmp, { destination: dest, metadata: { contentType: 'video/mp4', metadata: { firebaseStorageDownloadTokens: token } } });
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
}

(async () => {
  const drive = require(path.join('..', 'docs', 'video-catalog-audit', 'drive-videos.json'));
  const videos = Array.isArray(drive) ? drive : (drive.videos || Object.values(drive).find(Array.isArray));
  const byEquipMvt = new Map(); // `${equip}|${mvt}` → {side,front} filenames+ids
  const byMvt = new Map();      // mvt → [{equip,view,fileId,filename}]
  for (const v of videos) {
    if (SKIP_FOLDERS.has(v.folder.toLowerCase())) continue;
    const k = videoKey(v); if (!k.mvt) continue;
    const slot = byEquipMvt.get(`${k.equip}|${k.mvt}`) || {}; if (!slot[k.view]) slot[k.view] = { fileId: v.id, filename: v.title }; byEquipMvt.set(`${k.equip}|${k.mvt}`, slot);
    const arr = byMvt.get(k.mvt) || []; arr.push({ equip: k.equip, view: k.view, fileId: v.id, filename: v.title }); byMvt.set(k.mvt, arr);
  }

  const snap = await db.collection('exercises').get();
  const add = [], fill = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.videoUrl && d.videoUrl.includes('firebasestorage')) continue;
    const ek = exerciseKey(doc.id);
    if (ek.equip) {
      if (!DO_ADD) continue;
      const slot = byEquipMvt.get(`${ek.equip}|${ek.mvt}`);
      if (slot) { const p = slot.side || slot.front; add.push({ id: doc.id, name: d.name, fileId: p.fileId, filename: p.filename }); }
    } else {
      if (!DO_FILL) continue;
      const hasEquipField = d.equipment != null && d.equipment !== '';
      if (hasEquipField) continue; // never overwrite a defined equipment
      const cands = byMvt.get(ek.mvt);
      if (!cands || !cands.length) continue;
      const p = cands.find((c) => c.view === 'side') || cands[0];
      fill.push({ id: doc.id, name: d.name, fileId: p.fileId, filename: p.filename, equip: p.equip, equipJson: EQUIP_JSON[p.equip] || 'otro' });
    }
  }

  console.log(`${APPLY ? '[APPLY]' : '[DRY]'}  add-safe: ${add.length}  |  fill-empty: ${fill.length}`);
  if (DO_ADD) { console.log('--- ADD-SAFE ---'); add.forEach((p) => console.log(`  ${p.id.padEnd(34)} ← ${p.filename}`)); }
  if (DO_FILL) { console.log('--- FILL-EMPTY (id | name | equipo nuevo | video) ---'); fill.forEach((p) => console.log(`  ${p.id.padEnd(28)} ${(p.name || '').padEnd(28)} ${p.equipJson.padEnd(12)} ${p.filename}`)); }
  fs.writeFileSync(path.join(__dirname, '..', 'docs', 'video-catalog-audit', 'catalog-fill-empty.csv'),
    ['exercise_id,name,proposed_equipment,proposed_video', ...fill.map((p) => `${p.id},${(p.name || '').replace(/,/g, ' ')},${p.equipJson},${p.filename}`)].join('\n'));

  if (APPLY) {
    let ok = 0, fail = 0;
    for (const p of add) { try { const url = await uploadVideo(p.fileId, p.id); await db.collection('exercises').doc(p.id).update({ videoUrl: url }); ok++; } catch (e) { console.log(`[FAILED] ${p.id}: ${e.message}`); fail++; } }
    if (DO_FILL) for (const p of fill) { try { const url = await uploadVideo(p.fileId, p.id); await db.collection('exercises').doc(p.id).update({ videoUrl: url, equipment: p.equipJson }); ok++; } catch (e) { console.log(`[FAILED] ${p.id}: ${e.message}`); fail++; } }
    console.log(`--- applied: ${ok} | failed: ${fail}`);
  }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
