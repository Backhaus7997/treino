'use strict';

/**
 * scripts/cleanup_rejected_links.js
 *
 * Limpieza one-shot de las solicitudes RECHAZADAS o CANCELADAS que ya están en
 * `trainer_links`. De acá en adelante no se acumulan más: la CF las borra apenas
 * sale la notificación (functions/src/purge-rejected-link.ts). Este script es
 * sólo para las anteriores a ese cambio.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN. Ahí viven los pagos, turnos y sesiones de
 *     usuarios reales. Este script BORRA documentos. Leé AGENTS.md § Entornos
 *     antes de correrlo con `--apply`.
 *
 * ── EL PROBLEMA: `terminated` significa CUATRO cosas ────────────────────────
 *
 * `trainer_links.status == 'terminated'` no distingue el origen:
 *   - `decline`             — el PF rechazó una solicitud    → NUNCA fue vínculo
 *   - `cancel`              — el alumno canceló la suya      → NUNCA fue vínculo
 *   - `terminate`           — un vínculo REAL se dio de baja → tiene historia
 *   - `switched_trainer`    — el alumno cambió de PF         → tiene historia
 *
 * Borrar por `status == 'terminated'` a secas destruiría historia real: de esos
 * vínculos cuelgan pagos y sesiones.
 *
 * ── EL DISCRIMINADOR, Y POR QUÉ NO ALCANZA SOLO ─────────────────────────────
 *
 * `acceptedAt` sólo lo estampa el servidor
 * (functions/src/subscriptions/promote-link.ts, al aceptar), y `firestore.rules`
 * lo pinea inmutable en create y update. Entonces `acceptedAt == null` debería
 * significar "nunca fue un vínculo".
 *
 * DEBERÍA. El propio repo dice que hay excepciones, y por eso este script no
 * borra sólo por `acceptedAt`:
 *
 *   - `functions/src/subscriptions/select-blocked-links.ts:192` — textual: un
 *     vínculo sin `acceptedAt` «es un DEFECTO DE DATOS, no evidencia de
 *     lealtad».
 *   - `functions/src/subscriptions/promote-link.ts:221` — describe un stamp
 *     faltante que degrada a `requestedAt` en vez de fallar.
 *
 * O sea: un vínculo REAL viejo pudo quedar sin `acceptedAt`. Borrarlo sería
 * exactamente el daño que este script existe para evitar.
 *
 * Por eso el criterio de borrado es COMPUESTO — `acceptedAt == null` **y** una
 * señal positiva de que nunca hubo vínculo:
 *
 *   · `terminationReason` ∈ {declined, cancelled-by-athlete} — las dos únicas
 *     razones que el cliente escribe sobre un `pending`
 *     (`lib/features/coach/data/trainer_link_repository.dart`).
 *   · `reason == 'account-deleted'` — lo escribe
 *     `functions/src/cascade/trainer-links.ts` cuando el atleta borra su
 *     cuenta. OJO: `reason`, NO `terminationReason`. Son campos distintos, y
 *     confundirlos dejó estos docs sin juntar por ninguna de las dos puertas.
 *
 * Todo lo demás con `acceptedAt == null` se reporta como AMBIGUO y NO SE TOCA,
 * para que lo mire una persona.
 *
 * ── SALIDA: TRES GRUPOS ─────────────────────────────────────────────────────
 *
 *   BORRA     acceptedAt == null  Y  (terminationReason ∈ {declined,
 *             cancelled-by-athlete}  O  reason == 'account-deleted')
 *   AMBIGUO   acceptedAt == null  pero reason es otro o falta   → NO se toca
 *   CONSERVA  acceptedAt != null  (vínculo real terminado)      → NO se toca
 *
 * Usage:
 *   # Dry-run (DEFAULT — no escribe nada, sólo informa):
 *   node scripts/cleanup_rejected_links.js
 *   node scripts/cleanup_rejected_links.js --dry-run   # explícito, mismo efecto
 *
 *   # Borrar de verdad:
 *   node scripts/cleanup_rejected_links.js --apply
 *
 *   # Sumar los ambiguos al borrado (leé la lista del dry-run ANTES):
 *   node scripts/cleanup_rejected_links.js --apply --incluir-ambiguos
 *
 *   # Listar TODOS los ids en vez de los primeros 20 (para pipear a un archivo):
 *   node scripts/cleanup_rejected_links.js --ids > /tmp/a-borrar.txt
 *
 * Ante flags en conflicto gana la que NO destruye: `--apply --dry-run` NO
 * borra, y lo dice en pantalla.
 *
 * ── LO QUE EL BORRADO DESPIERTA (mirar antes de correr con --apply) ─────────
 *
 * Cada delete de `trainer_links` dispara CUATRO Cloud Functions, porque son
 * triggers `onDocumentWritten` y un delete es una escritura:
 *
 *   linkAggregate                  query completa `where trainerId ==` +
 *                                  escritura a trainerPublicProfiles/{trainerId}
 *   linkLoadReconcile              recompute de weightedLoad + entitlements
 *   cleanupAssignedPlansOnUnlink   corta con `!after`, pero se invoca igual
 *   syncSessionShareOnTrainerLink  inerte por su guarda, pero se invoca igual
 *
 * Una tanda de 500 son ~2000 invocaciones concurrentes. Y los rechazos se
 * concentran en los PF populares, así que muchas caen sobre el MISMO doc de
 * `trainerPublicProfiles`, por encima del límite blando de ~1 escritura/s por
 * documento. `subscriptions/link-load-reconcile.ts` documenta esa estampida en
 * su bloque «CORTE DE LA ESTAMPIDA»; este script la produce a escala.
 *
 * No se agrega throttle acá a propósito: los contadores se recomputan desde
 * cero en cada evento (son idempotentes), así que lo que se pierde en una
 * contención es tiempo, no exactitud. Pero conviene correrlo fuera de hora
 * pico y mirar los logs de Functions después.
 *
 * Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` falla cerrado con
 * la migración en el mensaje; contra el emulador no pide nada.
 * Ver scripts/lib/admin.js.
 */

