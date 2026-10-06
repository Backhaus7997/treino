'use strict';

/**
 * scripts/audit_forged_trainer_links.js
 *
 * Vínculos de `trainer_links` cuyo `trainerId` NO es un entrenador.
 *
 * ⚠️  `treino-dev` ES PRODUCCIÓN. Ahí viven los pagos, turnos y sesiones de
 *     usuarios reales. Con `--apply` este script BORRA documentos. Leé
 *     AGENTS.md § Entornos antes.
 *
 * ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
 *
 * El `create` de `trainer_links` no validaba el rol del `trainerId`
 * (firestore.rules ~1368, cerrado en el mismo PR que trae este script), así que
 * cualquier cuenta podía nombrar a CUALQUIER uid como su entrenador. La regla
 * nueva y el chequeo de `promote-link.ts` frenan lo que viene; los docs que YA
 * están en la base no los toca nadie, y uno `active` sigue surtiendo efecto:
 *
 *   · `hasActiveTrainerLink` (subscriptions/athlete-paywall-enforced.ts) apaga
 *     `athletePaywallEnforced` del alumno → tope del plan gratis salteado.
 *   · `session_shares` le da al "entrenador" lectura de sesiones, setLogs y
 *     mediciones del alumno.
 *   · `reviews` gatea en `status in ['active','paused']`, así que un `paused`
 *     trucho habilita reseñas forjadas (el camino de QA-SEC-002).
 *
 * ── POR QUÉ BORRA Y NO TERMINA ──────────────────────────────────────────────
 *
 * Un `delete` deja que los triggers que ya existen repartan la reparación, y
 * verificado uno por uno es MÁS limpio que escribir `terminated`:
 *
 *   notifyOnLinkChange          corta en `if (!after)` (~267) → NO manda aviso.
 *                               Un `terminated` sí avisaría, y el texto genérico
 *                               ("La vinculación … fue finalizada") describe mal
 *                               un vínculo que nunca existió — el defecto de
 *                               AGENTS.md §11.1.
 *   syncAthletePaywallOnTrainerLink
 *                               `linkActivityChanged(before, undefined)` da true
 *                               para un `active`, así que RECALCULA y le vuelve
 *                               a prender el paywall al alumno.
 *   syncSessionShareOnTrainerLink
 *                               su early-return (~299) pide
 *                               `before.status === 'terminated'`, que un `active`
 *                               no cumple: cae al camino de abajo y REVOCA el
 *                               share (chequeando antes que sea de este
 *                               trainerId, así que no pisa el del PF real).
 *
 * O sea: borrar el doc apaga el efecto sin avisos raros y sin tocar `users`.
 * NO hace falta escribir `athletePaywallEnforced` a mano — hacerlo sería pisar
 * un campo CF-only por fuera de su dueño.
 *
 * ⚠️  Los triggers tienen que estar DESPLEGADOS para que la reparación corra.
 *     Si corrés esto antes del deploy, los docs se van pero el
 *     `athletePaywallEnforced` del alumno queda en `false` hasta el barrido
 *     diario (`sweepAthletePaywall`). No es un agujero nuevo —es el estado de
 *     hoy— pero conviene desplegar primero.
 *
 * ── LOS TRES GRUPOS ─────────────────────────────────────────────────────────
 *
 *   TRUCHO    el doc de `users/{trainerId}` existe y su `role` dice algo
 *             distinto de 'trainer'  → se borra con --apply
 *   AMBIGUO   no hay doc de usuario, o el doc no tiene `role`  → NO se toca
 *   OK        role == 'trainer'  → NO se toca
 *
 * El AMBIGUO no se borra por el mismo motivo por el que `promote-link.ts` falla
 * ABIERTO ante un rol ausente: un PF legacy sin el campo existe de verdad, y
 * `paywallEnforcedFor` en las rules ya usa ese default. Confundir "no me consta"
 * con "es trucho" acá significa cortarle el vínculo a un entrenador real y a su
 * alumno. Se listan para que los mire una persona.
 *
 * Usage:
 *   # Dry-run (DEFAULT — no escribe nada, sólo informa):
 *   node scripts/audit_forged_trainer_links.js
 *
 *   # Borrar los TRUCHO de verdad:
 *   node scripts/audit_forged_trainer_links.js --apply
 *
 *   # Listar todos los ids en vez de los primeros 20:
 *   node scripts/audit_forged_trainer_links.js --ids > /tmp/truchos.txt
 *
 * Ante flags en conflicto gana la que NO destruye: `--apply --dry-run` NO borra.
 *
 * Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` falla cerrado;
 * contra el emulador no pide nada. Ver scripts/lib/admin.js.
 */

