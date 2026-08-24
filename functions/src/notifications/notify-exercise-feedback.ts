/**
 * notifyOnExerciseFeedback — Cloud Function for TREINO.
 *
 * Fires on `users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}`
 * (#628: el canal alumno → PF durante la sesión, ver exercise_feedback.dart).
 *
 * Notifica al PF SOLO cuando `kind === 'discomfort'`. Un `kind: 'comment'` NO
 * dispara push — es el requisito explícito del issue: "un comentario común no
 * debería vibrarle el teléfono al PF doce veces por sesión". El comment queda
 * disponible para que el PF lo lea cuando abre la sesión del alumno; lo único
 * que este trigger le agrega al comment es CERO ruido.
 *
 * Design:
 *   - onDocumentCreated only — un reporte de #628 es create-only del lado del
 *     alumno (firestore.rules: write owner-only, sin update declarado para
 *     este canal), así que no hace falta lidiar con ediciones re-disparando.
 *   - Destinatario: `session_shares/{uid}.trainerId` (uid = el alumno, mismo
 *     doc que gatea el read de exerciseFeedback en firestore.rules ~1738),
 *     PERO CONTRASTADO CONTRA `trainer_links` antes de despachar. Ver abajo:
 *     el grant SOLO no alcanza. Sin doc de grant → nadie a quien notificar, se
 *     sale sin error: el mismo estado que "el alumno todavía no tiene PF
 *     vinculado", no una falla.
 *   - Cuerpo del push: SOLO alumno + ejercicio, NUNCA `text` ni `photoUrl`.
 *     Es dato de salud (kind: discomfort = dolor/lesión declarada) y la
 *     notification aparece en la pantalla bloqueada — cualquier PF cerca del
 *     teléfono del PF la lee sin desbloquear nada. Que abra la app si quiere
 *     el detalle; ahí sí pasa por el read gateado de firestore.rules. Mismo
 *     razonamiento que ya aplica `photoUrl` en el propio modelo (nunca
 *     denormalizar a una colección con lectura más laxa — exercise_feedback.dart
 *     línea ~31), llevado al payload de FCM.
 *   - Todos los strings de cara al usuario en es-AR, mismo criterio que el
 *     resto de los triggers de este directorio.
 *
 * ⚠️ POR QUÉ NO ALCANZA CON EL GRANT, y esto CORRIGE lo que decía este mismo
 * header hasta el commit anterior. La versión vieja argumentaba que era seguro
 * porque "hay grant en session_shares" y "el PF puede leer el reporte si abre
 * la app" son la MISMA condición. La equivalencia es CIERTA y NO VIENE AL CASO:
 * prueba que el destinatario PUEDE leer, nunca que SEA un PF ni que esté
 * vinculado con nadie. Dejar escrito que el código es seguro cuando no lo es es
 * peor que el bug, porque el próximo que pase confía en el comentario.
 *
 * `session_shares/{athleteId}` es CLIENT-WRITABLE y casi no está validado
 * (firestore.rules ~1796: dueño del doc + `trainerId is string`, y se acabó —
 * sin chequeo de rol, sin chequeo de vínculo). O sea que cualquier alumno
 * autenticado apunta SU propio grant al uid que quiera —`userPublicProfiles`
 * es world-readable, los uids se enumeran— y este trigger le mandaba a esa
 * víctima un push con texto que el atacante controla (`exerciseName` también
 * es client-side: firestore.rules ~1885 le limita el LARGO, nunca lo cruza
 * contra un ejercicio real) más una fila permanente en su inbox de
 * notificaciones. Y no hay nada que repare el grant forjado: `sync-session-
 * share.ts` solo corre `onDocumentWritten` sobre `trainer_links/{linkId}`, así
 * que un atacante SIN vínculos no dispara jamás ese trigger.
 *
 * Por eso, entre leer el `trainerId` y despachar, se confirma contra
 * `trainer_links` que el vínculo existe y está `active`. `trainer_links` tiene
 * doc id autogenerado, así que la condición es una QUERY por par
 * (athleteId, trainerId, status) y NO se puede expresar en firestore.rules —
 * las rules hacen `get()` de un path conocido, no queries. Esta CF es la única
 * capa que puede cerrarlo, y por eso se cierra acá y no en las rules.
 *
 * El predicado copia el de `sync-session-share.ts` a propósito: ese CF otorga
 * el share SOLO en la transición a `active` (~:126) y lo borra cuando el
 * vínculo deja de estarlo (~:222). Un share que le sobrevivió a su vínculo es
 * basura por definición —lo dice ese mismo archivo—, así que acá tampoco
 * notifica. Se sale logueado y sin tirar, igual que el camino "no hay grant":
 * un grant vencido no es un error, es estado.
 *
 * ⚠️ RETENCIÓN, y esto es deuda conocida que este archivo HEREDA, no crea:
 * `sendFcm` persiste el título y el cuerpo en `users/{trainerId}/notifications`.
 * Ese inbox es de terceros y el cascade de borrado de cuenta NO lo barre —
 * es QA-CMP-008 en docs/security.md §2.2.1. O sea que la línea "X reportó una
 * molestia en Y" le sobrevive al borrado de la cuenta de X, y también a que X
 * le revoque el grant. Es exactamente por esto que el cuerpo NO lleva el texto
 * del reporte ni la foto: lo único que queda retenido es que hubo una
 * molestia, no qué dijo la persona ni dónde le dolía. Si algún día se
 * enriquece este body, hay que cerrar QA-CMP-008 ANTES.
 *
 * #628.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type FeedbackData = Record<string, unknown>;

/**
 * Pure handler extracted for jest testability (mirrors notifyOnReview / notifyOnChatMessage).
 *
 * @param app          - Admin SDK app.
 * @param athleteUid   - uid del alumno dueño de la sesión (event.params.uid).
 * @param sessionId    - Id de la sesión (event.params.sessionId).
 * @param feedbackData - Datos crudos del documento exerciseFeedback creado.
 * @param messaging    - Instancia de messaging opcional, para inyección en tests.
 */
