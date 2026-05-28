/**
 * Storage cascade module — deletes user avatar from Firebase Storage.
 *
 * Deletes `avatars/{uid}.jpg` from the default bucket.
 * If the file does not exist, the operation is a no-op (no error thrown).
 *
 * TRUST BOUNDARY: Admin SDK bypasses Firebase Storage security rules.
 * This module MUST NOT be called from client-side code.
 * Only the Cloud Function runtime (server-side) is permitted to invoke this.
 * ADR-ACCDEL-013 — Admin SDK trust boundary.
 *
 * REQ-ACCDEL-CF-010 | ADR-ACCDEL-013
 */

import * as admin from "firebase-admin";

/**
 * Deletes the avatar file for the given uid from Storage.
 * Returns { deleted: true } if the file was deleted, { deleted: false } if it was absent.
 */
export async function deleteAvatar(
  app: admin.app.App,
  uid: string
): Promise<{ deleted: boolean }> {
  // Admin SDK bypasses Storage security rules (ADR-ACCDEL-013)
  const bucket = admin.storage(app).bucket();
  const file = bucket.file(`avatars/${uid}.jpg`);

  try {
    await file.delete();
    return { deleted: true };
  } catch (err: unknown) {
    // Treat "not found" (HTTP 404 or storage/object-not-found) as a no-op
    const code = (err as { code?: number | string }).code;
    if (code === 404 || code === "storage/object-not-found") {
      return { deleted: false };
    }
    // Re-throw any unexpected error
    throw err;
  }
}
