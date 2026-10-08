#!/usr/bin/env node
/**
 * backfill_session_feedback_counts.js
 *
 * Llena `feedbackCounts` en los docs de sesión que ya existían cuando se
 * agregó el agregado (`maintainSessionFeedbackCounters`).
 *
 * Sin esto, el historial del PF no marca NADA de lo anterior al deploy: las
 * molestias y notas viejas quedan invisibles en la lista, y el PF concluye que
 * esas sesiones no traen nada adentro. Ése es el modo de falla que importa —
 * no "falta un dato", sino "la pantalla afirma que no hubo dolor".
 *
 * ── Por qué recorre los REPORTES y no las sesiones ──────────────────────────
 *
 * Lo obvio sería iterar `users/*​/sessions/*` y leerle a cada una su
 * subcolección. Eso es una lectura de subcolección POR SESIÓN, y la enorme
 * mayoría de las sesiones no tiene ningún reporte: se pagarían millones de
 * lecturas para escribir `{}` en casi todas.
 *
 * Un `collectionGroup('exerciseFeedback')` invierte el recorrido: toca sólo
 * los reportes que EXISTEN, que son pocos. Las sesiones sin reportes no
 * necesitan backfill — el modelo Dart ya default-ea a `{}` cuando el campo
 * falta, y el mapa vacío y el campo ausente significan lo mismo: ningún
 * reporte.
 *
 * ⚠️ La lógica de conteo es un ESPEJO A MANO de `aggregateFeedbackCounts` en
 * `functions/src/notifications/maintain-session-feedback-counters.ts`. No hay
 * nada que las sincronice. Si cambian los kinds, van las dos — y también
 * `FeedbackCountsConverter` del lado Dart.
 *
 * ── Seguridad ───────────────────────────────────────────────────────────────
 *
 * DRY-RUN POR DEFECTO. Sin `--write` no escribe una sola vez: cuenta y reporta.
 * El backfill más nuevo del repo (`backfill_user_public_profiles.js`) no tiene
 * ni dry-run ni cartel, y acá no alcanza con seguir esa convención: esto toca
 * el doc de sesión de TODOS los usuarios y el dato que escribe es una
 * afirmación sobre salud.
 *
 * Credencial: la única puerta (#834), `scripts/lib/admin.js`. Sin
 * `$TREINO_SA_KEY` falla cerrado; contra el emulador no pide nada.
 *
 * Uso:
 *   # contra el emulador, sin variables
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_session_feedback_counts.js --write
 *
 *   # contra producción: primero el dry-run, SIEMPRE
 *   GOOGLE_APPLICATION_CREDENTIALS=$TREINO_SA_KEY node scripts/backfill_session_feedback_counts.js
 *   GOOGLE_APPLICATION_CREDENTIALS=$TREINO_SA_KEY node scripts/backfill_session_feedback_counts.js --write
 *
 * ── Cómo se verificó, para que se pueda repetir ─────────────────────────────
 *
 * Contra un emulador, sembrando cuatro casos y corriendo dry-run → write →
 * dry-run otra vez. Los cuatro son el control de los otros: sin el B no se
 * distingue "no toca las sesiones sin reportes" de "no toca nada", y sin el C
 * no se ve que la segunda corrida sea gratis.
 *
 *   A · sesión con 2 molestias + 1 nota y SIN el mapa  → se llena
 *   B · sesión sin ningún reporte                      → NO se toca (queda ausente)
 *   C · sesión con el mapa ya correcto                 → no se reescribe
 *   D · reportes huérfanos, sesión borrada             → no se resucita
 *   E · un reporte nuevo entre el escaneo y la escritura → se cuenta el nuevo
 *
 * El E es el que agregó el recuento transaccional (P2 de Codex en el #1153).
 * Para reproducirlo hace falta escribir en la subcolección DESPUÉS de que el
 * paso 1 haya terminado y antes del commit; sin esa ventana forzada, el caso
 * pasa por casualidad y el test no prueba nada.
 *
 * Medido: dry-run reportó 1 pendiente y no escribió; `--write` escribió 1; la
 * segunda corrida dio 0 pendientes y 2 "ya estaban correctas".
 */

'use strict';

const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { FieldPath, getFirestore } = require('firebase-admin/firestore');

// Espejo a mano de FEEDBACK_KINDS en
// functions/src/notifications/maintain-session-feedback-counters.ts
const FEEDBACK_KINDS = ['discomfort', 'comment'];

const PAGE_SIZE = 500;