// El cartel va ANTES de inicializar: lo que frena a alguien tiene que estar en
// pantalla antes del primer write, no después. Mismo idioma que
// `promote_user_to_trainer.js`. (#826)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { FieldPath, getFirestore } = require('firebase-admin/firestore');

/** Las dos únicas razones que se escriben sobre un `pending`. */
const RAZONES_DE_NO_VINCULO = new Set(['declined', 'cancelled-by-athlete']);

/** Límite duro de `WriteBatch` en Firestore. */
const BATCH_SIZE = 500;

/** Cuántos docs se leen por página. Ver `leerTerminados`. */
const PAGE_SIZE = 500;

/**
 * Parte `docs` en páginas de a lo sumo `tam`. Puro, para poder testear el
 * chunking sin Firestore.
 *
 * @param {Array} docs
 * @param {number} tam
 * @returns {Array[]}
 */
function paginasDe(docs, tam) {
  const paginas = [];
  for (let i = 0; i < docs.length; i += tam) paginas.push(docs.slice(i, i + tam));
  return paginas;
}

/**
 * Cuántos de `chunk` existían de verdad, según el set de ids leídos en el
 * mismo batch.
 *
 * POR QUÉ NO ALCANZA CON `chunk.length`: `batch.delete()` sobre un doc que ya
 * no está resuelve OK, así que contar operaciones emitidas es contar intentos,
 * no borrados. Y desde que la CF purga en paralelo
 * (`functions/src/purge-rejected-link.ts`), la ventana entre la lectura y el
 * commit es real: un rechazo que la CF se llevó en el medio se contaba igual.
 * Un script destructivo que informa de más es un cartel tranquilizador sin
 * verificar (AGENTS.md §11.1).
 *
 * @param {Array<{id: string}>} chunk
 * @param {Set<string>} existian
 * @returns {number}
 */
function contarBorradosReales(chunk, existian) {
  let n = 0;
  for (const d of chunk) if (existian.has(d.id)) n += 1;
  return n;
}

