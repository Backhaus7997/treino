/**
 * seed_templates.js
 *
 * Siembra las plantillas precargadas (rutinas stock) desde
 * docs/video-catalog-audit/improved-templates.json a la colección `routines`
 * de Firestore. Usa los mismos ids que las viejas (ppl-beginner, etc.) → las
 * PISA (set), corrigiendo la ambigüedad de ids contra el catálogo nuevo.
 *
 * - Valida que TODO exerciseId exista en enriched-catalog.json antes de escribir.
 * - Estampa el contrato de discovery que la app necesita para mostrarlas:
 *     source: 'system'      (template stock, no asignación)
 *     visibility: 'public'  (RoutineRepository.listAll filtra por esto)
 *
 * DRY-RUN por default. Para aplicar: --write.
 *
 * Uso:
 *   GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json \
 *   NODE_PATH=functions/node_modules \
 *   node scripts/seed_templates.js            # dry-run
 *   ... node scripts/seed_templates.js --write
 */
'use strict';

const path = require('path');
const templates = require('../docs/video-catalog-audit/improved-templates.json');
const catalog = require('../docs/video-catalog-audit/enriched-catalog.json');

const WRITE = process.argv.includes('--write');

function validate() {
  const ids = new Set(catalog.map((e) => e.id));
  const errors = [];
  for (const t of templates) {
    for (const d of t.days) {
      for (const s of d.slots) {
        if (!ids.has(s.exerciseId)) {
          errors.push(`'${t.id}' día ${d.dayNumber}: exerciseId desconocido '${s.exerciseId}'`);
        }
      }
    }
  }
  if (errors.length) {
    console.error('Validación de referencias FALLÓ:');
    errors.forEach((e) => console.error('  - ' + e));
    throw new Error(`${errors.length} referencia(s) huérfana(s). Abortado antes de escribir.`);
  }
  console.log('Validación de referencias OK (todos los exerciseId existen en el catálogo).');
}

async function main() {
  validate();
  const slots = templates.reduce((a, t) => a + t.days.reduce((b, d) => b + d.slots.length, 0), 0);
  console.log(`Plantillas: ${templates.length} | slots: ${slots} | modo: ${WRITE ? 'WRITE' : 'DRY-RUN'}`);

  if (!WRITE) {
    templates.forEach((t) => console.log(`  ${t.id} — "${t.name}" (${t.days.length} días)`));
    console.log('\nPara aplicar: --write');
    return;
  }

  const admin = require('firebase-admin');
  admin.initializeApp();
  const db = admin.firestore();
  for (const t of templates) {
    const doc = { ...t, source: 'system', visibility: 'public' };
    await db.collection('routines').doc(t.id).set(doc);
    console.log(`  ✓ ${t.id}`);
  }
  console.log('Plantillas sembradas.');
}

main().catch((e) => { console.error(e); process.exit(1); });
