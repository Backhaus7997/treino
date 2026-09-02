/**
 * seed_racha_semanas.js
 *
 * Siembra `rachaSemanas: 0` en los `userPublicProfiles` opt-in que todavía no
 * tienen el campo, para que el board de RACHAS no los deje afuera.
 *
 * Por qué hace falta: la racha pasó de días (`racha`) a semanas
 * (`rachaSemanas`), campo NUEVO. El leaderboard ordena por él, y Firestore
 * **excluye de un `orderBy` los documentos donde el campo está AUSENTE** — no
 * los manda al fondo, los saca. Sin esta semilla, el día del deploy el board
 * de rachas se queda sólo con quien haya completado una semana desde entonces:
 * todos los demás desaparecen del ranking en vez de aparecer con 0.
 * (`user_public_profile_repository.dart` documenta la misma semántica para
 * `_presenceRequiredMetrics`.)
 *
 * Qué escribe: el literal `0`. NADA MÁS.
 *
 *   - NO recalcula la racha real. Para eso haría falta el objetivo semanal del
 *     atleta, o sea resolver cuál es su rutina activa — una cadena de
 *     prioridad que ya vive dos veces (Dart y Swift, fijada por
 *     `conformance/routine_selection.json`). Una tercera copia acá, corriendo
 *     contra producción y escribiendo a un board PÚBLICO, es más riesgo del
 *     que compra.
 *   - NO estampa `rachaSemanasUpdatedAt`. Sin sello, `effectiveRachaSemanas`
 *     devuelve 0 en lectura igual: el 0 sembrado no puede quedar "fresco" por
 *     accidente.
 *
 * Consecuencia honesta, y hay que decirla: durante a lo sumo una semana el
 * board SUB-reporta. Un atleta que venía con racha viva aparece en 0 hasta que
 * complete su próxima semana, momento en el que `finish()` escribe el valor
 * real. Sub-reportar en un ranking es mucho más barato que sobre-reportar: un
 * número inflado es una mentira, un 0 temprano es sólo un dato que todavía no
 * llegó.
 *
 * Idempotente: los docs que ya tienen el campo se saltean. Re-correrlo no
 * escribe nada nuevo y JAMÁS pisa un valor real.
 *
 * ⚠️  ORDEN DE DEPLOY: correr DESPUÉS de deployar las firestore.rules que
 * agregan `rachaSemanas` al allowlist de `userPublicProfiles`. (Este script
 * usa Admin SDK y se saltea las rules; el riesgo es para las escrituras del
 * cliente que vienen después.)
 *
 * Uso:
 *   # Producción (necesita $TREINO_SA_KEY, fuera del repo — ver scripts/README.md):
 *   cd scripts && node seed_racha_semanas.js --dry-run   # sólo loguea
 *   cd scripts && node seed_racha_semanas.js             # escribe
 *
 *   # Emulador (sin credenciales):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_racha_semanas.js
 */

'use strict';

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

const dryRun = process.argv.includes('--dry-run');

/** Firestore acepta hasta 500 operaciones por batch. */
const BATCH_SIZE = 400;

(async () => {
  // Sólo los opt-in: el board no lista a nadie más, así que sembrarle el campo
  // a quien no participa sería ensuciar docs sin ningún efecto.
  const snap = await db
    .collection('userPublicProfiles')
    .where('rankingOptIn', '==', true)
    .get();

  console.log(`Perfiles con rankingOptIn=true: ${snap.size}`);
  if (dryRun) console.log('(dry-run: no se escribe nada)');
  console.log('');

  const pendientes = snap.docs.filter(
    (d) => d.data().rachaSemanas === undefined,
  );

  console.log(`Sin \`rachaSemanas\`: ${pendientes.length}`);
  console.log(`Ya con el campo (se saltean): ${snap.size - pendientes.length}`);
  console.log('');

  if (pendientes.length === 0) {
    console.log('Nada que sembrar.');
    process.exit(0);
  }

  for (const doc of pendientes) {
    console.log(`${doc.id}: rachaSemanas -> 0${dryRun ? ' (dry-run)' : ''}`);
  }

  if (dryRun) {
    console.log('');
    console.log(`Done (dry-run). ${pendientes.length} doc(s) se habrían sembrado.`);
    process.exit(0);
  }

  let escritos = 0;
  for (let i = 0; i < pendientes.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const doc of pendientes.slice(i, i + BATCH_SIZE)) {
      // `merge` y sólo este campo: no tocamos `racha` legacy, ni los contadores,
      // ni ningún otro dato del perfil.
      batch.set(doc.ref, { rachaSemanas: 0 }, { merge: true });
    }
    await batch.commit();
    escritos += Math.min(BATCH_SIZE, pendientes.length - i);
    console.log(`  … ${escritos}/${pendientes.length}`);
  }

  console.log('');
  console.log(`Done. ${escritos} doc(s) sembrados con rachaSemanas: 0.`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