const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { FieldPath, getFirestore } = require('firebase-admin/firestore');

/**
 * Los estados NO terminales, o sea los que todavía surten efecto.
 *
 * Se recorren DE A UNO, con una query de igualdad por estado, y no con un
 * `where('status','in',[...])`. No es estilo: una igualdad más `orderBy` sobre
 * otro campo es una query COMPUESTA y Firestore la rechaza con
 * FAILED_PRECONDITION hasta que exista el índice. Ordenando por
 * `FieldPath.documentId()` la sirve el índice AUTOMÁTICO de un solo campo, que
 * es el patrón que `cleanup_rejected_links.js` ya probó contra producción.
 *
 * Y el emulador NO valida esto: un dry-run verde en local no dice nada sobre
 * índices (está escrito en el header de ese otro script, le costó una corrida).
 */
const ESTADOS_VIVOS = ['pending', 'active', 'paused'];

/** Límite duro de `WriteBatch` en Firestore. */
const BATCH_SIZE = 500;

/** Cuántos docs se leen por página. */
const PAGE_SIZE = 500;

/** Cuántos ids se listan por grupo antes de cortar. Con `--ids`, todos. */
const IDS_A_MOSTRAR = 20;

/**
 * Parsea las flags. Pura y exportada para testear la compuerta sin Firestore.
 *
 * REGLA: ante flags en conflicto, GANA LA QUE NO DESTRUYE. Mismo criterio que
 * `cleanup_rejected_links.js`, y por el mismo motivo: ocho scripts de este
 * directorio usan `--dry-run` como LA flag que frena las escrituras, así que no
 * puede ser decorativa justo en los que borran.
 *
 * @param {string[]} argv - `process.argv` completo.
 */
function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  const desconocidas = [...flags].filter(
    (f) => !['--apply', '--dry-run', '--ids'].includes(f),
  );
  if (desconocidas.length) {
    console.error(`Flags desconocidas: ${desconocidas.join(', ')}`);
    process.exit(2);
  }
  const dryRunExplicito = flags.has('--dry-run');
  return {
    apply: flags.has('--apply') && !dryRunExplicito,
    dryRunExplicito,
    ids: flags.has('--ids'),
  };
}

/**
 * Clasifica un vínculo según el doc de usuario de su `trainerId`.
 *
 * Pura y exportada para testearla sin Firestore.
 *
 * @param {{exists: boolean, role?: unknown}|undefined} usuario - lo que se leyó
 *        de `users/{trainerId}`. `undefined` o `{exists:false}` = no hay doc.
 * @returns {'trucho'|'ambiguo'|'ok'}
 */
function clasificar(usuario) {
  if (!usuario || !usuario.exists) return 'ambiguo';
  const role = usuario.role;
  if (role === undefined || role === null || role === '') return 'ambiguo';
  return role === 'trainer' ? 'ok' : 'trucho';
}

/** Cuenta por una clave, con `(ninguno)` para el faltante. */
function desglosePor(docs, clave) {
  const conteo = new Map();
  for (const d of docs) {
    const v = d[clave] ?? '(ninguno)';
    conteo.set(v, (conteo.get(v) ?? 0) + 1);
  }
  return [...conteo.entries()].sort((a, b) => b[1] - a[1]);
}

