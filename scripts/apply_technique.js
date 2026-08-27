/**
 * apply_technique.js
 *
 * Applies docs/exercise_technique.json → sets `techniqueInstructions` on the
 * matching exercise docs. Only fills docs that EXIST and currently LACK
 * technique (never overwrites curated/merged technique). Idempotent.
 *
 * Usage:
 *   TREINO_SA_KEY=~/.config/treino/sa-key.json node scripts/apply_technique.js          # dry-run
 *   TREINO_SA_KEY=~/.config/treino/sa-key.json node scripts/apply_technique.js --write
 */

const { inicializarAdmin } = require('./lib/admin');
const path = require('path');
const WRITE = process.argv.includes('--write');

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { admin } = inicializarAdmin();
const db = admin.firestore();

const { technique } = require(path.join(__dirname, '..', 'docs', 'exercise_technique.json'));

async function main() {
  const ids = Object.keys(technique);
  const missing = [];
  const skipped = [];
  const toSet = [];

  for (const id of ids) {
    const snap = await db.collection('exercises').doc(id).get();
    if (!snap.exists) { missing.push(id); continue; }
    const cur = snap.data().techniqueInstructions;
    if (Array.isArray(cur) && cur.length > 0) { skipped.push(id); continue; }
    toSet.push({ id, ref: snap.ref });
  }

  console.log(`Técnicas en el JSON: ${ids.length}`);
  console.log(`A aplicar (sin técnica):  ${toSet.length}`);
  console.log(`Ya tenían técnica (skip): ${skipped.length}`);
  console.log(`IDs inexistentes:         ${missing.length}`);
  if (missing.length) console.log('  ⚠️ no encontrados:', missing.join(', '));

  if (!WRITE) {
    console.log('DRY-RUN — no se escribió nada. Agregá --write para aplicar.');
    return;
  }

  let written = 0;
  for (let i = 0; i < toSet.length; i += 450) {
    const chunk = toSet.slice(i, i + 450);
    const batch = db.batch();
    for (const t of chunk) {
      batch.set(t.ref, { techniqueInstructions: technique[t.id] }, { merge: true });
    }
    await batch.commit();
    written += chunk.length;
  }
  console.log(`✓ Listo: técnica aplicada a ${written} ejercicios.`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
