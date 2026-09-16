/**
 * maintainSessionFeedbackCounters — Cloud Function for TREINO.
 *
 * Dispara sobre escrituras en
 * `users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}` y mantiene
 * el mapa denormalizado `feedbackCounts` del doc de sesión padre.
 *
 * ## Para qué existe
 *
 * El historial de sesiones del PF tiene que poder marcar, de un vistazo, qué
 * entrenamientos traen una molestia o una nota adentro. Sin un agregado, esa
 * marca cuesta una lectura de subcolección POR FILA: veinte sesiones en
 * pantalla son veinte lecturas cada vez que se abre, y los marcadores aparecen
 * escalonados mientras el PF scrollea. Con el mapa acá, la lista que ya se lee
 * trae la marca puesta y no cuesta una lectura más.
 *
 * ## Por qué RECUENTA en vez de incrementar (igual que W-SOCIAL-COUNTERS-01)
 *
 * Eventarc entrega *at-least-once*. Un `FieldValue.increment()` volvería a
 * aplicar el mismo delta en una redelivery y dejaría el contador desviado para
 * siempre — y un contador de molestias desviado es peor que no tenerlo, porque
 * marca dolor donde no lo hubo. Recontar desde la fuente de verdad y escribir
 * el mapa ABSOLUTO es idempotente. Mismo criterio y misma forma que
 * `maintain-reaction-counters.ts`, `maintain-follow-counters.ts` y las dos
 * cuotas de Storage: en este repo el increment ingenuo ya falló cuatro veces.
 *
 * ## Por qué es una función APARTE de `notifyOnExerciseFeedback`
 *
 * Las dos escuchan el mismo path, y la tentación es juntarlas. No van juntas:
 *
 *   - `notifyOnExerciseFeedback` notifica **sólo** cuando
 *     `kind === 'discomfort'`, y corta en un `return` temprano para todo lo
 *     demás. Este agregado tiene que correr para los DOS kinds — el historial
 *     marca molestias *y* notas.
 *   - Meter el conteo antes de ese gate volvería falso el header de aquel
 *     archivo, que son 110 líneas de doctrina de seguridad abriendo con
 *     "Notifica al PF SOLO cuando `kind === 'discomfort'`". Un comentario que
 *     deja de describir lo que hace su archivo es exactamente lo que AGENTS.md
 *     §11.1 prohíbe.
 *   - Separadas, además, un fallo notificando no se lleva puesto el conteo, ni
 *     al revés.
 *
 * ## Lo que este mapa NO es
 *
 * No es dato de salud: son dos enteros, sin `text` ni `photoUrl`. Vive en el
 * doc de sesión, que el PF vinculado ya puede leer entero
 * (`firestore.rules` ~2473). No agranda la superficie de lectura.
 *
 * Región southamerica-east1 por ADR-PN-005.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

// DEBE espejar `ExerciseFeedbackKind` en
// lib/features/workout/domain/exercise_feedback.dart y la allowlist de kinds
// en firestore.rules. Los tres se mantienen a mano. Un kind que falte acá NO
// rompe la función: se descarta en silencio y su contador queda en cero — el
// mismo modo de falla mudo que documenta `maintain-reaction-counters.ts`.
const FEEDBACK_KINDS = ["discomfort", "comment"] as const;
type FeedbackKind = (typeof FEEDBACK_KINDS)[number];
type FeedbackData = Record<string, unknown>;

export type FeedbackCounts = Partial<Record<FeedbackKind, number>>;

function isFeedbackKind(value: unknown): value is FeedbackKind {
  return (
    typeof value === "string" &&
    (FEEDBACK_KINDS as readonly string[]).includes(value)
  );
}

/**
 * Lógica pura de agregación. Los documentos inválidos se ignoran a la
 * defensiva: las reglas impiden que un cliente los cree, pero las escrituras
 * del Admin SDK se saltean las reglas. Las claves en cero no se emiten.
 */
export function aggregateFeedbackCounts(
  feedback: readonly FeedbackData[],
): FeedbackCounts {
  const counts: FeedbackCounts = {};

  for (const entry of feedback) {
    const kind = entry.kind;
    if (!isFeedbackKind(kind)) continue;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }

  return counts;
}

/**
 * Recomputa el mapa completo transaccionalmente y actualiza SÓLO una sesión
 * que exista, así un evento tardío o redelivered no puede resucitar una sesión
 * borrada.
 */
export async function maintainSessionFeedbackCountersHandler(
  app: App,
  athleteUid: string,
  sessionId: string,
): Promise<void> {
  const db = getFirestore(app);
  const sessionRef = db
    .collection("users")
    .doc(athleteUid)
    .collection("sessions")
    .doc(sessionId);
  const feedbackQuery = sessionRef.collection("exerciseFeedback");

  await db.runTransaction(async (tx) => {
    const [sessionSnap, feedbackSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(feedbackQuery),
    ]);

    if (!sessionSnap.exists) return;

    const counts = aggregateFeedbackCounts(
      feedbackSnap.docs.map((doc) => doc.data()),
    );
    tx.update(sessionRef, { feedbackCounts: counts });
  });

  logger.info("maintainSessionFeedbackCounters: recomputed", {
    athleteUid,
    sessionId,
  });
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const maintainSessionFeedbackCounters = onDocumentWritten(
  {
    document: "users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}",
    region: "southamerica-east1",
  },
  async (event) => {
    await maintainSessionFeedbackCountersHandler(
      ensureApp(),
      event.params.uid,
      event.params.sessionId,
    );
  },
);
