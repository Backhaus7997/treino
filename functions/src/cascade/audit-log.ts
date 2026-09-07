/**
 * Audit log helper — writes to audit_log/{uid} in Firestore.
 *
 * The audit_log collection is Admin-only accessible.
 * No firestore.rules change is required for this write path.
 */

import * as admin from "firebase-admin";
import { App } from "firebase-admin/app";
import { FieldValue } from "firebase-admin/firestore";

type FinalStatus = "success" | "partial" | "failed";

/**
 * Writes the initial audit entry with status: "started".
 * Idempotent — safe to call on retry.
 */
export async function writeStarted(
  app: App,
  uid: string,
  provider: string
): Promise<void> {
  const db = admin.firestore(app);
  await db.collection("audit_log").doc(uid).set({
    uid,
    status: "started",
    provider,
    startedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Updates the audit entry with the final status.
 * Should be called after all cascade steps complete (success, partial, or failed).
 */
export async function writeFinal(
  app: App,
  uid: string,
  status: FinalStatus,
  deletedCollections: string[],
  errors: string[]
): Promise<void> {
  const db = admin.firestore(app);
  await db.collection("audit_log").doc(uid).update({
    status,
    completedAt: FieldValue.serverTimestamp(),
    deletedCollections,
    errors,
  });
}
