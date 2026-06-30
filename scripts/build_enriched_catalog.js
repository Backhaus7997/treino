'use strict';

/**
 * build_enriched_catalog.js
 *
 * Lee docs/video-catalog-audit/NUEVO-catalogo.json (793 ejercicios crudos del
 * Drive) y produce los insumos para enriquecer el catálogo:
 *
 *   1. movement-index.json  -> movimientos únicos (slug inglés del id sin el
 *      sufijo de equipo) con todas sus variantes de equipo. Unidad de trabajo
 *      para nombrar y escribir técnica una sola vez por movimiento.
 *   2. listado-ejercicios.md -> listado completo agrupado por grupo muscular
 *      (deliverable para el usuario).
 *   3. stats por consola.
 *
 * No escribe a Firestore. Solo genera artefactos en docs/video-catalog-audit/.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'docs/video-catalog-audit/NUEVO-catalogo.json');
const OUT_DIR = path.join(ROOT, 'docs/video-catalog-audit');

// equipoES (NUEVO) -> EquipmentType.jsonValue (enum extendido).
// polea se fusiona en cable; balon en otro. El resto son valores propios.
const EQUIP_MAP = {
  peso_corporal: 'peso_corporal',
  mancuerna: 'mancuerna',
  barra: 'barra',
  maquina: 'maquina',
  banda: 'banda',
  cardio: 'cardio',
  polea: 'cable',
  balon: 'otro',
  pesa_rusa: 'pesa_rusa', // NUEVO en enum
  disco: 'disco', // NUEVO en enum
  trx: 'trx', // NUEVO en enum
  multipower: 'multipower', // NUEVO en enum
};

// sufijo del id (sin guion bajo) -> equipoES, para recortar el slug de movimiento.
const ID_SUFFIX = {
  pesocorporal: 'peso_corporal',
  pesarusa: 'pesa_rusa',
  mancuerna: 'mancuerna',
  barra: 'barra',
  maquina: 'maquina',
  banda: 'banda',
  cardio: 'cardio',
  polea: 'polea',
  balon: 'balon',
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

const MUSCLE_LABEL = {
  chest: 'Pecho',
  back: 'Espalda',
  shoulders: 'Hombros',
  biceps: 'Bíceps',
  triceps: 'Tríceps',
  quads: 'Cuádriceps',
  hamstrings: 'Isquiotibiales',
  glutes: 'Glúteos',
  calves: 'Gemelos',
  core: 'Core',
  fullbody: 'Cuerpo completo',
  cardio: 'Cardio',
};

// heurística compound vs isolation por tokens del movimiento.
const COMPOUND_RE =
  /(press|squat|deadlift|row|lunge|pull|chin|dip|clean|snatch|jerk|thruster|swing|push-?up|burpee|get-?up|carry|step-?up|hip-?thrust|good-?morning|muscle-?up|bench)/;
const ISOLATION_RE =
  /(curl|extension|raise|fly|flye|fly|lateral|kickback|shrug|calf|crunch|pushdown|pullover|abduction|adduction|pec-?deck)/;

function movementSlug(id) {
  const parts = id.split('-');
  const last = parts[parts.length - 1];
  if (ID_SUFFIX[last]) return parts.slice(0, -1).join('-');
  return id; // sin sufijo reconocido (no debería pasar)
}

function guessCategory(slug) {
  if (COMPOUND_RE.test(slug)) return 'compound';
  if (ISOLATION_RE.test(slug)) return 'isolation';
  return 'compound'; // default conservador
}

function main() {
  const raw = JSON.parse(fs.readFileSync(SRC, 'utf8'));

  const movements = new Map(); // slug -> {slug, muscleGroup, category, variants:[]}
  const equipUnmapped = new Set();

  for (const e of raw) {
    const equipment = EQUIP_MAP[e.equipoES];
    if (!equipment) equipUnmapped.add(e.equipoES);
    const slug = movementSlug(e.id);
    if (!movements.has(slug)) {
      movements.set(slug, {
        slug,
        muscleGroup: e.muscleGroup,
        category: guessCategory(slug),
        variants: [],
      });
    }
    movements.get(slug).variants.push({
      id: e.id,
      currentName: e.name,
      equipoES: e.equipoES,
      equipment,
      equipmentLabel: EQUIP_LABEL[equipment] || equipment,
      fileId: e.fileId,
      filename: e.filename,
    });
  }

  const movArr = [...movements.values()].sort(
    (a, b) =>
      a.muscleGroup.localeCompare(b.muscleGroup) || a.slug.localeCompare(b.slug),
  );

  // ---- movement-index.json ----
  fs.writeFileSync(
    path.join(OUT_DIR, 'movement-index.json'),
    JSON.stringify(movArr, null, 2),
  );

  // ---- listado-ejercicios.md ----
  const byMuscle = {};
  for (const e of raw) (byMuscle[e.muscleGroup] ||= []).push(e);
  let md = '# Listado completo de ejercicios (catálogo 793)\n\n';
  md += `Total: **${raw.length}** ejercicios · ${movArr.length} movimientos únicos · ${Object.keys(byMuscle).length} grupos musculares.\n\n`;
  md += '> Nombres actuales (autogenerados, a corregir). Equipo ya normalizado al enum.\n\n';
  for (const mg of Object.keys(byMuscle).sort()) {
    const list = byMuscle[mg].sort((a, b) => a.name.localeCompare(b.name, 'es'));
    md += `## ${MUSCLE_LABEL[mg] || mg} (${list.length})\n\n`;
    md += '| Nombre actual | Equipo | id |\n|---|---|---|\n';
    for (const e of list) {
      const eq = EQUIP_LABEL[EQUIP_MAP[e.equipoES]] || e.equipoES;
      md += `| ${e.name} | ${eq} | \`${e.id}\` |\n`;
    }
    md += '\n';
  }
  fs.writeFileSync(path.join(OUT_DIR, 'listado-ejercicios.md'), md);

  // ---- stats ----
  console.log('Total ejercicios:', raw.length);
  console.log('Movimientos únicos:', movArr.length);
  console.log(
    'Equipo no mapeado:',
    equipUnmapped.size ? [...equipUnmapped].join(', ') : '(ninguno)',
  );
  const eqCount = {};
  for (const e of raw) {
    const v = EQUIP_MAP[e.equipoES];
    eqCount[v] = (eqCount[v] || 0) + 1;
  }
  console.log('Distribución equipo (enum):');
  for (const [k, v] of Object.entries(eqCount).sort((a, b) => b[1] - a[1]))
    console.log('  ', k.padEnd(14), v);
  const variantDist = {};
  for (const m of movArr) {
    const n = m.variants.length;
    variantDist[n] = (variantDist[n] || 0) + 1;
  }
  console.log('Variantes por movimiento (n -> cuántos movimientos):');
  for (const [k, v] of Object.entries(variantDist).sort(
    (a, b) => Number(a[0]) - Number(b[0]),
  ))
    console.log('  ', k, 'variante(s):', v);
  console.log('\nArtefactos escritos en docs/video-catalog-audit/:');
  console.log('  - movement-index.json');
  console.log('  - listado-ejercicios.md');
}

main();
