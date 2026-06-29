/**
 * match_drive_videos_to_catalog.js   (READ-ONLY — no uploads, no Firestore writes)
 *
 * Matches the Drive demonstration clips against the REAL exercise docs in the
 * `exercises` collection, by movement + equipment, for high precision:
 *   - exercise id  "bench-press-barbell"  → movement {bench,press} + equip barbell
 *   - drive file   "female-Barbell-barbell-bench-press-side.mp4"
 *                  → folder Barbell (=barbell) + movement {bench,press}
 *   match only when movement token-set is EQUAL and equipment matches.
 *   Prefer the "side" view over "front".
 *
 * Output: docs/video-catalog-audit/video-matches-full.json  [{id,fileId,filename,equipment,view}]
 * plus a console report (coverage, sample matches, unmatched docs).
 *
 * Run: GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/match_drive_videos_to_catalog.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp({ storageBucket: 'treino-dev.firebasestorage.app' });
const db = admin.firestore();

// Drive folder → canonical equipment token (as used in exercise id suffixes).
const FOLDER_EQUIP = {
  dumbbells: 'dumbbell', barbell: 'barbell', bodyweight: 'bodyweight',
  kettlebells: 'kettlebell', cables: 'cable', band: 'band', machine: 'machine',
  plate: 'plate', 'smith-machine': 'smith-machine', 'medicine-ball': 'medicine-ball',
  medicineball: 'medicine-ball', trx: 'suspension', 'bosu-ball': 'bosu-ball',
  vitruvian: 'machine', cardio: 'cardio',
  recovery: 'recovery', yoga: 'yoga', stretches: 'stretch', pilates: 'pilates',
};
// Equipment suffixes an exercise id may end with (longest first).
const ID_EQUIP_SUFFIXES = [
  'smith-machine', 'trap-bar', 'medicine-ball', 'bosu-ball',
  'barbell', 'dumbbell', 'dumbbells', 'machine', 'cable', 'band',
  'bodyweight', 'suspension', 'kettlebell', 'plate',
];
const EQUIP_ALIASES = { dumbbells: 'dumbbell', 'trap-bar': 'barbell' }; // normalise
const norm = (e) => EQUIP_ALIASES[e] || e;

const isView = (t) => /^(side|front)(_.*)?$/.test(t);

const PREFIX_EQUIP = ['barbell', 'dumbbell', 'cable', 'band', 'machine', 'kettlebell', 'plate'];

function exerciseKey(id) {
  let equip = 'bodyweight';
  let movement = id;
  // equipment as a trailing suffix (e.g. bench-press-barbell)
  for (const suf of ID_EQUIP_SUFFIXES) {
    if (id === suf) break;
    if (id.endsWith('-' + suf)) { equip = norm(suf); movement = id.slice(0, -(suf.length + 1)); break; }
  }
  // equipment as a leading prefix (e.g. barbell-curl, barbell-row)
  if (equip === 'bodyweight') {
    for (const pre of PREFIX_EQUIP) {
      if (id.startsWith(pre + '-')) { equip = norm(pre); movement = id.slice(pre.length + 1); break; }
    }
  }
  const tokens = movement.split('-').filter(Boolean).sort();
  return { equip, mvt: tokens.join('-') };
}

function videoKey(v) {
  const folder = v.folder.toLowerCase();
  const equip = norm(FOLDER_EQUIP[folder] || folder);
  let tokens = v.title.replace(/\.mp4$/i, '').split('-').map((t) => t.toLowerCase()).filter(Boolean);
  if (tokens[0] === 'female' || tokens[0] === 'male') tokens.shift();
  if (tokens.length && isView(tokens[tokens.length - 1])) tokens.pop();
  // drop leading folder token, then a repeated equipment token
  if (tokens.length && tokens[0] === folder) tokens.shift();
  if (tokens.length && (tokens[0] === FOLDER_EQUIP[folder] || tokens[0] === equip)) tokens.shift();
  const view = /(\bside\b)/.test(v.title.toLowerCase()) ? 'side' : 'front';
  return { equip, mvt: tokens.slice().sort().join('-'), view };
}

(async () => {
  const drive = require(path.join('..', 'docs', 'video-catalog-audit', 'drive-videos.json'));
  const videos = Array.isArray(drive) ? drive : (drive.videos || drive.files || Object.values(drive).find(Array.isArray));

  // index: `${equip}|${mvt}` → {side, front}
  const index = new Map();
  for (const v of videos) {
    const k = videoKey(v);
    if (!k.mvt) continue;
    const key = `${k.equip}|${k.mvt}`;
    const slot = index.get(key) || {};
    if (!slot[k.view]) slot[k.view] = { fileId: v.id, filename: v.title };
    index.set(key, slot);
  }

  const snap = await db.collection('exercises').get();
  const matches = [];
  const unmatched = [];
  let already = 0;
  for (const doc of snap.docs) {
    const ek = exerciseKey(doc.id);
    const slot = index.get(`${ek.equip}|${ek.mvt}`);
    if (!slot) { unmatched.push(doc.id); continue; }
    const pick = slot.side || slot.front;
    const view = slot.side ? 'side' : 'front';
    if (doc.data().videoUrl && doc.data().videoUrl.includes('firebasestorage')) already += 1;
    matches.push({ id: doc.id, fileId: pick.fileId, filename: pick.filename, equipment: ek.equip, view });
  }

  fs.writeFileSync(
    path.join(__dirname, '..', 'docs', 'video-catalog-audit', 'video-matches-full.json'),
    JSON.stringify(matches, null, 2),
  );

  console.log(`exercises: ${snap.size} | matched: ${matches.length} | unmatched: ${unmatched.length} | (already have Storage video: ${already})`);
  console.log('--- 24 sample matches (eyeball precision) ---');
  for (const m of matches.slice(0, 24)) console.log(`  ${m.id.padEnd(34)} ← ${m.filename}`);
  console.log('--- 24 unmatched docs ---');
  console.log('  ' + unmatched.slice(0, 24).join(', '));
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
