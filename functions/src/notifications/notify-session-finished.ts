/**
 * notifyOnSessionFinished — Cloud Function for TREINO.
 *
 * Dispara en `users/{uid}/sessions/{sessionId}` cuando una sesión pasa a
 * terminada, y le avisa al PF vinculado — diciéndole **qué hay adentro**.
 *
 * ## Una notificación por sesión, no una por nota
 *
 * El pedido era que el PF se entere de las notas que le deja el alumno. La
 * salida obvia —notificar cada `kind: 'comment'`— es exactamente lo que el #628
 * rechazó, y con razón: "un comentario común no debería vibrarle el teléfono al
 * PF doce veces por sesión". Doce vibraciones terminan con el PF silenciando la
 * app, y ahí se pierde TODO, incluidas las molestias.
 *
 * Así que el conteo viaja en el cuerpo de este aviso:
 *
 *     Mateo terminó su entrenamiento
 *     Piernas · 1 molestia, 3 notas
 *
 * El PF se entera de que hay algo que leer sin abrir la app, en UNA
 * notificación. La molestia conserva su push inmediato y propio
 * (`notifyOnExerciseFeedback`): para un dolor, esperar al final de la sesión
 * sería tarde.
 *
 * ## ⚠️ El zombi, que es la trampa de este trigger
 *
 * La condición de disparo es la transición `finishedAt: null → no-null`. Pero
 * el barrido de sesiones colgadas (`session_repository.dart`, `getActive`)
 * **también escribe `finishedAt`**: cierra con `now` toda sesión `active` que
 * pasó las 8 horas (`maxWorkoutDuration`), y eso corre cuando el atleta vuelve
 * a abrir la app, que puede ser una semana después.
 *
 * Sin guarda, un entreno que el alumno abandonó el martes le avisaría al PF el
 * domingo que "Mateo terminó su entrenamiento". Falso, y encima a destiempo.
 *
 * `wasFullyCompleted` NO sirve para distinguirlos: vale `false` tanto en el
 * barrido como en `abandonSession()`, que es un abandono deliberado y sí
 * merece aviso — es justamente el caso donde el alumno dejó una nota y se fue.
 *
 * La señal es `closedBySweep`, que el propio barrido escribe. Es explícita.
 *
 * ⚠️ La PRIMERA versión de este archivo deducía el barrido por el TIEMPO
 * ("cerrada más de 8h después de empezar ⇒ la cerró el barrido") y esa premisa
 * es FALSA. El barrido tiene dos ramas:
 *
 *     final aCerrar = vencio ? snap.docs : snap.docs.skip(1).toList();
 *
 * Cuando la sesión más nueva sigue viva, cierra **todas las duplicadas sin
 * mirarles la edad**. Dos sesiones abiertas con minutos de diferencia —una del
 * reloj, otra del teléfono— se cierran a los minutos de empezar, y la
 * heurística de las 8h las deja pasar como si el alumno hubiera terminado.
 * Lo encontró Codex en el #1154.
 *
 * El tiempo transcurrido quedó SÓLO como fallback para las sesiones que ya
 * están en la base cerradas por clientes anteriores a la marca, que nunca la
 * van a tener.
 *
 * ## Por qué lee la subcolección y no `feedbackCounts`
 *
 * El doc de sesión YA trae `feedbackCounts`, que escribe
 * `maintainSessionFeedbackCounters`. Usarlo sería gratis. No se usa igual:
 * las dos funciones corren en paralelo y no hay orden garantizado entre ellas.
 * Un reporte escrito segundos antes de cerrar la sesión puede no estar contado
 * todavía, y el aviso diría "sin notas" sobre una sesión que tiene una. Un
 * mensaje que tranquiliza sin ser cierto es peor que ninguno (AGENTS.md §11.1).
 *
 * La subcolección es la fuente de verdad. Es UNA lectura extra por sesión
 * terminada, y se paga a propósito.
 *
 * ## ⚠️ Dato de salud
 *
 * El cuerpo dice CUÁNTAS molestias hay. Nunca el `text` ni el `photoUrl`. Esta
 * notificación se lee en la pantalla bloqueada y su título+cuerpo quedan
 * persistidos en el inbox del PF, que el cascade de borrado de cuenta NO barre
 * (QA-CMP-008). Que quede "hubo 2 molestias" es aceptable; que quede dónde le
 * dolía, no. Mismo criterio que `notify-exercise-feedback.ts`, y si algún día
 * se enriquece este cuerpo hay que cerrar QA-CMP-008 ANTES.
 *
 * ## `prefKey`, a diferencia de la molestia
 *
 * Lleva `prefKey: 'sesion_terminada'`. Un PF con veinte alumnos puede querer
 * apagarlo y es legítimo: nadie se lastima por no enterarse de que alguien
 * entrenó. La molestia NO lleva prefKey justamente porque apagarla sí tiene
 * consecuencias.
 *
 * Región southamerica-east1 por ADR-PN-005.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Messaging } from "firebase-admin/messaging";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

type SessionData = Record<string, unknown>;

/**
 * Espejo a mano de `maxWorkoutDuration` en
 * `lib/features/workout/application/session_duration.dart`. Si cambia allá,
 * cambia acá: de este número depende distinguir un entreno real de uno que
 * cerró el barrido de colgadas.
 */
