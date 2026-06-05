/**
 * import_exercises_catalog.js
 *
 * Merges docs/exercises_catalog.json (free-exercise-db derived, 429 entries with
 * name_es/muscle_es) into the Firestore `exercises` collection, WITHOUT
 * duplicates against what's already there (the hand-curated seed + anything
 * previously imported).
 *
 * Dedup key: id (kebab of name_en) OR normalized name (es/en) matching an
 * existing doc's name/aliases. Idempotent — re-running adds nothing new.
 *
 * Imported docs are tagged `seedSource: 'free-exercise-db'` (traceable +
 * reversible). Media in the dataset is static images, not videos, so videoUrl
 * is left null (videos are sourced separately).
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/import_exercises_catalog.js          # dry-run (report only)
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/import_exercises_catalog.js --write   # actually write
 */

const admin = require('firebase-admin');
const path = require('path');

const WRITE = process.argv.includes('--write');

admin.initializeApp(); // GOOGLE_APPLICATION_CREDENTIALS
const db = admin.firestore();

const { exercises: SOURCE } = require(path.join(
  __dirname,
  '..',
  'docs',
  'exercises_catalog.json',
));

// JSON muscle_en (20) → app muscleGroup taxonomy (10). Debatable ones flagged
// in the run report so they can be refined later.
const MUSCLE = {
  Abdominals: 'core',
  Abductors: 'glutes', // hip abductors ~ glute region
  Adductors: 'quads', // inner thigh → leg bucket
  Biceps: 'biceps',
  Calves: 'calves',
  Cardio: 'cardio', // dedicated group
  Chest: 'chest',
  Forearms: 'biceps', // arm → closest existing bucket
  'Full Body': 'fullbody', // dedicated group
  Glutes: 'glutes',
  Hamstrings: 'hamstrings',
  Lats: 'back',
  'Lower Back': 'back',
  Neck: 'shoulders',
  Other: 'core', // catch-all
  Quadriceps: 'quads',
  Shoulders: 'shoulders',
  Traps: 'back', // traps grouped with back
  Triceps: 'triceps',
  'Upper Back': 'back',
};
const DEBATABLE = new Set(['Abductors', 'Adductors', 'Forearms', 'Neck', 'Other']);

const ISO_KEYWORDS = [
  'curl', 'extension', 'fly', 'flye', 'raise', 'lateral', 'kickback',
  'pushdown', 'shrug', 'crunch', 'pec deck', 'reverse fly', 'concentration',
  'preacher', 'wrist', 'calf raise', 'leg curl', 'leg extension',
];

function normalize(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[áàäâã]/g, 'a')
    .replace(/[éèëê]/g, 'e')
    .replace(/[íìïî]/g, 'i')
    .replace(/[óòöôõ]/g, 'o')
    .replace(/[úùüû]/g, 'u')
    .replace(/ñ/g, 'n')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function toId(nameEn) {
  return String(nameEn || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function categorize(nameEn) {
  const n = String(nameEn || '').toLowerCase();
  return ISO_KEYWORDS.some((k) => n.includes(k)) ? 'isolation' : 'compound';
}

async function main() {
  // 1. Build dedup sets from the LIVE catalog.
  const snap = await db.collection('exercises').get();
  const existingIds = new Set();
  const existingNorms = new Set();
  for (const doc of snap.docs) {
    existingIds.add(doc.id);
    const d = doc.data();
    if (d.name) existingNorms.add(normalize(d.name));
    for (const a of d.aliases || []) existingNorms.add(normalize(a));
  }
  console.log(`Catálogo vivo: ${snap.size} ejercicios.`);

  // 2. Map + dedup the source.
  const toAdd = [];
  const addedIds = new Set();
  const addedNorms = new Set();
  const debatableHits = {};
  let skippedDup = 0;
  let skippedBadData = 0;

  for (const ex of SOURCE) {
    const nameEs = (ex.name_es || '').trim();
    const nameEn = (ex.name_en || '').trim();
    if (!nameEs || !nameEn) {
      skippedBadData++;
      continue;
    }
    const id = toId(nameEn);
    const normEs = normalize(nameEs);
    const normEn = normalize(nameEn);

    const isDup =
      existingIds.has(id) ||
      addedIds.has(id) ||
      existingNorms.has(normEs) ||
      existingNorms.has(normEn) ||
      addedNorms.has(normEs);
    if (isDup) {
      skippedDup++;
      continue;
    }

    const muscleGroup = MUSCLE[ex.muscle_en] || 'core';
    if (DEBATABLE.has(ex.muscle_en)) {
      debatableHits[ex.muscle_en] = (debatableHits[ex.muscle_en] || 0) + 1;
    }
    const aliases = [...new Set([nameEs, nameEn])];

    toAdd.push({
      id,
      name: nameEs,
      muscleGroup,
      category: categorize(nameEn),
      aliases,
      seedSource: 'free-exercise-db',
    });
    addedIds.add(id);
    addedNorms.add(normEs);
  }

  // 3. Report.
  console.log('─'.repeat(56));
  console.log(`Fuente (JSON):      ${SOURCE.length}`);
  console.log(`Duplicados (skip):  ${skippedDup}`);
  console.log(`Datos incompletos:  ${skippedBadData}`);
  console.log(`NUEVOS a agregar:   ${toAdd.length}`);
  console.log(`Total tras merge:   ${snap.size + toAdd.length}`);
  console.log('Mapeos debatibles (muscle_en → revisar):', debatableHits);
  console.log('Muestra de nuevos:');
  for (const e of toAdd.slice(0, 6)) {
    console.log(`  ${e.id}  | ${e.name}  | ${e.muscleGroup}/${e.category}`);
  }
  console.log('─'.repeat(56));

  if (!WRITE) {
    console.log('DRY-RUN — no se escribió nada. Agregá --write para aplicar.');
    return;
  }

  // 4. Write in batches of 450.
  let written = 0;
  for (let i = 0; i < toAdd.length; i += 450) {
    const chunk = toAdd.slice(i, i + 450);
    const batch = db.batch();
    for (const e of chunk) {
      // IMPORTANT: store `id` INSIDE the doc too — Exercise.fromJson requires
      // it (the repo's _fromDoc does NOT inject doc.id), same as the seed.
      batch.set(db.collection('exercises').doc(e.id), e, { merge: false });
    }
    await batch.commit();
    written += chunk.length;
    console.log(`  escritos ${written}/${toAdd.length}…`);
  }
  console.log(`✓ Listo: ${written} ejercicios agregados.`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