/** Idéntica a `aggregateFeedbackCounts` del CF. Las claves en cero no se emiten. */
function contar(docs) {
  const counts = {};
  for (const data of docs) {
    const kind = data.kind;
    if (typeof kind !== 'string' || !FEEDBACK_KINDS.includes(kind)) continue;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

function iguales(a, b) {
  const ka = Object.keys(a ?? {}).sort();
  const kb = Object.keys(b ?? {}).sort();
  if (ka.length !== kb.length) return false;
  return ka.every((k, i) => k === kb[i] && a[k] === b[k]);
}

async function main() {
  const escribir = process.argv.includes('--write');

  const { app, contexto } = inicializarAdmin();
  const projectId = proyectoDe(contexto);
  const banner = bannerDeProduccion(projectId, {
    contraEmulador: contexto.modo === 'emulador',
  });
  if (banner) console.warn(banner);

  console.log(`proyecto: ${projectId}  ·  modo: ${contexto.modo}`);
  console.log(
    escribir
      ? '⚠  --write: ESTO ESCRIBE.'
      : 'dry-run (sin --write): no se escribe nada.',
  );

  const db = getFirestore(app);

  // Paso 1 — juntar los reportes por sesión. Se pagina por `__name__` para no
  // traerse toda la colección de golpe: con muchos reportes, un `.get()` pelado
  // se come la memoria del proceso y falla lejos de acá.
  const porSesion = new Map(); // path del doc de sesión -> array de datas
  let ultimo = null;
  let leidos = 0;

  for (;;) {
    let q = db
      .collectionGroup('exerciseFeedback')
      .orderBy(FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (ultimo) q = q.startAfter(ultimo);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      // .../sessions/{sessionId}/exerciseFeedback/{id} → el padre de la subcolección
      const sessionRef = doc.ref.parent.parent;
      if (!sessionRef) continue;
      const lista = porSesion.get(sessionRef.path) ?? [];
      lista.push(doc.data());
      porSesion.set(sessionRef.path, lista);
      leidos++;
    }

    ultimo = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < PAGE_SIZE) break;
  }

  console.log(
    `reportes leídos: ${leidos}  ·  sesiones con reportes: ${porSesion.size}`,
  );

  // Paso 2 — escribir sólo lo que DIFIERE. Una sesión que ya tiene el mapa
  // correcto (porque el CF ya la tocó) no se reescribe: el backfill se puede
  // volver a correr sin costo y sin tocar `updatedAt` de nada.
  //
  // ⚠️ La escritura RECUENTA dentro de una transacción, y no escribe lo que
  // contó el paso 1. Ese conteo es una FOTO: si entre el escaneo y la
  // escritura alguien crea o borra un reporte, escribir la foto pisa el valor
  // correcto con uno viejo.
  //
  // Y no se arregla solo, que es lo que lo vuelve un P2 y no un detalle: el
  // trigger que mantiene el agregado (`maintainSessionFeedbackCounters`)
  // escucha la SUBCOLECCIÓN, así que tocar el doc padre NO lo redispara. El
  // contador queda mintiendo hasta el próximo reporte de esa misma sesión —
  // que puede no llegar nunca, porque son sesiones viejas y ya terminadas.
  // O sea: el backfill que existe para arreglar contadores ausentes podía
  // dejar contadores FALSOS, que es estrictamente peor (el modelo Dart lee el
  // mapa ausente como "ningún reporte", igual que un mapa en cero, pero un
  // conteo viejo afirma un número que nadie va a corregir).
  //
  // Lo del paso 1 se usa sólo para saber A QUÉ SESIONES IR. Firestore
  // reintenta la transacción sola si algo cambió en el medio.
  let aEscribir = 0;
  let yaEstaban = 0;
  let ausentes = 0;

  for (const [path, datas] of porSesion) {
    const ref = db.doc(path);

    if (!escribir) {
      // Dry-run: compara contra la foto del paso 1 y no abre transacción. Es
      // un informe de "qué pasaría", no la escritura — y abrir una transacción
      // por sesión sólo para contar duplicaría el costo de una corrida cuyo
      // punto es ser barata y repetible.
      const snap = await ref.get();
      if (!snap.exists) {
        ausentes++;
      } else if (iguales(snap.data()?.feedbackCounts, contar(datas))) {
        yaEstaban++;
      } else {
        aEscribir++;
      }
      continue;
    }

    // Todas las lecturas ANTES de la escritura: Firestore lo exige dentro de
    // una transacción.
    const resultado = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        // Reportes huérfanos: la sesión se borró y la subcolección quedó. No se
        // crea el doc — un backfill no puede resucitar lo que alguien borró.
        return 'ausente';
      }
      const reportes = await tx.get(ref.collection('exerciseFeedback'));
      const nuevo = contar(reportes.docs.map((d) => d.data()));
      if (iguales(snap.data()?.feedbackCounts, nuevo)) return 'igual';
      tx.update(ref, { feedbackCounts: nuevo });
      return 'escrita';
    });

    if (resultado === 'ausente') ausentes++;
    else if (resultado === 'igual') yaEstaban++;
    else aEscribir++;
  }

  console.log('');
  console.log(`ya estaban correctas: ${yaEstaban}`);
  console.log(`sesiones borradas (reportes huérfanos): ${ausentes}`);
  console.log(
    escribir
      ? `✔ escritas: ${aEscribir}`
      : `pendientes de escribir: ${aEscribir}  → volvé a correr con --write`,
  );
}

main().catch((err) => {
  console.error('Backfill FAILED:', err);
  process.exit(1);
});
