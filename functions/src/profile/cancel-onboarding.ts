/**
 * cancel-onboarding.ts — «Cancelar cuenta» del alta: borra lo que el login dejo
 * en Firestore y Storage ANTES de que el cliente borre la cuenta de Auth.
 *
 * ── El bug que cierra ──
 *
 * El login deja `users/{uid}` y `userPublicProfiles/{uid}` con
 * `displayName: null` (`createIfAbsent` del cliente, o `ensureAthleteProfile`
 * desde la web), y ProfileSetup los completa. Si la persona se arrepiente en el
 * paso 0 y toca «Cancelar cuenta», `AuthService.cancelOnboarding` intentaba
 * borrar el doc con `UserRepository.delete` —que tira SIEMPRE, porque las
 * reglas le niegan el delete al cliente—, se tragaba el error y borraba solo la
 * cuenta de Auth. Los dos documentos quedaban para siempre, con el mail de
 * alguien que pidio no tener cuenta. La Politica de Privacidad (§8) promete lo
 * contrario: «Todo lo asociado a tu cuenta: se elimina al eliminar la cuenta».
 *
 * ── Por que un callable propio y no `deleteAccount` ──
 *
 * `deleteAccount` corre la cascada COMPLETA (posts, vinculos, turnos, rutinas,
 * mediciones) y en la app se llega a el despues de re-autenticarse. Aca se
 * llega con un solo dialogo de confirmacion, y el poder del servidor tiene que
 * ser el que justifica esa UI: este callable solo actua sobre un alta que nunca
 * se completo, que es exactamente la condicion con la que el router muestra
 * ProfileSetup (`displayName == null`, `lib/app/router.dart:192`). Si algun dia
 * el boton se le muestra a una cuenta establecida, lo peor que pasa es un
 * rechazo, no una cascada.
 *
 * Tampoco escribe `audit_log/{uid}`: ese registro es la auditoria de una BAJA y
 * se retiene a proposito (`cascade/users.ts`). Un alta que no llego a existir
 * queda en Cloud Logging.
 *
 * ── Lo que borra ──
 *
 * El mismo camino que los pasos 8 y 9 de `deleteAccount`:
 *   - `deleteUserDocs`: `users/{uid}` recursivo (con los `fcmTokens` que el
 *     arranque de la app ya pudo escribir), `userPublicProfiles/{uid}`,
 *     `trainerPublicProfiles/{uid}` y `retention_notices/{uid}`.
 *   - `deleteAvatar`: la foto puede estar subida si un submit anterior del alta
 *     la subio y despues fallo (`profile_setup_notifier.dart`, `submit`).
 * Nada mas puede existir: ProfileSetup no escribe hasta el submit del ultimo
 * paso, y ningun trigger recrea estos documentos al borrarse.
 *
 * ── Lo que NO hace ──
 *
 * No borra la cuenta de Auth. Lo sigue haciendo el cliente, DESPUES: sin
 * sesion este callable ya no se podria llamar.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { deleteAvatar } from "../cascade/storage";
import { deleteUserDocs } from "../cascade/users";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * La logica, separada del callable para testearla contra el emulador. Recibe
 * el `uid` YA extraido del token: no hay body.
 *
 * Idempotente: un reintento —por ejemplo despues de que el borrado de Auth
 * fallara con `requires-recent-login`— no encuentra nada y no falla.
 */
export async function runCancelOnboarding(app: App, uid: string): Promise<void> {
  const userSnap = await getFirestore(app).collection("users").doc(uid).get();
  if (userSnap.exists) {
    // El mismo guard que deleteAccount (REQ-ACCDEL-CF-003): a un entrenador lo
    // da de alta el equipo, y no se da de baja solo.
    if (userSnap.get("role") === "trainer") {
      throw new HttpsError(
        "permission-denied",
        "un entrenador no se da de baja solo",
      );
    }
    // Espeja el `displayName == null` del router, donde un campo ausente
    // tambien es null.
    const displayName = userSnap.get("displayName");
    if (displayName !== null && displayName !== undefined) {
      throw new HttpsError(
        "failed-precondition",
        "el alta ya esta completa: la cuenta se elimina desde Ajustes",
      );
    }
  }

  const errores: string[] = [];

  // Los documentos primero: son los que tienen el mail.
  try {
    await deleteUserDocs(app, uid);
  } catch (err: unknown) {
    errores.push(`users: ${(err as Error).message ?? String(err)}`);
  }

  let avatares = 0;
  try {
    ({ deleted: avatares } = await deleteAvatar(app, uid));
  } catch (err: unknown) {
    errores.push(`storage: ${(err as Error).message ?? String(err)}`);
  }

  if (errores.length > 0) {
    logger.error("profile/cancel-onboarding: borrado incompleto", {
      uid,
      errores,
    });
    throw new HttpsError("internal", "no se pudo borrar todo lo del alta");
  }

  logger.info("profile/cancel-onboarding: alta cancelada", { uid, avatares });
}

export const cancelOnboarding = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo que deleteAccount
  // (delete-account.ts): una parte real de los clientes todavia no puede
  // atestar, y con el flag el boton de cancelar no andaria nunca para ellos.
  // La cerradura es que NO HAY BODY: el uid sale del token, asi que un llamador
  // solo puede borrar lo SUYO, y solo si su alta nunca se completo.
  { region: "southamerica-east1" },
  async (request): Promise<{ ok: true }> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    await runCancelOnboarding(ensureApp(), uid);
    // Un objeto y no `undefined`: el cliente lo pide como
    // `call<Map<String, dynamic>>`, igual que el resto de los callables.
    return { ok: true };
  },
);
