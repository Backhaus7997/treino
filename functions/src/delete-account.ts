/**
 * deleteAccount — Firebase Callable Cloud Function handler.
 *
 * Full cascade handler (PR#2): handles auth guard, anti-spoofing, trainer role guard,
 * audit log, full Firestore/Storage cascade, and Auth user deletion (last).
 *
 * Cascade order (REQ-ACCDEL-CF-012: Auth MUST be last):
 *   1. Validate + anti-spoof (callable wrapper)
 *   2. Trainer role guard
 *   3. Audit log: started
 *   4. Sweep friendships
 *   5. Anonymize posts
 *   6. Terminate trainer links
 *   7. Cancel future appointments
 *   8. Delete storage avatar
 *   9. Delete user docs (users + userPublicProfiles + trainerPublicProfiles)
 *  10. Update audit log with cascade results
 *  11. Delete Auth user (LAST — REQ-ACCDEL-CF-012)
 *  12. Update audit log to success/partial
 *
 * ADRs: ACCDEL-001 (CF over client), ACCDEL-003 (callable), ACCDEL-010 (idempotency),
 *       ACCDEL-012 (audit log shape), ACCDEL-013 (storage trust boundary),
 *       ACCDEL-014 (anti-spoofing).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { writeStarted, writeFinal } from "./cascade/audit-log";
import { sweepFriendships } from "./cascade/friendships";
import { anonymizePosts } from "./cascade/posts";
import { terminateTrainerLinks } from "./cascade/trainer-links";
import { cancelFutureAppointments } from "./cascade/appointments";
import { deleteAvatar } from "./cascade/storage";
import { deleteUserDocs } from "./cascade/users";
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
 *
 * Each cascade step is wrapped in try/catch — a single step failure does not
 * abort the overall flow. Errors are accumulated and reported in the final
 * audit log and response.
 */
export async function runDeleteAccount(
  app: admin.app.App,
  uid: string,
  provider: string
): Promise<DeleteAccountResponse> {
  const db = admin.firestore(app);

  // ── Guard: trainers cannot self-delete (REQ-ACCDEL-CF-003) ─────────────
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

  const errors: string[] = [];
  const deletedCollections: string[] = [];

  // ── Step 4: Sweep friendships ──────────────────────────────────────────
  try {
    await sweepFriendships(app, uid);
    deletedCollections.push("friendships");
  } catch (err: unknown) {
    errors.push(`friendships: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 5: Anonymize posts ────────────────────────────────────────────
  try {
    await anonymizePosts(app, uid);
    deletedCollections.push("posts");
  } catch (err: unknown) {
    errors.push(`posts: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 6: Terminate trainer links ───────────────────────────────────
  try {
    await terminateTrainerLinks(app, uid);
    deletedCollections.push("trainer_links");
  } catch (err: unknown) {
    errors.push(`trainer_links: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 7: Cancel future appointments ────────────────────────────────
  try {
    await cancelFutureAppointments(app, uid);
    deletedCollections.push("appointments");
  } catch (err: unknown) {
    errors.push(`appointments: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 8: Delete storage avatar ─────────────────────────────────────
  // Admin SDK bypasses Storage security rules (ADR-ACCDEL-013).
  try {
    await deleteAvatar(app, uid);
    deletedCollections.push("storage");
  } catch (err: unknown) {
    errors.push(`storage: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 9: Delete user docs ───────────────────────────────────────────
  try {
    await deleteUserDocs(app, uid);
    deletedCollections.push("users");
    deletedCollections.push("userPublicProfiles");
  } catch (err: unknown) {
    errors.push(`users: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 10-11: Auth user deletion (REQ-ACCDEL-CF-012) ─────────────────
  // MUST be last — so role guard still works if retry happens mid-cascade.
  try {
    await admin.auth(app).deleteUser(uid);
    deletedCollections.push("users-auth");
  } catch (authErr: unknown) {
    // Idempotency (REQ-ACCDEL-CF-013): if the user was already deleted
    // in a prior partial run, treat it as a no-op.
    const code = (authErr as { code?: string }).code;
    if (code !== "auth/user-not-found") {
      errors.push(`auth: ${(authErr as Error).message ?? String(authErr)}`);
    } else {
      // Already deleted — still mark as complete for idempotent runs
      if (!deletedCollections.includes("users-auth")) {
        deletedCollections.push("users-auth");
      }
    }
  }

  // ── Audit log: final ───────────────────────────────────────────────────
  const finalStatus = errors.length > 0 ? "partial" : "success";
  try {
    await writeFinal(app, uid, finalStatus, deletedCollections, errors);
  } catch {
    // Swallow audit write failure — cascade results take priority.
  }

  // ── Structured response (REQ-ACCDEL-CF-014) ────────────────────────────
  return {
    status: finalStatus,
    deletedCollections,
    errors,
  };
}

/**
 * The v2 callable exported as the Firebase Function.
 * Named export so firebase-functions-test can wrap it directly.
 */
export const deleteAccountHandler = functions.onCall(
  // Region aligned with the existing parsePlan CF for latency
  // consistency for LATAM users.
  { region: "southamerica-east1" },
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
