/**
 * backfill_dedupe_setlogs.js
 *
 * Limpia los `setLogs` DUPLICADOS que dejó el bug de ids cruzados entre el
 * teléfono y el reloj, y sana el `totalVolumeKg` de esas sesiones.
 *
 * Por qué: los dos clientes acuñaban ids distintos para la misma fila lógica
 * —el teléfono autogenerado, el reloj `exerciseId__setNumber`— así que el que
 * escribía segundo no tenía contra qué deduplicar y creaba un documento nuevo.
 * El arreglo de `fix/watch-sync-bugs` es PREVENTIVO: lo que ya está sigue ahí.
 *
 * ⚠️ LO QUE IMPORTA NO SON LOS DOCUMENTOS.
 *
 * `functions/src/ranking-aggregate.ts:183` calcula `lifetimeVolumeKg` sumando
 * el campo `totalVolumeKg` de cada SESIÓN — NO los setLogs. Los agregadores de
 * Insights hacen lo mismo (`monthly_report_aggregator.dart:69`,
 * `muscle_distribution_aggregator.dart:77`). Borrar documentos duplicados, por
 * sí solo, NO cambia nada de lo que ve el atleta.
 *
 * Lo corrupto es el campo guardado, y no siempre hacia arriba: lo escribió el
 * cliente que cerró la sesión, desde SU estado local. En `ZTjx8jVA6Ru5vCVLLy5x`
 * los documentos suman 3850, las series reales 2200 y el campo dice 1650 — el
 * teléfono cerró con sus 3 series sin haber ingerido las 4 del reloj.
 *
 * Entonces: se borran los duplicados Y se recalcula `totalVolumeKg` sobre lo
 * que sobrevive. Escribir la sesión dispara `rankingAggregateOnSession`
 * (`onDocumentWritten`), así que `lifetimeVolumeKg` y los `best<Lift>Kg` se
 * recalculan solos en el server.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * LO QUE NO TOCA, Y POR QUÉ. Cada una de estas salvaguardas salió de una
 * revisión adversarial previa a la primera corrida.
 *
 * 1. SESIONES RENUMERADAS. Es la trampa que hubiera DESTRUIDO datos.
 *    `SessionNotifier.removeSet` renumera solo los sobrevivientes que están en
 *    su estado, y ese estado ya pasó por `_dedupedLogs` — o sea que los
 *    documentos SOMBRA nunca se renumeran y quedan con el número viejo.
 *    Ejemplo real: el reloj escribe W1(1) W2(2) W3(3) y el teléfono P1 P2 P3
 *    duplicados; el atleta borra la serie 2 desde el celular y queda
 *    W1(1) P1(1) W2(2) W3(3) P3(2). Agrupando por campos, la clave `__2` junta
 *    W2 —la serie BORRADA— con P3 —la serie 3 real renumerada—, y como W2 es
 *    más viejo sobreviviría W2 y se borraría P3: **la serie que el atleta borró
 *    vuelve al historial y la real desaparece**, con el volumen subiendo.
 *    `enConflicto` no lo ve cuando las series son iguales, que es lo normal.
 *    Por eso se saltea entera cualquier sesión con evidencia de renumeración.
 *
 * 2. CONFLICTOS. Si dos documentos de la misma serie lógica traen reps, kilos o
 *    RPE distintos, uno es una corrección del atleta y borrar el equivocado la
 *    pierde. Se saltea la sesión entera.
 *
 * 3. DOCUMENTOS MALFORMADOS. Sin `exerciseId` o sin `setNumber` no hay
 *    identidad lógica que comparar; agruparlos por una clave `undefined`
 *    juntaría series de EJERCICIOS DISTINTOS. Se saltea la sesión entera.
 *
 * 4. VOLUMEN DESAJUSTADO SIN DUPLICADOS. Tiene otras causas —una sesión
 *    abandonada, un cierre viejo— y recalcularlo sería otra migración, mucho
 *    más invasiva. Se reporta y se deja quieto.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SEGURIDAD
 *
 * - El respaldo se escribe ANTES de borrar, sesión por sesión, con flush. Si el
 *   proceso muere a la mitad, lo ya borrado está en el archivo.
 * - `completedAt` se guarda como ISO con marca de tipo, para que
 *   `restore_dedupe_setlogs.js` lo rehidrate a `Timestamp`. Reponer un
 *   `{_seconds,_nanoseconds}` crudo dejaría la serie ilegible para la app.
 * - El `totalVolumeKg` ANTERIOR va en el respaldo. No se puede reconstruir
 *   desde los documentos: la premisa del script es justamente que no coincidían.
 * - Los borrados y la escritura del volumen de una sesión van en un MISMO
 *   `WriteBatch`: o entra todo o no entra nada. Sin eso, morir en el medio
 *   dejaba la sesión sin duplicados y con el volumen mal — y una segunda
 *   corrida ya no la vería como afectada.
 * - Idempotente: una sesión ya sana no se toca. Correrlo dos veces no escribe.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ ORDEN DE DEPLOY — correr esto ANTES de publicar el fix no sirve.
 *
 * Los duplicados los crean los CLIENTES. Con la versión vieja instalada siguen
 * apareciendo, así que limpiar antes es tirar la corrida: la base se vuelve a
 * ensuciar sola.
 *
 * Y una app móvil no se actualiza de golpe. Aunque el fix salga hoy, los
 * atletas que sigan en la versión anterior van a seguir generando duplicados
 * durante semanas. El orden real es:
 *
 *   1. Publicar la app con el fix (iOS lleva el companion del reloj embebido:
 *      los dos lados salen en la misma release).
 *   2. Esperar a que la mayoría del padrón actualice.
 *   3. `--dry-run`, mirar el reporte —sobre todo las SALTEADAS—, y recién ahí
 *      `--apply`.
 *   4. Volver a correrlo más adelante si quedó una cola larga de versiones
 *      viejas. Es idempotente justamente para eso.
 *
 * NO hace falta deployar nada de `functions/` ni de `firestore.rules`: este
 * script usa el Admin SDK, que las saltea, y `rankingAggregateOnSession` ya
 * está en producción.
 *
 * ⚠️ COSTO EN PRODUCCIÓN. Cada sesión que se escribe dispara
 * `rankingAggregateOnSession`, y esa función lee hasta 365 sesiones del atleta
 * MÁS todos los `setLogs` de cada una. O sea que tocar N sesiones de un mismo
 * atleta cuesta N recálculos completos, no uno. Es correcto —la función es
 * idempotente y gana la última— pero es plata. Si el dry-run muestra muchas
 * sesiones por atleta, conviene mirar la factura antes de aplicar.
 *
 * Usage:
 *   # Emulador (sin credenciales):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_dedupe_setlogs.js --dry-run
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_dedupe_setlogs.js --apply
 *
 *   # Producción (necesita scripts/sa-key.json, gitignored):
 *   cd scripts && node backfill_dedupe_setlogs.js --dry-run
 *   cd scripts && node backfill_dedupe_setlogs.js --apply
 *
 *   # Un solo atleta:
 *   ... node scripts/backfill_dedupe_setlogs.js --uid seed-athlete-001 --dry-run
 *
 * SIN `--apply` NO ESCRIBE. El default es seguro a propósito: este script borra.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// La DECISIÓN —qué se saltea, qué se borra, qué volumen queda— vive en un
// módulo aparte y TESTEADO. Este script borra datos de producción: lo sutil
// tiene que poder medirse sin Firestore y sin emulador, en milisegundos.
// Ver `scripts/lib/dedupe_setlogs_plan.js` y su test.
//
// Acá queda lo único que no se puede evitar: leer, respaldar y escribir.
const { paraRespaldo, planSesion } = require('./lib/dedupe_setlogs_plan');

if (process.env.FIRESTORE_EMULATOR_HOST) {
  admin.initializeApp({ projectId: 'treino-dev' });
} else {
  let serviceAccount;
  try {
    serviceAccount = require('./sa-key.json');
  } catch (err) {
    if (err.code !== 'MODULE_NOT_FOUND') throw err;
    console.error(
      '\nERROR: scripts/sa-key.json not found — required to run against production.\n' +
      'Download a service-account key from the Firebase console and save it as\n' +
      'scripts/sa-key.json (gitignored), or target the local emulator instead:\n\n' +
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_dedupe_setlogs.js\n',
    );
    process.exitCode = 1;
    return;
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

// Escribir es OPT-IN. Un script que borra no puede tener el borrado por default.
const APPLY = process.argv.includes('--apply');
const uidArgIndex = process.argv.indexOf('--uid');
const ONLY_UID = uidArgIndex !== -1 ? process.argv[uidArgIndex + 1] : null;

/** Cómo reconocer un Timestamp de Firestore. Se le pasa a `paraRespaldo` para
 *  que el módulo de la decisión no tenga que arrastrar `firebase-admin`. */
