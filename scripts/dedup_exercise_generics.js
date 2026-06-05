/**
 * dedup_exercise_generics.js
 *
 * Removes the redundant GENERIC entry from any exercise "family" that already
 * has equipment-qualified variants — e.g. drops "Sentadilla" when "Sentadilla
 * (Barra)", "(Mancuerna)"… exist. Equipment variants are kept (they are
 * distinct exercises, filterable by the Equipamiento chip).
 *
 * Data preservation: when the generic being removed is a hand-curated ORIGINAL
 * (has technique/video/image/etc.), its rich fields are MERGED into the
 * matching variant FIRST (matched by equipment, else the barbell variant, else
 * the first), so nothing curated is lost. The generic doc is then deleted.
 *
 * Family key = normalized name with "(...)" qualifiers stripped.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/dedup_exercise_generics.js          # dry-run
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json node scripts/dedup_exercise_generics.js --write
 */

const admin = require('firebase-admin');
const WRITE = process.argv.includes('--write');

admin.initializeApp();
const db = admin.firestore();

function baseKey(name) {
  return String(name || '')
    .toLowerCase()
    .replace(/[áàäâã]/g, 'a').replace(/[éèëê]/g, 'e').replace(/[íìïî]/g, 'i')
    .replace(/[óòöôõ]/g, 'o').replace(/[úùüû]/g, 'u').replace(/ñ/g, 'n')
    .replace(/\(.*?\)/g, ' ')
    .replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}
const hasQualifier = (name) => /\(.+\)/.test(String(name || ''));

// Fields whose curated value should survive on the merge target.
const MERGE_FIELDS = [
  'techniqueInstructions', 'videoUrl', 'imageUrl', 'imageUrls', 'thumbnailUrl',
  'defaultRestSeconds', 'equipment',
];
const isEmpty = (v) =>
  v === undefined || v === null || v === '' ||
  (Array.isArray(v) && v.length === 0);

// Most "default/free-weight" first, so curated data lands on a sensible variant.
const EQUIP_PREF = [/\(barra\)/i, /\(mancuerna\)/i, /\(m[áa]quina\)/i, /\(polea\)/i, /\(multipower\)/i];

function pickTarget(original, variants) {
  const oe = original.equipment;
  if (oe) {
    const byEquip = variants.find((v) => v.data.equipment === oe);
    if (byEquip) return byEquip;
  }
  for (const re of EQUIP_PREF) {
    const hit = variants.find((v) => re.test(v.data.name));
    if (hit) return hit;
  }
  return variants[0];
}

async function main() {
  const snap = await db.collection('exercises').get();
  const families = {};
  for (const d of snap.docs) {
    const data = d.data();
    (families[baseKey(data.name)] ||= []).push({ id: d.id, ref: d.ref, data });
  }

  const toDelete = []; // {id, name}
  const merges = []; // {from, into, fields:[]}

  for (const members of Object.values(families)) {
    const generics = members.filter((m) => !hasQualifier(m.data.name));
    const variants = members.filter((m) => hasQualifier(m.data.name));
    if (generics.length === 0 || variants.length === 0) continue; // nothing redundant

    for (const g of generics) {
      const isOriginal = !g.data.seedSource;
      const target = pickTarget(g.data, variants);
      const merged = [];
      if (isOriginal && target) {
        for (const f of MERGE_FIELDS) {
          if (!isEmpty(g.data[f]) && isEmpty(target.data[f])) {
            target.data[f] = g.data[f]; // stage (used in --write)
            merged.push(f);
          }
        }
        // aliases: union (keep the original's good Spanish synonyms).
        const union = [...new Set([...(target.data.aliases || []), ...(g.data.aliases || [])])];
        if (union.length !== (target.data.aliases || []).length) {
          target.data.aliases = union;
          merged.push('aliases');
        }
      }
      if (merged.length) merges.push({ from: g.data.name, into: target.data.name, fields: merged, target });
      toDelete.push({ id: g.id, ref: g.ref, name: g.data.name, isOriginal });
    }
  }

  // Report.
  console.log(`Catálogo: ${snap.size}`);
  console.log(`Genéricos redundantes a borrar: ${toDelete.length}`);
  console.log(`  (de esos, originales con datos: ${toDelete.filter((d) => d.isOriginal).length})`);
  console.log(`Merges de datos curados a una variante: ${merges.length}`);
  console.log('Muestra de borrados:');
  for (const d of toDelete.slice(0, 12)) console.log(`  − ${d.name}${d.isOriginal ? '  «ORIGINAL»' : ''}`);
  console.log('Muestra de merges (se preserva el dato):');
  for (const m of merges.slice(0, 10)) console.log(`  ${m.from}  →  ${m.into}   [${m.fields.join(', ')}]`);
  console.log('─'.repeat(54));
  console.log(`Total tras dedup: ${snap.size - toDelete.length}`);

  if (!WRITE) {
    console.log('DRY-RUN — no se tocó nada. Agregá --write para aplicar.');
    return;
  }

  // Apply merges first (so curated data lands on the variant before delete).
  let batch = db.batch();
  let ops = 0;
  const flush = async () => { if (ops) { await batch.commit(); batch = db.batch(); ops = 0; } };
  for (const m of merges) {
    const patch = {};
    for (const f of m.fields) patch[f] = m.target.data[f];
    batch.set(m.target.ref, patch, { merge: true });
    if (++ops >= 450) await flush();
  }
  await flush();
  for (const d of toDelete) {
    batch.delete(d.ref);
    if (++ops >= 450) await flush();
  }
  await flush();
  console.log(`✓ Listo: ${toDelete.length} genéricos borrados, ${merges.length} merges aplicados.`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