/**
 * Parsea las flags. Puro y exportado para poder testear la compuerta del
 * borrado sin tocar Firestore.
 *
 * REGLA: ante flags en conflicto, GANA LA QUE NO DESTRUYE.
 *
 * `--dry-run` estaba antes en la allowlist del validador y NUNCA se leía, así
 * que `node cleanup_rejected_links.js --apply --dry-run` BORRABA. Es la peor
 * forma de fallar que puede tener un script destructivo: el validador acepta
 * el flag —le confirma al operador que lo entendió— y después lo ignora.
 *
 * Y no es una palabra cualquiera. Ocho scripts de este mismo directorio
 * (`backfill_gym_ids`, `backfill_gym_names`, `backfill_athlete_counts`,
 * `backfill_racha_freshness`, `backfill_trainer_links_shared`,
 * `backfill_custom_exercise_name_lowercase`, `upload_drive_exercise_videos`,
 * `upload_enriched_videos`) usan `--dry-run` como LA flag que frena las
 * escrituras. El único que borra documentos no puede ser el único donde esa
 * palabra no significa nada.
 *
 * @param {string[]} argv - `process.argv` completo.
 */
function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  const desconocidas = [...flags].filter(
    (f) => !['--apply', '--incluir-ambiguos', '--dry-run', '--ids'].includes(f),
  );
  if (desconocidas.length) {
    console.error(`Flags desconocidas: ${desconocidas.join(', ')}`);
    process.exit(2);
  }
  const dryRunExplicito = flags.has('--dry-run');
  return {
    apply: flags.has('--apply') && !dryRunExplicito,
    dryRunExplicito,
    incluirAmbiguos: flags.has('--incluir-ambiguos'),
    // Listar TODOS los ids en vez de los primeros IDS_A_MOSTRAR.
    ids: flags.has('--ids'),
  };
}

/**
 * Clasifica un doc de `trainer_links` en uno de los tres grupos.
 *
 * Puro y exportado para que se pueda testear sin Firestore.
 *
 * @param {{acceptedAt?: unknown, terminationReason?: unknown}} data
 * @returns {'borra'|'ambiguo'|'conserva'}
 */
function clasificar(data) {
  // `acceptedAt` gana ANTES que cualquier razón: si hubo relación, se conserva.
  // Vale también para la cuenta borrada — el atleta se fue, pero los pagos y
  // las sesiones que le cuelgan al PF siguen existiendo.
  if (data.acceptedAt != null) return 'conserva';

  // `reason` (NO `terminationReason`) es lo que escribe
  // `functions/src/cascade/trainer-links.ts` cuando el atleta borra su cuenta.
  // Son campos DISTINTOS y confundirlos dejó el agujero: estos docs caían en
  // AMBIGUO y no los juntaba nadie. Hubo uno real en producción.
  if (data.reason === 'account-deleted') return 'borra';

  return RAZONES_DE_NO_VINCULO.has(data.terminationReason) ? 'borra' : 'ambiguo';
}

/** Cuenta por `terminationReason`, con `(sin razón)` para el faltante. */
function desglosePorRazon(docs) {
  const conteo = new Map();
  for (const d of docs) {
    const razon = d.razon ?? '(sin razón)';
    conteo.set(razon, (conteo.get(razon) ?? 0) + 1);
  }
  return [...conteo.entries()].sort((a, b) => b[1] - a[1]);
}

/**
 * Cuántos ids se listan por grupo antes de cortar.
 *
 * Salió de correr el dry-run contra el emulador con 1200 rechazos sembrados:
 * listarlos todos inunda la terminal y —peor— empuja al grupo AMBIGUO, que es
 * el que necesita criterio humano, fuera de pantalla. Un reporte que no se
 * puede leer no es un paso de revisión.
 *
 * Con `--ids` se listan enteros, para el que quiera pipearlo a un archivo.
 */
const IDS_A_MOSTRAR = 20;

