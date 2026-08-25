/**
 * Despierta el companion de Wear cuando arranca un entreno.
 *
 * ## Por qué hace falta, si el reloj ya lee Firestore
 *
 * Un listener de Firestore existe sólo mientras hay proceso vivo. Con la app
 * del reloj cerrada no hay nadie escuchando, por más internet que tenga: algo
 * tiene que despertar el proceso DESDE AFUERA.
 *
 * La Data Layer puede hacerlo, pero exige que el reloj esté emparejado con ese
 * teléfono y que el teléfono tenga la app companion instalada — medido en
 * hardware: sin companion, Play Services responde `Wearable.API is not
 * available on this device` y el aviso no sale nunca. El push no exige nada de
 * eso: al reloj le alcanza con red.
 *
 * ## Por qué un trigger y no una llamada desde el teléfono
 *
 * Porque así da igual QUIÉN abrió el entreno. Si mañana se abre desde la web o
 * desde el panel del PF, el reloj se entera igual. Atarlo al cliente que hoy lo
 * abre sería atarlo a un detalle que va a cambiar.
 */
import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

/**
 * Inicializa el Admin SDK de forma perezosa, para que el módulo se pueda
 * importar sin una app ya creada — igual que hace `ranking-aggregate`.
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/** El campo donde el reloj deja su token. Espeja `WearPushRegistration.field`. */
export const WEAR_TOKENS_FIELD = "wearFcmTokens";

/** Discriminador que lee `WearMessagingService` en Kotlin. */
export const TYPE_WORKOUT_STARTED = "workoutStarted";

/**
 * Si este cambio de documento es el NACIMIENTO de un entreno activo.
 *
 * Va aparte del trigger para poder probarla sin construir un CloudEvent, que es
 * donde de verdad se rompen estas cosas: avisar en cada escritura de la sesión
 * —y hay una por cada serie marcada— despertaría el reloj decenas de veces por
 * entreno.
 */
export function esArranqueDeEntreno(
  existiaAntes: boolean,
  existeAhora: boolean,
  estado: unknown,
): boolean {
  if (!existeAhora) return false;
  // Ya existía: es una actualización (una serie más, el cierre), no un arranque.
  if (existiaAntes) return false;
  return estado === "active";
}

/** Los tokens de reloj del atleta, o vacío. */
async function tokensDeReloj(
  app: admin.app.App,
  uid: string,
): Promise<string[]> {
  const snap = await admin.firestore(app).collection("users").doc(uid).get();
  const raw = snap.get(WEAR_TOKENS_FIELD);
  if (!Array.isArray(raw)) return [];
  return raw.filter((t): t is string => typeof t === "string" && t.length > 0);
}

export const notifyWearOnWorkoutStarted = onDocumentWritten(
  { document: "users/{uid}/sessions/{sessionId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;

    if (
      !esArranqueDeEntreno(
        before?.exists === true,
        after?.exists === true,
        after?.get("status"),
      )
    ) {
      return;
    }

    const uid = event.params.uid;
    const sessionId = event.params.sessionId;
    if (!uid) return;

    const app = getApp();
    const tokens = await tokensDeReloj(app, uid);
    if (tokens.length === 0) {
      // No es un error: la enorme mayoría de los atletas no tiene reloj.
      logger.debug("notifyWearOnWorkoutStarted: sin relojes", { uid });
      return;
    }

    try {
      const res = await admin.messaging(app).sendEachForMulticast({
        tokens,
        // DATA-ONLY a propósito: un mensaje con `notification` lo dibuja el
        // sistema y NO llega al service, así que el reloj no podría abrirse
        // solo. Con data-only el mensaje entra por `onMessageReceived` y es el
        // service el que decide qué hacer — que es todo el punto.
        data: {
          type: TYPE_WORKOUT_STARTED,
          sessionId: String(sessionId ?? ""),
        },
        // `high` es lo que permite entregar con el equipo en Doze. Sin esto el
        // push puede quedar diferido justo cuando el reloj está en la muñeca
        // quieto, que es el caso normal.
        android: { priority: "high" },
      });
      logger.info("notifyWearOnWorkoutStarted: enviado", {
        uid,
        ok: res.successCount,
        fallaron: res.failureCount,
      });
    } catch (e) {
      // Un aviso perdido no puede hacer fallar la escritura de la sesión.
      logger.warn("notifyWearOnWorkoutStarted: falló el envío", { uid, e });
    }
  },
);
