/**
 * build_catalog_proposal.js   (READ-ONLY — writes a review CSV, no DB writes)
 *
 * Classifies every doc in `exercises` against the Drive video library, matching
 * STRICTLY by movement + equipment (light, safe synonym/plural normalisation —
 * never changes equipment to force a match). Output for human review:
 *   docs/video-catalog-audit/catalog-proposal.csv
 *
 * Status per exercise:
 *   HAS_VIDEO  already has a Drive video (leave as is)
 *   ADD_VIDEO  no video yet, but a matching clip exists → safe to attach
 *   NO_VIDEO   no clip for this exact movement+equipment (decide: keep / drop)
 *   DUPLICATE  another doc maps to the same movement+equipment
 *
 * Run: GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/build_catalog_proposal.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp({ storageBucket: 'treino-dev.firebasestorage.app' });
const db = admin.firestore();

// canonical equipment vocabulary shared by ids and Drive folders
const FOLDER_EQUIP = {
  dumbbells: 'dumbbell', barbell: 'barbell', bodyweight: 'bodyweight',
  kettlebells: 'kettlebell', cables: 'cable', band: 'band', machine: 'machine',
  plate: 'plate', 'smith-machine': 'smith-machine', 'medicine-ball': 'medicine-ball',
  medicineball: 'medicine-ball', trx: 'suspension', 'bosu-ball': 'bosu-ball',
  vitruvian: 'machine', cardio: 'cardio',
};
const SKIP_FOLDERS = new Set(['recovery', 'yoga', 'stretches', 'pilates']);
const ID_EQUIP_SUFFIXES = ['smith-machine', 'trap-bar', 'medicine-ball', 'bosu-ball', 'barbell', 'dumbbell', 'dumbbells', 'machine', 'cable', 'band', 'bodyweight', 'suspension', 'kettlebell', 'plate'];
const ID_EQUIP_PREFIXES = ['barbell', 'dumbbell', 'cable', 'band', 'machine', 'kettlebell', 'plate'];
const EQUIP_NORM = { dumbbells: 'dumbbell', 'trap-bar': 'barbell' };
const ne = (e) => EQUIP_NORM[e] || e;
const isView = (t) => /^(side|front)(_.*)?$/.test(t);
const SYN = { bicep: 'biceps', tricep: 'triceps', ab: 'abs', flys: 'fly', flyes: 'fly', crossovers: 'crossover', pushup: 'pushup', pullup: 'pullup', chinup: 'chinup', situp: 'situp' };

function normMovement(tokens) {
  const out = [];
  for (let t of tokens) {
    t = SYN[t] || t;
    if (t.length > 3 && t.endsWith('s') && !['press', 'triceps', 'biceps', 'abs'].includes(t)) t = t.replace(/s$/, '');
    out.push(t);
  }
  return out.filter(Boolean).sort().join('-');
}

function exerciseKey(id) {
  let equip = 'bodyweight', movement = id;
  for (const suf of ID_EQUIP_SUFFIXES) {
    if (id !== suf && id.endsWith('-' + suf)) { equip = ne(suf); movement = id.slice(0, -(suf.length + 1)); break; }
  }
  if (equip === 'bodyweight') {
    for (const pre of ID_EQUIP_PREFIXES) {
      if (id.startsWith(pre + '-')) { equip = ne(pre); movement = id.slice(pre.length + 1); break; }
    }
  }
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

(async () => {
  const drive = require(path.join('..', 'docs', 'video-catalog-audit', 'drive-videos.json'));
  const videos = Array.isArray(drive) ? drive : (drive.videos || Object.values(drive).find(Array.isArray));
  const index = new Map();
  for (const v of videos) {
    if (SKIP_FOLDERS.has(v.folder.toLowerCase())) continue;
    const k = videoKey(v);
    if (!k.mvt) continue;
    const key = `${k.equip}|${k.mvt}`;
    const slot = index.get(key) || {};
    if (!slot[k.view]) slot[k.view] = v.title;
    index.set(key, slot);
  }

  const snap = await db.collection('exercises').get();
  const byKey = new Map();
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const ek = exerciseKey(doc.id);
    const key = `${ek.equip}|${ek.mvt}`;
    byKey.set(key, (byKey.get(key) || 0) + 1);
    const slot = index.get(key);
    const vid = slot ? (slot.side || slot.front) : '';
    const hasVideo = !!(d.videoUrl && d.videoUrl.includes('firebasestorage'));
    rows.push({ id: doc.id, name: (d.name || '').replace(/,/g, ' '), equip: ek.equip, key, hasVideo, vid });
  }
  for (const r of rows) {
    if (r.hasVideo) r.status = 'HAS_VIDEO';
    else if (r.vid) r.status = 'ADD_VIDEO';
    else r.status = 'NO_VIDEO';
    if (byKey.get(r.key) > 1) r.dup = byKey.get(r.key);
  }
  rows.sort((a, b) => a.status.localeCompare(b.status) || a.id.localeCompare(b.id));

  const out = ['exercise_id,name,equipment,status,duplicate_count,proposed_video'];
  for (const r of rows) out.push(`${r.id},${r.name},${r.equip},${r.status},${r.dup || ''},${r.vid}`);
  fs.writeFileSync(path.join(__dirname, '..', 'docs', 'video-catalog-audit', 'catalog-proposal.csv'), out.join('\n'));

  const c = (s) => rows.filter((r) => r.status === s).length;
  const dups = rows.filter((r) => r.dup).length;
  console.log(`total: ${rows.length}`);
  console.log(`  HAS_VIDEO (ya tiene): ${c('HAS_VIDEO')}`);
  console.log(`  ADD_VIDEO (se agrega, seguro): ${c('ADD_VIDEO')}`);
  console.log(`  NO_VIDEO  (sin video en Drive): ${c('NO_VIDEO')}`);
  console.log(`  docs en grupos duplicados (mismo movimiento+equipo): ${dups}`);
  console.log('--- nuevos ADD_VIDEO (muestra) ---');
  for (const r of rows.filter((r) => r.status === 'ADD_VIDEO').slice(0, 20)) console.log(`  ${r.id.padEnd(32)} ← ${r.vid}`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