function imprimirGrupo(titulo, docs, { detallar = false, todos = false } = {}) {
  console.log(`\n${titulo}: ${docs.length}`);
  if (docs.length === 0) return;
  for (const [razon, n] of desglosePorRazon(docs)) {
    console.log(`    ${String(n).padStart(6)}  ${razon}`);
  }
  if (!detallar) return;

  const mostrados = todos ? docs : docs.slice(0, IDS_A_MOSTRAR);
  console.log('    ── ids ──');
  for (const d of mostrados) {
    console.log(`    ${d.id}  reason=${d.razon ?? '(sin razón)'}`);
  }
  const restantes = docs.length - mostrados.length;
  if (restantes > 0) {
    console.log(`    … y ${restantes} más. Para la lista completa: --ids`);
  }
}

async function borrarEnBatches(db, docs) {
  let borrados = 0;
  let yaNoEstaban = 0;
  let procesados = 0;

  for (const chunk of paginasDe(docs, BATCH_SIZE)) {
    const refs = chunk.map((d) => db.collection('trainer_links').doc(d.id));

    // Se releen JUSTO ANTES de borrar para poder informar un número verdadero.
    // `getAll` es una sola llamada, no N.
    const snaps = await db.getAll(...refs);
    const existian = new Set(
      snaps.filter((sn) => sn.exists).map((sn) => sn.id),
    );

    const batch = db.batch();
    for (const ref of refs) batch.delete(ref);
    await batch.commit();

    const reales = contarBorradosReales(chunk, existian);
    borrados += reales;
    yaNoEstaban += chunk.length - reales;
    procesados += chunk.length;
    console.log(`  ✗ ${procesados}/${docs.length} procesados — ${borrados} borrados`);
  }

  if (yaNoEstaban > 0) {
    // No es un error: la CF purga en paralelo y hace exactamente esto.
    console.log(`  ℹ ${yaNoEstaban} ya no existían al momento de borrar.`);
  }
  return { borrados, yaNoEstaban };
}

/**
 * Lee los `terminated` PAGINANDO por ID DE DOCUMENTO.
 *
 * El `.get()` pelado traía todo de una: el Admin SDK bufferea el resultado
 * entero y acá además se retiene un objeto por doc. Con decenas de miles la
 * corrida moría por DEADLINE_EXCEEDED o por memoria antes de imprimir una sola
 * línea — o sea que fallaba justo en el escenario de backlog acumulado para el
 * que este script existe.
 *
 * POR QUÉ EL CURSOR VA POR `__name__` Y NO POR `requestedAt`, que es lo que
 * parecía natural: una igualdad + `orderBy` sobre OTRO campo es una query
 * COMPUESTA y Firestore la rechaza con FAILED_PRECONDITION hasta que exista el
 * índice. Ordenar por el id de documento la sirve el índice AUTOMÁTICO de un
 * solo campo —`__name__` es su desempate—, así que no hace falta declarar nada
 * ni correr `deploy --only firestore:indexes`, que además trae prompt de
 * borrado de los huérfanos que viven en prod a propósito
 * (docs/firestore-indexes.md).
 *
 * ⚠️  EL EMULADOR NO VALIDA ESTO. La primera versión de esta paginación
 *     ordenaba por `requestedAt`, pasó una prueba con 1200 docs sembrados en el
 *     emulador, y reventó contra producción en la primera query: el emulador de
 *     Firestore NO exige índices compuestos. Para este script, un dry-run
 *     verde en el emulador no dice nada sobre índices.
 */