function imprimirGrupo(titulo, docs, { detallar = false, todos = false } = {}) {
  console.log(`\n${titulo}: ${docs.length}`);
  if (docs.length === 0) return;
  console.log('    ── por estado ──');
  for (const [v, n] of desglosePor(docs, 'status')) {
    console.log(`    ${String(n).padStart(6)}  ${v}`);
  }
  console.log('    ── por rol del supuesto PF ──');
  for (const [v, n] of desglosePor(docs, 'role')) {
    console.log(`    ${String(n).padStart(6)}  ${v}`);
  }
  if (!detallar) return;

  const mostrados = todos ? docs : docs.slice(0, IDS_A_MOSTRAR);
  console.log('    ── ids ──');
  for (const d of mostrados) {
    console.log(
      `    ${d.id}  status=${d.status}  trainerId=${d.trainerId}` +
      `  role=${d.role ?? '(ninguno)'}`,
    );
  }
  const restantes = docs.length - mostrados.length;
  if (restantes > 0) {
    console.log(`    … y ${restantes} más. Para la lista completa: --ids`);
  }
}

/**
 * Lee los vínculos de un estado, PAGINANDO por id de documento.
 *
 * El `.get()` pelado trae todo de una y el Admin SDK lo bufferea entero: con
 * decenas de miles la corrida muere por DEADLINE_EXCEEDED antes de imprimir una
 * línea, o sea justo en el escenario de backlog para el que sirve el script.
 */