export async function notifyOnExerciseFeedbackHandler(
  app: admin.app.App,
  athleteUid: string,
  sessionId: string,
  feedbackData: FeedbackData,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  const kind = feedbackData.kind as string | undefined;

  // EL guard del feature: un comment nunca notifica. Se corta ACÁ, antes de
  // leer session_shares ni nada más — un comment no debe gastar ni una
  // lectura de más en el camino hacia una notificación que nunca va a salir.
  if (kind !== "discomfort") {
    logger.info("notifyOnExerciseFeedback: kind is not discomfort, skipping", {
      athleteUid,
      sessionId,
      kind,
    });
    return;
  }

  const exerciseId = feedbackData.exerciseId as string | undefined;
  const exerciseName = feedbackData.exerciseName as string | undefined;

  if (!exerciseId || !exerciseName) {
    logger.warn("notifyOnExerciseFeedback: missing exerciseId or exerciseName", {
      athleteUid,
      sessionId,
      exerciseId,
      exerciseName,
    });
    return;
  }

  const db = admin.firestore(app);

  // Destinatario CANDIDATO: el PF que el grant dice. Candidato y no destinatario
  // a secas — este doc es client-writable y el alumno lo apunta a quien quiera
  // (ver el bloque "POR QUÉ NO ALCANZA CON EL GRANT" del header). Se valida
  // abajo, contra trainer_links, antes de despachar nada.
  const shareSnap = await db.collection("session_shares").doc(athleteUid).get();
  if (!shareSnap.exists) {
    logger.info("notifyOnExerciseFeedback: no session_shares doc, nobody to notify", {
      athleteUid,
      sessionId,
    });
    return;
  }

  const trainerId = shareSnap.data()?.trainerId as string | undefined;
  if (!trainerId) {
    logger.info("notifyOnExerciseFeedback: session_shares doc has no trainerId, skipping", {
      athleteUid,
      sessionId,
    });
    return;
  }

  // LA guarda de seguridad: el grant NO es prueba de vínculo. Se exige un
  // `trainer_links` vivo para ese par exacto. Nombres de campo verificados
  // contra sync-session-share.ts (~:97-99, el CF que OTORGA este mismo share)
  // y contra el create rule de firestore.rules (~:657-662).
  //
  // Va DESPUÉS de leer el grant y ANTES del profile: si el grant ya cortó, esta
  // query no se paga; y el `get()` de userPublicProfiles es puro adorno del
  // cuerpo del push, no tiene sentido pagarlo por un despacho que no va a salir.
  //
  // Equality-only sobre tres campos: la sirven los índices de campo único con
  // zigzag merge, no hace falta índice compuesto en firestore.indexes.json.
  const linkSnap = await db
    .collection("trainer_links")
    .where("athleteId", "==", athleteUid)
    .where("trainerId", "==", trainerId)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (linkSnap.empty) {
    // Dos casos distintos, mismo desenlace y a propósito: un grant FORJADO
    // (nunca hubo vínculo) y uno VENCIDO (lo hubo y murió, y el borrado del
    // share se perdió). Ninguno de los dos es una excepción: el forjado no le
    // avisa al atacante que lo agarramos, y el vencido es el estado normal de
    // un share que le sobrevivió a su vínculo. Se loguea en warn —no en info,
    // como el "sin grant"— porque acá SÍ hay un doc que miente y alguien lo
    // escribió.
    logger.warn("notifyOnExerciseFeedback: grant forjado o vencido, no se notifica", {
      athleteUid,
      trainerId,
      sessionId,
    });
    return;
  }

  // Nombre del alumno para el cuerpo del push — mismo origen y mismo fallback
  // que notifyOnReview (userPublicProfiles.displayName).
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(athleteUid)
    .get();
  const athleteName: string =
    (profileSnap.data()?.displayName as string | undefined) ?? "Un atleta"; // i18n: #628

  // Cuerpo: SOLO alumno + ejercicio. `text` y `photoUrl` quedan afuera a
  // propósito — ver el header de este archivo.
  const body = `${athleteName} reportó una molestia en ${exerciseName}`; // i18n: #628

  // No existe today una ruta para una sesión puntual del lado del coach
  // (routine_detail_screen.dart y session_detail_sheet.dart ya navegan a
  // este mismo path para que el PF vea a SU alumno); el PF entra a la ficha
  // del alumno y ahí tiene el historial de sesiones con este reporte adentro.
  const deepLink = `/coach/athlete/${athleteUid}`;

  await sendFcm(
    app,
    {
      uids: [trainerId],
      kind: "discomfort",
      notification: {
        title: "Molestia reportada", // i18n: #628
        body,
      },
      data: { deepLink, athleteUid, sessionId, exerciseId },
      actorUid: athleteUid,
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005 (misma región que el resto
 * de los triggers de notificaciones de este directorio).
 */
export const notifyOnExerciseFeedback = onDocumentCreated(
  {
    document: "users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const feedbackData = event.data?.data() as FeedbackData | undefined;
    if (!feedbackData) {
      logger.warn("notifyOnExerciseFeedback: no feedback data");
      return;
    }

    const { uid: athleteUid, sessionId } = event.params;
    await notifyOnExerciseFeedbackHandler(getApp(), athleteUid, sessionId, feedbackData);
  },
);
