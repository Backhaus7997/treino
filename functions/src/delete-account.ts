/**
 * deleteAccount — Firebase Callable Cloud Function handler.
 *
 * PR#1 skeleton: handles auth guard, anti-spoofing, trainer role guard,
 * audit log, and Auth user deletion. Full Firestore/Storage cascade in PR#2.
 *
 * ADRs: ACCDEL-001 (CF over client), ACCDEL-003 (callable), ACCDEL-014
 * (anti-spoofing), ACCDEL-012 (audit log shape).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { writeStarted, writeFinal } from "./cascade/audit-log";
import {
  DeleteAccountRequest,
  DeleteAccountResponse,
} from "./types";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments that set up
 * their own named apps before importing).
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    // No default app yet — initialize one.
    return admin.initializeApp();
  }
}

/**
 * Core deletion logic, extracted for unit-testability.
 * The caller supplies the firebase-admin App so tests can pass a named
 * emulator-backed app without relying on the default app.
 */
export async function runDeleteAccount(
  app: admin.app.App,
  uid: string,
  provider: string
): Promise<DeleteAccountResponse> {
  const db = admin.firestore(app);

  // ── Guard: trainers cannot self-delete (REQ-ACCDEL-CF-003) ─────────────
  // Full trainer check is enforced here. PR#2 adds the 6 cascade modules.
  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.exists) {
    const role = userSnap.data()?.role as string | undefined;
    if (role === "trainer") {
      throw new HttpsError(
        "permission-denied",
        "trainers cannot self-delete"
      );
    }
  }

  // ── Audit log: started ─────────────────────────────────────────────────
  await writeStarted(app, uid, provider);

  try {
    // ── Auth user deletion (REQ-ACCDEL-CF-012) ─────────────────────────
    // In the full cascade (PR#2) this is the LAST step. In PR#1 skeleton
    // it is the only cascade step, so it is effectively last.
    try {
      await admin.auth(app).deleteUser(uid);
    } catch (authErr: unknown) {
      // Idempotency (REQ-ACCDEL-CF-013): if the user was already deleted
      // in a prior partial run, treat it as a no-op.
      const code = (authErr as { code?: string }).code;
      if (code !== "auth/user-not-found") {
        throw authErr;
      }
    }

    // ── Audit log: success ─────────────────────────────────────────────
    const deletedCollections = ["users-auth"];
    await writeFinal(app, uid, "success", deletedCollections, []);

    // ── Structured response (REQ-ACCDEL-CF-014) ────────────────────────
    return {
      status: "success",
      deletedCollections,
      errors: [],
    };
  } catch (err: unknown) {
    // ── Audit log: failed ──────────────────────────────────────────────
    const message =
      err instanceof Error ? err.message : "Unknown error during deletion";
    try {
      await writeFinal(app, uid, "failed", [], [message]);
    } catch {
      // Swallow audit write failure — original error takes priority.
    }

    if (err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError(
      "internal",
      `Account deletion failed: ${message}`
    );
  }
}

/**
 * The v2 callable exported as the Firebase Function.
 * Named export so firebase-functions-test can wrap it directly.
 */
export const deleteAccountHandler = functions.onCall(
  { region: "us-central1" },
  async (request): Promise<DeleteAccountResponse> => {
    // ── Guard: caller must be authenticated ─────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Caller is not authenticated.");
    }

    const callerUid = request.auth.uid;
    const data = request.data as DeleteAccountRequest;

    // ── Guard: anti-spoofing (REQ-ACCDEL-CF-002, ADR-ACCDEL-014) ───────────
    if (callerUid !== data.uid) {
      throw new HttpsError("permission-denied", "uid mismatch");
    }

    // ── Resolve sign-in provider from auth token ────────────────────────────
    // DecodedIdToken.firebase.sign_in_provider is present on real tokens.
    // In test contexts the field may be absent — fall back to "unknown".
    const tokenFirebase = request.auth.token.firebase as
      | { sign_in_provider?: string }
      | undefined;
    const provider = tokenFirebase?.sign_in_provider ?? "unknown";

    const app = getApp();
    return runDeleteAccount(app, data.uid, provider);
  }
);