async function leerPorEstado(db, status, onPagina) {
  let cursor = null;
  let total = 0;
  for (;;) {
    let q = db
      .collection('trainer_links')
      .where('status', '==', status)
      .orderBy(FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    onPagina(snap.docs);
    total += snap.size;
    process.stdout.write(`\r  ${status}: leídos ${total}...`);

    if (snap.size < PAGE_SIZE) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  if (total > 0) process.stdout.write('\n');
  return total;
}

/**
 * Resuelve el `role` de cada uid, con UNA llamada por tanda de 300.
 *
 * `getAll` acepta hasta 300 refs. Los uids se deduplican antes: en un backlog
 * real muchos vínculos cuelgan del mismo trainerId, y leer el mismo doc N veces
 * es la diferencia entre una corrida y una factura.
 *
 * @returns {Promise<Map<string, {exists: boolean, role?: unknown}>>}
 */
async function leerRoles(db, uids) {
  const unicos = [...new Set(uids)];
  const porUid = new Map();
  const TANDA = 300;
  for (let i = 0; i < unicos.length; i += TANDA) {
    const tanda = unicos.slice(i, i + TANDA);
    const refs = tanda.map((uid) => db.collection('users').doc(uid));
    const snaps = await db.getAll(...refs);
    for (const sn of snaps) {
      porUid.set(sn.id, { exists: sn.exists, role: sn.data()?.role });
    }
    process.stdout.write(`\r  roles: ${porUid.size}/${unicos.length}...`);
  }
  if (unicos.length > 0) process.stdout.write('\n');
  return porUid;
}

/** Parte `docs` en páginas de a lo sumo `tam`. Pura, para testear el chunking. */
function paginasDe(docs, tam) {
  const paginas = [];
  for (let i = 0; i < docs.length; i += tam) paginas.push(docs.slice(i, i + tam));
  return paginas;
}

/**
 * Cuántos de `chunk` existían de verdad, según los ids leídos en el mismo batch.
 *
 * `batch.delete()` sobre un doc que ya no está resuelve OK, así que contar
 * operaciones emitidas es contar intentos, no borrados. Un script destructivo
 * que informa de más es un cartel tranquilizador sin verificar (AGENTS.md
 * §11.1). Mismo criterio que `cleanup_rejected_links.js`.
 */
function contarBorradosReales(chunk, existian) {
  let n = 0;
  for (const d of chunk) if (existian.has(d.id)) n += 1;
  return n;
}

async function borrarEnBatches(db, docs) {
  let borrados = 0;
  let yaNoEstaban = 0;
  let procesados = 0;

  for (const chunk of paginasDe(docs, BATCH_SIZE)) {
    const refs = chunk.map((d) => db.collection('trainer_links').doc(d.id));
    const snaps = await db.getAll(...refs);
    const existian = new Set(snaps.filter((sn) => sn.exists).map((sn) => sn.id));

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
    console.log(`  ℹ ${yaNoEstaban} ya no existían al momento de borrar.`);
  }
  return { borrados, yaNoEstaban };
}

async function main() {
  const { apply, dryRunExplicito, ids } = parseArgs(process.argv);

  // El cartel ANTES de inicializar nada: lo que frena a alguien tiene que estar
  // en pantalla antes del primer write. Se calla solo si Firestore está
  // desviado al emulador, que es el único servicio que este script toca.
  const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
    contraEmulador: contraEmuladorDe(['firestore']),
  });
  if (bannerProd) console.warn(bannerProd);

  const { app, contexto } = inicializarAdmin();

  const proyecto = contexto ? proyectoDe(contexto) : '(app ya inicializada)';
  console.log('═'.repeat(66));
  console.log(`  PROYECTO: ${proyecto}`);
  console.log(`  MODO:     ${apply ? '⚠️  APPLY — VA A BORRAR' : 'dry-run (no escribe nada)'}`);
  if (dryRunExplicito && process.argv.includes('--apply')) {
    console.log('  NOTA:     pediste --apply Y --dry-run. Gana --dry-run: NO se borra nada.');
  }
  console.log('═'.repeat(66));

  const db = getFirestore(app);

  console.log('\nLeyendo vínculos vivos...');
  const vinculos = [];
  let total = 0;
  for (const status of ESTADOS_VIVOS) {
    total += await leerPorEstado(db, status, (docs) => {
      for (const doc of docs) {
        const data = doc.data();
        vinculos.push({
          id: doc.id,
          status,
          trainerId: data.trainerId,
          athleteId: data.athleteId,
        });
      }
    });
  }
  console.log(`Vínculos en ${ESTADOS_VIVOS.join('/')}: ${total}`);

  if (total === 0) {
    console.log('\nNada que auditar.');
    return;
  }

  console.log('\nResolviendo el rol de cada supuesto PF...');
  const roles = await leerRoles(
    db,
    vinculos.map((v) => v.trainerId).filter((u) => typeof u === 'string' && u),
  );

  const grupos = { trucho: [], ambiguo: [], ok: [] };
  for (const v of vinculos) {
    const usuario = roles.get(v.trainerId);
    grupos[clasificar(usuario)].push({ ...v, role: usuario?.role });
  }

  imprimirGrupo(
    'TRUCHO    (el trainerId tiene un rol que NO es trainer)',
    grupos.trucho,
    { detallar: true, todos: ids },
  );
  imprimirGrupo(
    'AMBIGUO   (sin doc de usuario, o sin campo role)',
    grupos.ambiguo,
    { detallar: true, todos: ids },
  );
  imprimirGrupo('OK        (role == trainer)', grupos.ok);

  if (grupos.ambiguo.length) {
    console.log(
      '\n  ⚠️  Los AMBIGUOS quedan intactos a propósito. Un PF legacy sin `role`\n' +
      '     existe de verdad, y borrarle el vínculo le corta el servicio a él y a\n' +
      '     su alumno. Miralos uno por uno antes de decidir.',
    );
  }

  if (!apply) {
    console.log(
      `\nDRY-RUN: se borrarían ${grupos.trucho.length} documentos. Nada se escribió.` +
      '\nPara ejecutar: --apply',
    );
    return;
  }

  if (grupos.trucho.length === 0) {
    console.log('\nNada que borrar.');
    return;
  }

  console.log(`\nBorrando ${grupos.trucho.length} vínculos truchos...`);
  const { borrados, yaNoEstaban } = await borrarEnBatches(db, grupos.trucho);
  console.log(
    `\nListo. ${borrados} documentos borrados` +
    (yaNoEstaban > 0 ? `, ${yaNoEstaban} ya no existían.` : '.'),
  );
  console.log(
    '\nLos triggers desplegados se encargan del resto: el paywall del alumno se\n' +
    'recalcula y el share de sesiones se revoca. Mirá los logs de Functions.',
  );
}

module.exports = {
  clasificar,
  desglosePor,
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
