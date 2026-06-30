'use strict';

/**
 * assemble_enriched_catalog.js
 *
 * Combina:
 *   - docs/video-catalog-audit/NUEVO-catalogo.json   (793 ejercicios crudos)
 *   - docs/video-catalog-audit/movement-index.json   (527 movimientos únicos)
 *   - docs/video-catalog-audit/generated/out-*.json   (nombre + técnica por movimiento)
 *
 * Produce docs/video-catalog-audit/enriched-catalog.json: 793 ejercicios en el
 * shape del modelo Exercise (id, name, muscleGroup, category, aliases,
 * techniqueInstructions, equipment) + campos auxiliares _driveFileId/_filename
 * para el paso posterior de subida de videos a Firebase Storage.
 *
 * No escribe a Firestore. Es el insumo de un import script aparte.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const AUDIT = path.join(ROOT, 'docs/video-catalog-audit');
const GEN = path.join(AUDIT, 'generated');

const EQUIP_MAP = {
  peso_corporal: 'peso_corporal',
  mancuerna: 'mancuerna',
  barra: 'barra',
  maquina: 'maquina',
  banda: 'banda',
  cardio: 'cardio',
  polea: 'cable',
  balon: 'otro',
  pesa_rusa: 'pesa_rusa',
  disco: 'disco',
  trx: 'trx',
  multipower: 'multipower',
};

const EQUIP_LABEL = {
  peso_corporal: 'Peso corporal',
  mancuerna: 'Mancuerna',
  barra: 'Barra',
  maquina: 'Máquina',
  cable: 'Cable',
  banda: 'Banda',
  cardio: 'Cardio',
  otro: 'Otro',
  pesa_rusa: 'Pesa rusa',
  disco: 'Disco',
  trx: 'TRX',
  multipower: 'Multipower',
};

const ID_SUFFIX = {
  pesocorporal: 1, pesarusa: 1, mancuerna: 1, barra: 1, maquina: 1,
  banda: 1, cardio: 1, polea: 1, balon: 1, disco: 1, trx: 1, multipower: 1,
};

function movementSlug(id) {
  const parts = id.split('-');
  if (ID_SUFFIX[parts[parts.length - 1]]) return parts.slice(0, -1).join('-');
  return id;
}

function uniq(arr) {
  return [...new Set(arr.filter(Boolean))];
}

function main() {
  const raw = JSON.parse(fs.readFileSync(path.join(AUDIT, 'NUEVO-catalogo.json'), 'utf8'));
  const idx = JSON.parse(fs.readFileSync(path.join(AUDIT, 'movement-index.json'), 'utf8'));

  // slug -> {nombre, tecnica}
  const gen = new Map();
  for (const f of fs.readdirSync(GEN).filter((f) => /^out-\d+\.json$/.test(f))) {
    for (const o of JSON.parse(fs.readFileSync(path.join(GEN, f), 'utf8'))) {
      gen.set(o.slug, o);
    }
  }

  // slug -> nº variantes (para decidir si se agrega etiqueta de equipo al nombre)
  const variantCount = new Map(idx.map((m) => [m.slug, m.variants.length]));
  const category = new Map(idx.map((m) => [m.slug, m.category]));

  const out = [];
  const usedNames = new Map();
  const problems = [];

  for (const e of raw) {
    const slug = movementSlug(e.id);
    const g = gen.get(slug);
    if (!g) {
      problems.push(`sin nombre/tecnica: ${e.id} (slug ${slug})`);
      continue;
    }
    const equipment = EQUIP_MAP[e.equipoES];
    const label = EQUIP_LABEL[equipment];
    const multi = (variantCount.get(slug) || 1) > 1;
    let name = multi ? `${g.nombre} (${label})` : g.nombre;

    // unicidad de nombre
    const key = name.toLowerCase();
    if (usedNames.has(key)) {
      // colisión: forzar etiqueta de equipo
      name = `${g.nombre} (${label})`;
      if (usedNames.has(name.toLowerCase())) {
        name = `${g.nombre} (${label}) ${e.id.split('-').slice(-2, -1)[0] || ''}`.trim();
      }
    }
    usedNames.set(name.toLowerCase(), e.id);

    out.push({
      id: e.id,
      name,
      muscleGroup: e.muscleGroup,
      category: category.get(slug) || 'compound',
      aliases: uniq([name, g.nombre, e.name, slug.replace(/-/g, ' ')]),
      techniqueInstructions: g.tecnica,
      equipment,
      seedSource: 'drive-catalog-2026',
      _driveFileId: e.fileId,
      _filename: e.filename,
    });
  }

  out.sort((a, b) => a.muscleGroup.localeCompare(b.muscleGroup) || a.name.localeCompare(b.name, 'es'));

  fs.writeFileSync(path.join(AUDIT, 'enriched-catalog.json'), JSON.stringify(out, null, 2));

  console.log('Ejercicios ensamblados:', out.length, '/', raw.length);
  console.log('Problemas:', problems.length);
  problems.slice(0, 20).forEach((p) => console.log('  -', p));
  // distribución equipo
  const eq = {};
  for (const o of out) eq[o.equipment] = (eq[o.equipment] || 0) + 1;
  console.log('Equipo:', Object.entries(eq).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}:${v}`).join('  '));
  // nombres duplicados (no debería haber)
  const dupNames = out.length - new Set(out.map((o) => o.name.toLowerCase())).size;
  console.log('Nombres duplicados:', dupNames);
  console.log('Escrito: docs/video-catalog-audit/enriched-catalog.json');
}

main();