const aFecha = (v) => (v instanceof admin.firestore.Timestamp ? v.toDate() : null);

const RESPALDO = path.join(__dirname, `dedupe-setlogs-backup-${Date.now()}.json`);
let respaldoAbierto = false;
/** Append con flush: si el proceso muere, lo ya volcado sobrevive. */
function volcarRespaldo(entrada) {
  if (!respaldoAbierto) {
    fs.writeFileSync(RESPALDO, '');
    respaldoAbierto = true;
  }
  fs.appendFileSync(RESPALDO, JSON.stringify(entrada) + '\n');
}

(async () => {
  console.log(APPLY ? '── APLICANDO ──\n' : '── DRY RUN (sin --apply no se escribe) ──\n');

  const userDocs = ONLY_UID
    ? [await db.collection('users').doc(ONLY_UID).get()]
    : (await db.collection('users').get()).docs;

  let sesionesRevisadas = 0;
  let sesionesTocadas = 0;
  let docsBorrados = 0;
  const cambiosVolumen = [];
  const salteadas = [];
  const desajustesSinDuplicados = [];

  for (const userDoc of userDocs) {
    if (!userDoc.exists) continue;
    const uid = userDoc.id;
    const sesiones = await db
      .collection('users').doc(uid).collection('sessions').get();

    for (const sesion of sesiones.docs) {
      sesionesRevisadas++;
      const logsSnap = await sesion.ref.collection('setLogs').get();
      if (logsSnap.empty) continue;

      // El snapshot se reduce a lo único que la decisión mira. `doc` viaja de
      // vuelta adentro para poder borrar por referencia sin volver a buscar.
      const plan = planSesion(
        logsSnap.docs.map((d) => ({
          id: d.id,
          data: d.data(),
          createTimeMs: d.createTime.toMillis(),
          doc: d,
        })),
        sesion.data().totalVolumeKg ?? 0,
      );

      if (plan.tipo === 'vacia' || plan.tipo === 'sana') continue;

      // Las salteadas son las que necesitan mirada humana: renumeración,
      // conflictos de reps/kilos/RPE, o documentos malformados. Ver las
      // salvaguardas en el módulo de la decisión.
      if (plan.tipo === 'salteada') {
        salteadas.push({
          sesion: sesion.id, motivo: plan.motivo, detalle: plan.detalle,
        });
        continue;
      }

      const califica = sesion.data().status === 'finished' &&
        sesion.data().wasFullyCompleted === true;

      // Salvaguarda 4: desajuste SIN duplicados. Tiene otras causas y
      // recalcularlo sería otra migración. Se reporta y se deja quieto.
      if (plan.tipo === 'desajuste-sin-duplicados') {
        desajustesSinDuplicados.push({
          sesion: sesion.id, guardado: plan.volumenGuardado,
          real: plan.volumenReal, califica,
        });
        continue;
      }

      sesionesTocadas++;
      docsBorrados += plan.borrar.length;
      if (plan.volumenDifiere) {
        cambiosVolumen.push({
          sesion: sesion.id, guardado: plan.volumenGuardado,
          real: plan.volumenReal,
          delta: plan.volumenReal - plan.volumenGuardado,
          duplicados: plan.borrar.length, califica,
        });
      }

      if (!APPLY) continue;

      // El respaldo va ANTES del borrado y con flush, para que un corte a mitad
      // de corrida deje rastro de todo lo que ya se eliminó.
      volcarRespaldo({
        sesionPath: sesion.ref.path,
        totalVolumeKgAnterior: plan.volumenGuardado,
        totalVolumeKgNuevo: plan.volumenDifiere
          ? plan.volumenReal
          : plan.volumenGuardado,
        borrados: plan.borrar.map(({ doc }) => ({
          path: doc.ref.path, data: paraRespaldo(doc.data(), aFecha),
        })),
      });

      // Un batch por sesión: los borrados y el volumen entran juntos o no entra
      // nada. Sin esto, morir en el medio dejaba la sesión sin duplicados y con
      // el volumen viejo — y la re-corrida ya no la reconocía como afectada.
      const batch = db.batch();
      for (const { doc } of plan.borrar) batch.delete(doc.ref);
      if (plan.volumenDifiere) {
        batch.set(sesion.ref, { totalVolumeKg: plan.volumenReal }, { merge: true });
      }
      await batch.commit();
    }
  }

  if (cambiosVolumen.length > 0) {
    console.log('totalVolumeKg corregido (el que leen rankings e insights):');
    for (const c of cambiosVolumen.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))) {
      const signo = c.delta > 0 ? '+' : '';
      console.log(
        `  ${c.sesion}  ${c.guardado} -> ${c.real} (${signo}${c.delta.toFixed(1)} kg)` +
        `  dups=${c.duplicados}${c.califica ? ' [CUENTA PARA RANKINGS]' : ''}`,
      );
    }
    console.log('');
  }

  if (desajustesSinDuplicados.length > 0) {
    console.log(
      `${desajustesSinDuplicados.length} sesiones con totalVolumeKg desajustado ` +
      'SIN duplicados. Otra causa, NO se tocan:',
    );
    for (const d of desajustesSinDuplicados) {
      console.log(
        `  ${d.sesion}  ${d.guardado} -> ${d.real}` +
        `${d.califica ? ' [CUENTA PARA RANKINGS]' : ''}`,
      );
    }
    console.log('');
  }

  if (salteadas.length > 0) {
    console.log('⚠️  SALTEADAS — necesitan mirada humana:');
    for (const s of salteadas) {
      console.log(`  ${s.sesion}  (${s.motivo})`);
      console.log(`      ${s.detalle}`);
    }
    console.log('');
  }

  if (respaldoAbierto) console.log(`Respaldo: ${RESPALDO}\n`);

  console.log(
    `Done. ${sesionesRevisadas} sesiones revisadas, ${sesionesTocadas} tocadas, ` +
    `${docsBorrados} documentos ${APPLY ? 'borrados' : 'a borrar'}, ` +
    `${cambiosVolumen.length} volúmenes ${APPLY ? 'corregidos' : 'a corregir'}, ` +
    `${salteadas.length} salteadas.`,
  );
  // `process.exitCode` y no `process.exit`: exit trunca la escritura async a
  // stdout, y ahí se pierde justo el listado de lo que hay que mirar a mano.
  process.exitCode = 0;
})().catch((err) => {
  console.error(err);
  if (respaldoAbierto) {
    console.error(`\nLo ya borrado quedó respaldado en: ${RESPALDO}`);
  }
  process.exitCode = 1;
});
