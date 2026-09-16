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
  let aEscribir = 0;
  let yaEstaban = 0;
  let ausentes = 0;
  let batch = db.batch();
  let enBatch = 0;

  for (const [path, datas] of porSesion) {
    const ref = db.doc(path);
    const snap = await ref.get();
    if (!snap.exists) {
      // Reportes huérfanos: la sesión se borró y la subcolección quedó. No se
      // crea el doc — un backfill no puede resucitar lo que alguien borró.
      ausentes++;
      continue;
    }

    const nuevo = contar(datas);
    if (iguales(snap.data()?.feedbackCounts, nuevo)) {
      yaEstaban++;
      continue;
    }

    aEscribir++;
    if (!escribir) continue;

    batch.update(ref, { feedbackCounts: nuevo });
    if (++enBatch >= PAGE_SIZE) {
      await batch.commit();
      batch = db.batch();
      enBatch = 0;
    }
  }

  if (escribir && enBatch > 0) await batch.commit();

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
