/**
 * removeFollowEdgesOnBlock — Cloud Function for TREINO.
 *
 * Trigger `onCreate` sobre `blocks/{blockId}`. Borra las DOS aristas de
 * `follows` entre bloqueador y bloqueado (`{blockerUid}_{blockedUid}` y
 * `{blockedUid}_{blockerUid}`), si existen.
 *
 * ## Por qué existe (design.md, "El tier `followers` sale gratis")
 *
 * `moderacion-reporte-y-bloqueo` corta la escritura (chat, reacciones,
 * follows, reviews) con `notBlocked()` en `firestore.rules`, pero el tier
 * `followers` de `posts` se protege distinto: por LECTURA, vía
 * `postFollowerAccepted` → `followAccepted`, que resuelve mirando si existe
 * la arista `follows/{lector}_{autor}` con `status == 'accepted'`.
 *
 * Sumar `notBlocked()` a `posts/{postId} allow read` rompería el feed
 * entero: las rules de `list` se evalúan contra la QUERY, y si un solo doc
 * del resultado no pasa, Firestore rechaza la query COMPLETA en vez de
 * filtrar la fila (`post_providers.dart:157`). `feedPublic()` no filtra por
 * autor, así que el primer post de alguien con un bloqueo activo dejaría el
 * feed en blanco para el lector, no recortado.
 *
 * La salida: si bloquear BORRA la arista de follow en las dos direcciones,
 * el gate de lectura que YA EXISTE (`followAccepted`) deja de resolver
 * `true` para ese par — sin tocar una sola línea de `posts/{postId} allow
 * read`. El enforcement de lectura del tier que de verdad importa
 * (`followers`, contenido privado) sale de arrastre.
 *
 * ## Por qué CF y no rules
 *
 * `firestore.rules` sólo autoriza o deniega la escritura que el cliente
 * pidió — no puede borrar un doc de OTRA colección como efecto secundario
 * de un `create`. Sacar la arista de `follows` cuando se crea un `blocks`
 * necesita Admin SDK.
 *
 * ## Por qué batch y no transacción
 *
 * A diferencia de `maintainFollowCounters` (`social/maintain-follow-
 * counters.ts`), acá no hay ninguna lectura condicional: los dos ids a
 * borrar se derivan enteros de los campos del propio doc creado
 * (`blockerUid`/`blockedUid`). Un `WriteBatch` de dos deletes alcanza —
 * atómico igual, sin pagar el round-trip extra de una transacción. Borrar
 * un doc que no existe no es un error en Firestore (delete es idempotente),
 * así que no hace falta comprobar existencia antes: si alguna de las dos
 * aristas (o las dos) no existía, el batch igual se aplica limpio.
 *
 * ## Lo que NO hace
 *
 * No toca `blocks` ni `reports`. No restaura nada al des-bloquear (`allow
 * delete` en `blocks`): el trigger sólo corre en el CREATE, así que
 * desbloquear deja las aristas de follow borradas — cada uno vuelve a
 * seguir si quiere, mismo criterio que cualquier unfollow.
 *
 * Región southamerica-east1 (ADR-PN-005, igual que el resto de las CF de
 * grafo social).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** Forma mínima que el handler necesita del doc `blocks/{blockId}` creado. */
export interface BlockData {
  blockerUid?: unknown;
  blockedUid?: unknown;
}

/**
 * Pure handler extraído para jest testability, mismo criterio que
 * `maintainFollowCountersHandler`: sin este split, testear la lógica exige
 * un emulador de Firestore levantado.
 */
export async function removeFollowEdgesOnBlockHandler(
  app: App,
  data: BlockData | undefined,
): Promise<void> {
  const blockerUid = data?.blockerUid;
  const blockedUid = data?.blockedUid;

  // Defensa contra un doc malformado escrito por Admin SDK (que saltea las
  // rules — el `create` del cliente ya exige ambos campos como string
  // no-vacío y distintos entre sí).
  if (
    typeof blockerUid !== "string" ||
    typeof blockedUid !== "string" ||
    blockerUid.length === 0 ||
    blockedUid.length === 0 ||
    blockerUid === blockedUid
  ) {
    logger.info("removeFollowEdgesOnBlock: noop, malformed block doc");
    return;
  }

  const db = getFirestore(app);
  const batch = db.batch();
  batch.delete(db.collection("follows").doc(`${blockerUid}_${blockedUid}`));
  batch.delete(db.collection("follows").doc(`${blockedUid}_${blockerUid}`));
  await batch.commit();

  logger.info("removeFollowEdgesOnBlock: applied", { blockerUid, blockedUid });
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005.
 */
export const removeFollowEdgesOnBlock = onDocumentCreated(
  {
    document: "blocks/{blockId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const data = event.data?.data() as BlockData | undefined;
    await removeFollowEdgesOnBlockHandler(ensureApp(), data);
  },
);
