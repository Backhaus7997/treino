'use strict';

/**
 * import_enriched_catalog.js
 *
 * Sube docs/video-catalog-audit/enriched-catalog.json (793 ejercicios) a la
 * colección `exercises` de Firestore.
 *
 * Por defecto corre en DRY-RUN (no escribe nada). Requiere flags explícitos:
 *   --write      escribe/actualiza los 793 docs (merge:true, no pisa videoUrl
 *                ya seteado salvo que se incluya en el doc).
 *   --replace    además BORRA los docs existentes en `exercises` cuyo id NO
 *                esté en el catálogo nuevo (migración limpia). PELIGROSO:
 *                rompe rutinas que referencien ids viejos por id directo.
 *
 * Los campos auxiliares _driveFileId/_filename NO se escriben (son para el
 * paso de subida de videos a Storage). videoUrl se deja para ese paso.
 *
 * Uso:
 *   GOOGLE_APPLICATION_CREDENTIALS=... node scripts/import_enriched_catalog.js          # dry-run
 *   GOOGLE_APPLICATION_CREDENTIALS=... node scripts/import_enriched_catalog.js --write
 *   GOOGLE_APPLICATION_CREDENTIALS=... node scripts/import_enriched_catalog.js --write --replace
 */

const fs = require('fs');
const path = require('path');

const WRITE = process.argv.includes('--write');
const REPLACE = process.argv.includes('--replace');

const SRC = path.resolve(__dirname, '../docs/video-catalog-audit/enriched-catalog.json');

async function main() {
  const raw = JSON.parse(fs.readFileSync(SRC, 'utf8'));
  const docs = raw.map((e) => {
    const { _driveFileId, _filename, ...doc } = e;
    return doc;
  });

  console.log(`Catálogo: ${docs.length} ejercicios.`);
  console.log(`Modo: ${WRITE ? 'WRITE' : 'DRY-RUN'}${REPLACE ? ' + REPLACE' : ''}`);

  if (!WRITE) {
    console.log('\n[dry-run] No se escribe nada. Muestra de 3 docs:');
    docs.slice(0, 3).forEach((d) => console.log(JSON.stringify(d, null, 2)));
    console.log('\nPara aplicar: agregá --write (y opcional --replace).');
    return;
  }

  const admin = require('firebase-admin');
  admin.initializeApp(); // usa GOOGLE_APPLICATION_CREDENTIALS
  const db = admin.firestore();
  const col = db.collection('exercises');

  const newIds = new Set(docs.map((d) => d.id));

  if (REPLACE) {
    const existing = await col.get();
    const stale = existing.docs.filter((d) => !newIds.has(d.id));
    console.log(`REPLACE: ${stale.length} docs viejos a borrar.`);
    let batch = db.batch();
    let n = 0;
    for (const d of stale) {
      batch.delete(d.ref);
      if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
    }
    await batch.commit();
  }

  let batch = db.batch();
  let n = 0;
  for (const d of docs) {
    batch.set(col.doc(d.id), d, { merge: true });
    if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`Listo: ${docs.length} ejercicios escritos.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
