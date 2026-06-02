/**
 * backfill_exercise_equipment.js
 *
 * One-shot idempotent backfill of the `equipment` field on
 * `exercises/{exerciseId}` documents. Reads the canonical map from
 * `_equipment_map.js` (shared with the seed script) and updates each
 * document only if the field is currently missing.
 *
 * Usage:
 *   cd treino  (repo root)
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
 *   node scripts/backfill_exercise_equipment.js
 *
 * Idempotent — re-running is safe:
 *   [updated]  bench-press    → barra
 *   [skipped]  back-squat     (already barra)
 *   [unmapped] custom-id      (no entry in _equipment_map.js)
 *
 * After the run, a summary line shows totals.
 *
 * REQ-RER-015 + ADR-RER-03 of sdd/routine-editor-redesign.
 */

'use strict';

const admin = require('firebase-admin');
const { equipmentMap } = require('./_equipment_map.js');

admin.initializeApp();
const db = admin.firestore();

async function backfill() {
  const snapshot = await db.collection('exercises').get();
  console.log(`Found ${snapshot.size} exercise docs.`);

  let updated = 0;
  let skipped = 0;
  let unmapped = 0;

  for (const doc of snapshot.docs) {
    const id = doc.id;
    const data = doc.data();
    const existingEquipment = data.equipment;
    const targetEquipment = equipmentMap[id];

    if (!targetEquipment) {
      console.log(`[unmapped] ${id}`);
      unmapped += 1;
      continue;
    }

    if (existingEquipment === targetEquipment) {
      console.log(`[skipped]  ${id} (already ${existingEquipment})`);
      skipped += 1;
      continue;
    }

    await doc.ref.update({ equipment: targetEquipment });
    console.log(`[updated]  ${id} → ${targetEquipment}`);
    updated += 1;
  }

  console.log('---');
  console.log(`Summary: ${updated} updated, ${skipped} skipped, ${unmapped} unmapped.`);
  console.log('Total:', snapshot.size);
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
