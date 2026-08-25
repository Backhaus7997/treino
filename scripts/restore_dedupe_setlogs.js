/**
 * restore_dedupe_setlogs.js
 *
 * Repone lo que borró `backfill_dedupe_setlogs.js`, desde su archivo de
 * respaldo. Existe porque un respaldo que nadie probó a restaurar no es un
 * respaldo: es un archivo.
 *
 * Rehidrata los timestamps. El respaldo guarda `completedAt` como
 * `{"__timestamp__": "<ISO>"}` a propósito — reponerlo como objeto plano
 * dejaría la serie ILEGIBLE para la app: `TimestampConverter.fromJson` hace
 * `.toDate()` sobre un `Timestamp` y con un Map tira, `_setLogFromDoc` lo
 * captura y devuelve null, y `whereType<SetLog>()` la descarta. O sea: repuesta
 * en Firestore pero invisible en el historial, en Insights y en el cálculo de
 * `best<Lift>Kg`.
 *
 * También repone el `totalVolumeKg` anterior de cada sesión tocada, que es el
 * otro dato que el backfill pisa y que NO se puede reconstruir desde los
 * documentos.
 *
 * Usage:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     node scripts/restore_dedupe_setlogs.js scripts/dedupe-setlogs-backup-<n>.json --dry-run
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     node scripts/restore_dedupe_setlogs.js scripts/dedupe-setlogs-backup-<n>.json --apply
 */

const admin = require('firebase-admin');
const fs = require('fs');

if (process.env.FIRESTORE_EMULATOR_HOST) {
  admin.initializeApp({ projectId: 'treino-dev' });
} else {
  let serviceAccount;
  try {
    serviceAccount = require('./sa-key.json');
  } catch (err) {
    if (err.code !== 'MODULE_NOT_FOUND') throw err;
    console.error('\nERROR: scripts/sa-key.json not found.\n');
    process.exitCode = 1;
    return;
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const ARCHIVO = process.argv[2];
const APPLY = process.argv.includes('--apply');

if (!ARCHIVO || ARCHIVO.startsWith('--')) {
  console.error('Falta el archivo de respaldo.\n' +
    '  node scripts/restore_dedupe_setlogs.js <backup.json> [--apply]');
  process.exitCode = 1;
  return;
}

/**
 * Devuelve los Timestamp a su tipo. Ver el encabezado.
 *
 * ⚠️ Lo que NO se puede devolver: un double redondo vuelve como INTEGER.
 * `JSON.stringify(110.0)` da `110` y la distinción se pierde en el respaldo, no
 * acá. Verificado que hoy es inocuo: `set_log.g.dart:15` deserializa con
 * `(json['weightKg'] as num).toDouble()`, y `num` cubre int y double.
 *
 * Es un alambre de trampa: si alguna vez ese generado pasara a `as double`, una
 * serie restaurada dejaría de parsear y `_setLogFromDoc` la descartaría en
 * silencio. Si cambia, hay que marcar los floats en el respaldo igual que los
 * timestamps.
 */
const rehidratar = (data) => {
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    out[k] = v && typeof v === 'object' && typeof v.__timestamp__ === 'string'
      ? admin.firestore.Timestamp.fromDate(new Date(v.__timestamp__))
      : v;
  }
  return out;
};

(async () => {
  console.log(APPLY ? '── RESTAURANDO ──\n' : '── DRY RUN (sin --apply no se escribe) ──\n');

  // El respaldo es JSON-por-línea: se escribe con flush por sesión para
  // sobrevivir a un corte, así que no es un array único.
  const lineas = fs.readFileSync(ARCHIVO, 'utf8')
    .split('\n').filter((l) => l.trim().length > 0);

  let docs = 0;
  let sesiones = 0;

  for (const linea of lineas) {
    const entrada = JSON.parse(linea);
    sesiones++;
    console.log(
      `${entrada.sesionPath}\n` +
      `   totalVolumeKg ${entrada.totalVolumeKgNuevo} -> ${entrada.totalVolumeKgAnterior}` +
      `   (${entrada.borrados.length} series a reponer)`,
    );
    if (!APPLY) { docs += entrada.borrados.length; continue; }

    const batch = db.batch();
    for (const b of entrada.borrados) {
      batch.set(db.doc(b.path), rehidratar(b.data));
      docs++;
    }
    batch.set(
      db.doc(entrada.sesionPath),
      { totalVolumeKg: entrada.totalVolumeKgAnterior },
      { merge: true },
    );
    await batch.commit();
  }

  console.log(
    `\nDone. ${sesiones} sesiones, ${docs} documentos ` +
    `${APPLY ? 'repuestos' : 'a reponer'}.`,
  );
  process.exitCode = 0;
})().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