async function leerTerminados(db, FieldPath, onPagina) {
  let cursor = null;
  let total = 0;
  for (;;) {
    let q = db
      .collection('trainer_links')
      .where('status', '==', 'terminated')
      .orderBy(FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    onPagina(snap.docs);
    total += snap.size;
    process.stdout.write(`\r  leídos ${total}...`);

    if (snap.size < PAGE_SIZE) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  if (total > 0) process.stdout.write('\n');
  return total;
}

async function main() {
  const { apply, dryRunExplicito, incluirAmbiguos, ids } = parseArgs(process.argv);

  // El cartel ANTES de inicializar nada. `bannerDeProduccion` es el del repo
  // —el que dice «IS PRODUCTION. The name says "dev"; the data is real» y
  // nombra la retención de 28 días—, no uno casero: imprimir `treino-dev` a
  // secas es exactamente el caso que AGENTS.md §11.1 abre («treino-dev SUENA a
  // entorno descartable»). Se calla sólo si Firestore está desviado al
  // emulador, que es el único servicio que este script toca.
  const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
    contraEmulador: contraEmuladorDe(['firestore']),
  });
  if (bannerProd) console.warn(bannerProd);

  const { app, contexto } = inicializarAdmin();

  // Y además el proyecto RESUELTO, que puede no coincidir con el que estimó
  // `projectIdObjetivo()` de arriba: éste sale de la credencial que realmente
  // se cargó.
  const proyecto = contexto ? proyectoDe(contexto) : '(app ya inicializada)';
  console.log('═'.repeat(66));
  console.log(`  PROYECTO: ${proyecto}`);
  console.log(`  MODO:     ${apply ? '⚠️  APPLY — VA A BORRAR' : 'dry-run (no escribe nada)'}`);
  if (dryRunExplicito && process.argv.includes('--apply')) {
    // Decirlo fuerte: alguien pidió las dos cosas y se le concedió la segura.
    console.log('  NOTA:     pediste --apply Y --dry-run. Gana --dry-run: NO se borra nada.');
  }
  if (incluirAmbiguos) {
    console.log('  AMBIGUOS: INCLUIDOS en el borrado');
  }
  console.log('═'.repeat(66));

  const db = getFirestore(app);

  // `acceptedAt` se filtra en memoria: Firestore no consulta por ausencia de
  // campo. La lectura va paginada — ver `leerTerminados`.
  console.log('');
  const grupos = { borra: [], ambiguo: [], conserva: [] };
  const total = await leerTerminados(db, FieldPath, (docs) => {
    for (const doc of docs) {
      const data = doc.data();
      grupos[clasificar(data)].push({
        id: doc.id,
        razon: data.terminationReason,
      });
    }
  });

  console.log(`Vínculos con status == 'terminated': ${total}`);

  // `detallar` TAMBIÉN acá, y es el cambio que importa: antes sólo se listaban
  // los ids del grupo AMBIGUO —el que NO se toca— y el grupo BORRA salía como
  // un número pelado. O sea que el paso de revisión que justifica la existencia
  // del dry-run no se podía hacer sobre los documentos que efectivamente se
  // destruyen.
  imprimirGrupo(
    'BORRA     (acceptedAt null + rechazo/cancelación)',
    grupos.borra,
    { detallar: true, todos: ids },
  );
  imprimirGrupo(
    'AMBIGUO   (acceptedAt null, razón distinta o ausente)',
    grupos.ambiguo,
    { detallar: true, todos: ids },
  );
  imprimirGrupo('CONSERVA  (acceptedAt presente — vínculo real)', grupos.conserva);

  if (grupos.ambiguo.length && !incluirAmbiguos) {
    console.log(
      '\n  ⚠️  Los AMBIGUOS quedan intactos. Un vínculo real viejo pudo perder su\n' +
      '     `acceptedAt` (ver el header de este archivo). Miralos uno por uno antes\n' +
      '     de sumarlos con --incluir-ambiguos.',
    );
  }

  const aBorrar = incluirAmbiguos
    ? [...grupos.borra, ...grupos.ambiguo]
    : grupos.borra;

  if (!apply) {
    console.log(
      `\nDRY-RUN: se borrarían ${aBorrar.length} documentos. ` +
      'Nada se escribió.\nPara ejecutar: --apply',
    );
    return;
  }

  if (aBorrar.length === 0) {
    console.log('\nNada que borrar.');
    return;
  }

  console.log(`\nBorrando ${aBorrar.length} documentos...`);
  const { borrados, yaNoEstaban } = await borrarEnBatches(db, aBorrar);
  console.log(
    `\nListo. ${borrados} documentos borrados` +
    (yaNoEstaban > 0 ? `, ${yaNoEstaban} ya no existían.` : '.'),
  );
}

module.exports = {
  clasificar,
  desglosePorRazon,
  parseArgs,
  contarBorradosReales,
  paginasDe,
};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