const MAX_WORKOUT_MS = 8 * 60 * 60 * 1000;

function aFecha(valor: unknown): Date | null {
  if (valor instanceof Timestamp) return valor.toDate();
  if (valor instanceof Date) return valor;
  return null;
}

/**
 * El texto de los reportes, o `null` si no hay ninguno.
 *
 * Exportada para testearla sola: es la parte con más ramas y la que más fácil
 * se rompe (plurales, el orden, el caso cero).
 */
export function resumenDeReportes(
  molestias: number,
  notas: number,
): string | null {
  const partes: string[] = [];
  if (molestias > 0) {
    partes.push(molestias === 1 ? "1 molestia" : `${molestias} molestias`); // i18n
  }
  if (notas > 0) {
    partes.push(notas === 1 ? "1 nota" : `${notas} notas`); // i18n
  }
  return partes.length > 0 ? partes.join(", ") : null;
}

/** Handler puro, extraído para jest (espeja notifyOnExerciseFeedback). */
export async function notifyOnSessionFinishedHandler(
  app: App,
  athleteUid: string,
  sessionId: string,
  before: SessionData,
  after: SessionData,
  messaging?: Messaging,
): Promise<void> {
  // ── Guarda 1: LA TRANSICIÓN, no cualquier update ──────────────────────────
  // Sin esto, cada escritura posterior sobre la sesión —una corrección, un
  // contador, el propio `feedbackCounts` de la otra CF— volvería a notificar.
  const antes = aFecha(before.finishedAt);
  const despues = aFecha(after.finishedAt);
  if (antes !== null || despues === null) return;

  // ── Guarda 2: el barrido de colgadas, no el atleta ────────────────────────
  //
  // Dos señales, y el orden importa porque sólo la primera es CONFIABLE.
  //
  // `closedBySweep` lo escribe el propio barrido (`session_repository.getActive`).
  // Es explícito y no se deduce de nada.
  //
  // El tiempo transcurrido es el FALLBACK para las sesiones que cerró un
  // cliente anterior a esa marca, que ya están en la base y nunca la van a
  // tener. Es una heurística y no alcanza sola: cuando la sesión más nueva
  // sigue viva, el barrido cierra las duplicadas SIN mirarles la edad
  // (`aCerrar = snap.docs.skip(1)`), así que una colgada de minutos se le
  // escapa. La primera versión de este archivo tenía SÓLO esta mitad — lo
  // encontró Codex en el #1154.
  if (after.closedBySweep === true) {
    logger.info(
      "notifyOnSessionFinished: cerrada por el barrido (marcada), no se notifica",
      { athleteUid, sessionId },
    );
    return;
  }

  const inicio = aFecha(after.startedAt);
  if (inicio !== null && despues.getTime() - inicio.getTime() > MAX_WORKOUT_MS) {
    logger.info(
      "notifyOnSessionFinished: excede la duración máxima, la cerró un barrido " +
        "de un cliente viejo (sin marca), no se notifica",
      { athleteUid, sessionId },
    );
    return;
  }

  const db = getFirestore(app);

  // ── Guarda 3: a quién, y el grant NO es prueba de vínculo ──────────────────
  // Mismo predicado de dos partes que `notify-exercise-feedback.ts`: el
  // `session_shares` es client-writable y casi no está validado, así que
  // cualquiera puede apuntarlo al uid que quiera. Se exige un `trainer_links`
  // vivo para ese par exacto.
  const shareSnap = await db.collection("session_shares").doc(athleteUid).get();
  const trainerId = shareSnap.data()?.trainerId as string | undefined;
  if (!shareSnap.exists || !trainerId) {
    // Estado normal —el alumno no tiene PF—, no una falla.
    logger.info("notifyOnSessionFinished: sin PF vinculado", {
      athleteUid,
      sessionId,
    });
    return;
  }

  const linkSnap = await db
    .collection("trainer_links")
    .where("athleteId", "==", athleteUid)
    .where("trainerId", "==", trainerId)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (linkSnap.empty) {
    logger.warn(
      "notifyOnSessionFinished: grant forjado o vencido, no se notifica",
      { athleteUid, trainerId, sessionId },
    );
    return;
  }

  // ── Qué hay adentro ───────────────────────────────────────────────────────
  const feedbackSnap = await db
    .collection("users")
    .doc(athleteUid)
    .collection("sessions")
    .doc(sessionId)
    .collection("exerciseFeedback")
    .get();

  let molestias = 0;
  let notas = 0;
  for (const doc of feedbackSnap.docs) {
    const kind = doc.data().kind;
    if (kind === "discomfort") molestias++;
    else if (kind === "comment") notas++;
  }

  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(athleteUid)
    .get();
  const athleteName: string =
    (profileSnap.data()?.displayName as string | undefined) ?? "Un atleta"; // i18n

  const routineName = (after.routineName as string | undefined) ?? "";
  const resumen = resumenDeReportes(molestias, notas);
  const body = resumen ? `${routineName} · ${resumen}` : routineName; // i18n

  await sendFcm(
    app,
    {
      uids: [trainerId],
      // `kind` y `prefKey` NO son lo mismo y por eso no se parecen: el kind es
      // el discriminador estable del historial y del cliente FCM (inglés,
      // kebab, como sus hermanos `chat-message` y `overdue-payment`); el
      // prefKey es la clave de la fila de Ajustes (`kNotifTypes`, castellano).
      kind: "session-finished",
      notification: {
        title: `${athleteName} terminó su entrenamiento`, // i18n
        body,
      },
      // El destino es LA SESIÓN. Existe desde
      // `/coach/athlete/:athleteId/session/:sessionId`; antes de esa ruta este
      // aviso habría caído en la ficha larga del alumno, que es el defecto que
      // los tres avisos anteriores tenían.
      data: {
        deepLink: `/coach/athlete/${athleteUid}/session/${sessionId}`,
        athleteUid,
        sessionId,
      },
      actorUid: athleteUid,
      // A diferencia de la molestia, ésta SÍ se puede apagar. Ver el header.
      prefKey: "sesion_terminada",
    },
    messaging,
  );
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const notifyOnSessionFinished = onDocumentUpdated(
  {
    document: "users/{uid}/sessions/{sessionId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before.data() as SessionData | undefined;
    const after = event.data?.after.data() as SessionData | undefined;
    if (!before || !after) return;

    await notifyOnSessionFinishedHandler(
      ensureApp(),
      event.params.uid,
      event.params.sessionId,
      before,
      after,
    );
  },
);
