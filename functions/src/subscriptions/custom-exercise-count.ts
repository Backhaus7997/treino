/**
 * custom-exercise-count.ts — mantiene `users/{uid}.customExerciseUsage.count`
 * al dia cuando un PF crea o borra un ejercicio propio
 * (limite-ejercicios-pf.md, PR1).
 *
 * Solo reacciona a CREATE y DELETE: un update de un ejercicio propio (cambiar
 * nombre, grupo muscular, video) no mueve la CANTIDAD, asi que sale temprano
 * sin tocar nada.
 *
 * Corta por ROL antes de recontar: `users/{uid}/customExercises` es una
 * subcoleccion COMPARTIDA entre el PF y el alumno (mismo editor, decision E4
 * del plan). Si no es un `trainer`, no se escribe nada — no se ensucia el
 * documento del alumno con un campo que no le corresponde, y no se disparan
 * sus propios triggers sobre `users/{uid}` por una escritura que no significa
 * nada para el.
 *
 * ─── Anti-loop: esta CF escribe en `users/{uid}` ────────────────────────────
 *
 * `recountCustomExercises` escribe `customExerciseUsage` en `users/{uid}`, que
 * es el documento que disparan VARIOS otros `onDocumentWritten`. Investigado
 * contra el codigo real de este repo (ver el reporte de la sesion que agrego
 * este modulo para el detalle completo por trigger):
 *
 *   - `syncEntitlementsOnSubscription` (entitlement-triggers.ts) y
 *     `syncAthletePaywallOnUser` (athlete-paywall-enforced.ts) comparan solo
 *     `subscription` y (`athleteSubscription` + `role`) respectivamente. Esta
 *     escritura no toca ninguno de los dos campos: las dos GUARDAS cortan en
 *     la primera linea, sin leer nada mas.
 *   - `reassignFcmToken` compara `fcmTokens`; esta escritura no lo toca, corta
 *     igual.
 *   - `ensureStoreAccountToken` sale temprano si el token ya es un UUID valido
 *     (lo es, salvo la primera escritura de la vida del usuario).
 *   - `syncSharedProfile` lee `profile_shares/{uid}` y compara SOLO los seis
 *     campos de `SHARED_FIELDS` (telefono, altura, etc.); ninguno es
 *     `customExerciseUsage`, asi que no escribe.
 *   - `quarantineDisplayNameOnWrite` NO tiene guarda de campo: corre un scan de
 *     texto en memoria (`checkText`) sobre `displayName` en CADA escritura de
 *     `users/{uid}`. Es barato (sin Firestore de por medio si el nombre esta
 *     limpio) pero SI corre una vez por cada create/delete de ejercicio de
 *     cada PF — no es un loop ni hace trabajo caro, pero es una CF mas que se
 *     factura por cada escritura de este modulo.
 *
 * Ninguno de los seis hace trabajo caro en cascada ni vuelve a escribir
 * `users/{uid}` de una forma que reactive a este modulo, asi que no hay loop.
 * El costo real es un puñado de invocaciones baratas extra por cada
 * create/delete de ejercicio — aceptable por el mismo motivo que el resto del
 * modulo: "los ejercicios se crean poco" (§E7 del plan).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { recountCustomExercises } from "./trainer-plan-limits";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Si esta escritura cambio la CANTIDAD de documentos (create o delete).
 *
 * Exportada para testear la decision sin emulador: un update dispara
 * `onDocumentWritten` igual que un create o un delete, y la unica forma de
 * distinguirlos desde afuera es comparar existencia antes/despues.
 */
export function isCreateOrDelete(
  beforeExists: boolean,
  afterExists: boolean,
): boolean {
  return beforeExists !== afterExists;
}

/**
 * Handler puro, extraido del wrapper `onDocumentWritten` — mismo patron que
 * `reassignFcmTokenHandler` en `reassign-fcm-token.ts`. Permite testearlo
 * contra el emulador real sin tener que levantar el emulador de Functions
 * (que no dispara triggers v2 por si solo): `custom-exercise-count.test.ts`
 * llama a esta funcion directamente.
 */
export async function handleCustomExerciseWrite(
  app: App,
  uid: string,
  beforeExists: boolean,
  afterExists: boolean,
): Promise<void> {
  if (!isCreateOrDelete(beforeExists, afterExists)) return;

  const userSnap = await getFirestore(app).collection("users").doc(uid).get();
  if (userSnap.get("role") !== "trainer") return;

  const r = await recountCustomExercises(app, uid);
  if (r.changed) {
    logger.info("customExerciseCount: reconciliado", { uid, count: r.count });
  }
}

/**
 * Trigger sobre `users/{uid}/customExercises/{exId}`.
 *
 * Region `southamerica-east1`: mismo patron que el resto de los triggers de
 * subcolecciones de `users/{uid}` en este repo (`notify-wear-workout.ts`,
 * `ranking-aggregate.ts`), no `us-east1` — esa excepcion es solo para
 * triggers de Cloud Storage, que tienen que vivir en la region del bucket.
 */
export const maintainCustomExerciseCount = onDocumentWritten(
  {
    document: "users/{uid}/customExercises/{exId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const beforeExists = event.data?.before?.exists ?? false;
    const afterExists = event.data?.after?.exists ?? false;
    const uid = event.params.uid;
    try {
      await handleCustomExerciseWrite(ensureApp(), uid, beforeExists, afterExists);
    } catch (err) {
      // Catch-and-log sin relanzar, igual que el resto de los triggers de
      // subscriptions: un doc malformado no debe provocar una tormenta de
      // reintentos.
      logger.error("customExerciseCount: error", { uid, err });
    }
  },
);
