/**
 * addAlias — Firebase Callable Cloud Function for TREINO.
 *
 * Appends a normalized alias to an existing exercise document so that
 * future Excel imports can auto-match trainer-specific exercise names.
 *
 * Pattern: pure handler (runAddAlias) + thin onCall wrapper (addAlias).
 * Mirrors the recomputeAggregate / deleteAccount pattern in this codebase.
 *
 * REQ-CXP-CF-001..009. Fase 6 Etapa 5.
 *
 * ADRs:
 *   ADR-CXP-004 — pure handler + thin onCall wrapper
 *   ADR-CXP-005 — trainer role gate via users/{callerId}.role, exercise existence, arrayUnion
 *   ADR-CXP-006 — normalize() is a LITERAL char-by-char port of Dart normalize() (LOAD-BEARING R1)
 *   ADR-CXP-007 — HttpsError message strings locked (English, operator-facing)
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments that set up
 * their own named apps before importing).
 * Copied from review-aggregate.ts (same pattern).
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    // No default app yet — initialize one.
    return admin.initializeApp();
  }
}

// ---------------------------------------------------------------------------
// NORMALIZE-PARITY: see ADR-CXP-006
//
// This function is a LITERAL char-by-char port of the Dart normalize() from
// lib/features/coach_hub/data/exercise_matcher.dart lines 29-41:
//
//   String normalize(String s) {
//     return s
//         .toLowerCase()
//         .replaceAll(RegExp('[áàäâã]'), 'a')
//         .replaceAll(RegExp('[éèëê]'), 'e')
//         .replaceAll(RegExp('[íìïî]'), 'i')
//         .replaceAll(RegExp('[óòöôõ]'), 'o')
//         .replaceAll(RegExp('[úùüû]'), 'u')
//         .replaceAll('ñ', 'n')
//         .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
//         .replaceAll(RegExp(r'\s+'), ' ')
//         .trim();
//   }
//
// OPERATION ORDER IS LOAD-BEARING:
//   1. lowercase first (so accent chars are lowercased before stripping)
//   2. accent strip (á→a, é→e, í→i, ó→o, ú→u, ñ→n)
//   3. [^a-z0-9\s] → ' '  (must run AFTER accent strip — otherwise accented
//      chars would be stripped before they can be replaced)
//   4. \s+ → ' '  (collapse multiple spaces)
//   5. trim
//
// SCENARIO-742 and SCENARIO-743 are the cross-language safety nets.
// If the Dart normalize() ever changes, update this function in lock-step.
// ---------------------------------------------------------------------------
function normalize(s: string): string {
  return s
    .toLowerCase()
    .replace(/[áàäâã]/g, "a")
    .replace(/[éèëê]/g, "e")
    .replace(/[íìïî]/g, "i")
    .replace(/[óòöôõ]/g, "o")
    .replace(/[úùüû]/g, "u")
    .replace(/ñ/g, "n")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Core addAlias logic, extracted for unit-testability.
 * The caller supplies the firebase-admin App so tests can pass a named
 * emulator-backed app without relying on the default app.
 *
 * @param app    - firebase-admin App (default or named emulator app in tests)
 * @param callerId  - UID of the authenticated caller (must be a trainer)
 * @param exerciseId - Firestore document ID in the `exercises` collection
 * @param alias  - Raw alias string (will be normalized before storing)
 * @returns { status: 'ok' } on write, { status: 'noop' } when alias already exists
 */
export async function runAddAlias(
  app: admin.app.App,
  callerId: string,
  exerciseId: string,
  alias: string,
): Promise<{ status: "ok" | "noop" }> {
  const db = admin.firestore(app);

  // ── Guard: inputs must be non-empty ──────────────────────────────────────
  // Validated here (not only in the callable wrapper) so runAddAlias is
  // independently testable without going through the onCall harness.
  if (!exerciseId || !alias) {
    throw new HttpsError(
      "invalid-argument",
      "exerciseId and alias are required.",
    );
  }

  // ── Guard: caller must be a trainer ──────────────────────────────────────
  const userSnap = await db.collection("users").doc(callerId).get();
  if (!userSnap.exists || userSnap.data()?.role !== "trainer") {
    throw new HttpsError("permission-denied", "Caller must be a trainer.");
  }

  // ── Guard: exercise must exist ────────────────────────────────────────────
  const exerciseRef = db.collection("exercises").doc(exerciseId);
  const exerciseSnap = await exerciseRef.get();
  if (!exerciseSnap.exists) {
    throw new HttpsError("not-found", "Exercise not found.");
  }

  // ── Normalize + dedup (idempotency) ───────────────────────────────────────
  const normalized = normalize(alias);
  const existing = (exerciseSnap.data()?.aliases ?? []) as string[];
  if (existing.includes(normalized)) {
    return { status: "noop" };
  }

  // ── Write: arrayUnion appends the normalized alias ────────────────────────
  await exerciseRef.update({ aliases: FieldValue.arrayUnion(normalized) });

  return { status: "ok" };
}

/**
 * The v2 callable exported as the Firebase Function.
 * Named export so firebase-functions-test can wrap it directly.
 * Deployed to southamerica-east1 per ADR-CXP-004 / REQ-CXP-CF-008.
 */
export const addAlias = functions.onCall(
  // QA-SEC-006: enforce App Check so only the legitimate, attested app can
  // mutate the exercise catalog. Defense-in-depth on top of request.auth.
  // See PR body for the release prerequisite before deploy.
  { region: "southamerica-east1", enforceAppCheck: true },
  async (request): Promise<{ status: "ok" | "noop" }> => {
    // ── Guard: caller must be authenticated ─────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { exerciseId, alias } = request.data as {
      exerciseId?: string;
      alias?: string;
    };

    // ── Guard: inputs must be non-empty ─────────────────────────────────────
    if (!exerciseId || !alias) {
      throw new HttpsError(
        "invalid-argument",
        "exerciseId and alias are required.",
      );
    }

    return runAddAlias(getApp(), request.auth.uid, exerciseId, alias);
  },
);
