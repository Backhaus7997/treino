/**
 * Users cascade module — deletes user documents and public profiles.
 *
 * Handles:
 *   - `users/{uid}` with all sub-collections (recursiveDelete)
 *   - `userPublicProfiles/{uid}` (hard delete)
 *   - `trainerPublicProfiles/{uid}` (defensive no-op if absent)
 *   - `retention_notices/{uid}` (hard delete)
 *
 * Admin SDK bypasses Firestore security rules — no rules change needed.
 * REQ-ACCDEL-CF-004 | ADR-ACCDEL-001
 */

import { App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { RETENTION_NOTICES_COLLECTION } from "../retention/collection";

/**
 * Deletes all Firestore documents owned by the given user.
 * Idempotent — safe to call when docs are already absent.
 */
export async function deleteUserDocs(
  app: App,
  uid: string
): Promise<void> {
  const db = getFirestore(app);

  // Step 1: Recursively delete users/{uid} including all sub-collections
  // (sessions, sessions/*/setLogs, checkIns, etc.)
  // Admin SDK BulkWriter handles batching internally.
  await db.recursiveDelete(db.collection("users").doc(uid));

  // Step 2: Delete userPublicProfiles/{uid}
  // Firestore delete on a non-existent doc is a no-op — no error thrown.
  await db.collection("userPublicProfiles").doc(uid).delete();

  // Step 3: Delete trainerPublicProfiles/{uid} if present (defensive)
  // Athletes normally have no trainer profile; this handles edge cases.
  await db.collection("trainerPublicProfiles").doc(uid).delete();

  // Step 4: Delete retention_notices/{uid}.
  //
  // Va ACA y no en el barrido de deuda por una razon de forma: el resto de la
  // cascada borra por CAMPO (`where athleteId == uid`), y este documento lleva
  // el uid en el ID. Es el mismo molde huerfano de `blocks` y `reports`, y se
  // resuelve del unico modo que se puede — nombrandolo.
  //
  // Aplica tanto a una baja pedida por el usuario como a la automatica: en la
  // segunda, `sweepInactiveAccounts` escribe `deletedAt` ANTES de llamar a la
  // cascada, justamente para que este delete se lo lleve. La auditoria de la
  // baja queda en `audit_log/{uid}`, que se retiene a proposito.
  await db.collection(RETENTION_NOTICES_COLLECTION).doc(uid).delete();
}
