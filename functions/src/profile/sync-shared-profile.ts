/**
 * syncSharedProfile — Cloud Function for TREINO.
 *
 * Fires on writes to `users/{uid}`. When the athlete edits their profile,
 * if they have an active `profile_shares/{uid}` doc (they opted in to share),
 * this CF refreshes the snapshot fields so the coach always sees fresh data.
 *
 * Behaviour:
 *   - `userAfter` is null (user deleted) → skip (no-op).
 *   - `profile_shares/{uid}` does not exist → no-op (`not-sharing`).
 *   - `profile_shares/{uid}` exists but no shared field changed → no write
 *     (`no-change`). Short-circuits to avoid write amplification.
 *   - At least one shared field changed → merge the new snapshot into
 *     `profile_shares/{uid}` (keeping `trainerId`), bump `updatedAt` →
 *     returns `synced`.
 *
 * Note: this CF writes `profile_shares`, NOT `users`, so there is no direct
 * self-trigger loop with the `users/{uid}` trigger.
 *
 * Wire format produced EXACTLY matches `ProfileShareRepository.grant()` in
 * lib/features/coach/data/profile_share_repository.dart:
 *   - trainerId:         string (kept via merge, not written here)
 *   - updatedAt:         Timestamp.fromDate(now)
 *   - phone:             string | absent
 *   - bornAt:            Timestamp | absent
 *   - heightCm:          number | absent
 *   - bodyWeightKg:      number | absent
 *   - gender:            'male'|'female'|'non_binary'|'undisclosed' | absent
 *   - experienceLevel:   'beginner'|'intermediate'|'advanced' | absent
 *
 * Deployed to southamerica-east1 (matches all other TREINO CFs).
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

// ---------------------------------------------------------------------------
// Lazy app singleton (project convention — mirrors sync-session-share.ts)
// ---------------------------------------------------------------------------

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

// ---------------------------------------------------------------------------
// Shared field names — the subset of UserProfile fields that profile_shares
// exposes. Must stay in sync with ProfileShareRepository.grant().
// ---------------------------------------------------------------------------

const SHARED_FIELDS = [
  "phone",
  "bornAt",
  "heightCm",
  "bodyWeightKg",
  "gender",
  "experienceLevel",
] as const;

type SharedFieldName = (typeof SHARED_FIELDS)[number];

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

export interface SyncSharedProfileResult {
  updated: boolean;
  reason: "not-sharing" | "no-change" | "synced" | "user-deleted";
}

// ---------------------------------------------------------------------------
// Pure handler — emulator-testable, `now` injected for deterministic tests
// ---------------------------------------------------------------------------

/**
 * Refreshes `profile_shares/{uid}` snapshot fields when the athlete's user
 * doc changes.
 *
 * @param app       - Admin SDK app instance.
 * @param uid       - The athlete's uid (document id in both `users` and
 *                    `profile_shares`).
 * @param userAfter - The `users/{uid}` document data AFTER the write, or
 *                    `null` if the user doc was deleted.
 * @param now       - Reference timestamp for `updatedAt` (injected for tests).
 * @returns A result object indicating whether the snapshot was updated.
 */
export async function syncSharedProfileHandler(
  app: admin.app.App,
  uid: string,
  userAfter: Record<string, unknown> | null,
  now: Date,
): Promise<SyncSharedProfileResult> {
  // ── 1. User doc deleted → nothing to sync ─────────────────────────────────
  if (userAfter === null) {
    logger.info("syncSharedProfile: user doc deleted — skipping", { uid });
    return { updated: false, reason: "user-deleted" };
  }

  const db = admin.firestore(app);
  const shareRef = db.collection("profile_shares").doc(uid);

  // ── 2. Read existing profile_shares/{uid} ─────────────────────────────────
  const shareSnap = await shareRef.get();
  if (!shareSnap.exists) {
    logger.info("syncSharedProfile: no profile_shares doc — not sharing", {
      uid,
    });
    return { updated: false, reason: "not-sharing" };
  }

  const existingShare = shareSnap.data() as Record<string, unknown>;

  // ── 3. Build new snapshot from userAfter ──────────────────────────────────
  //
  // We replicate the exact same conditional-include logic as grant():
  // only non-null fields are present in the Firestore doc.
  //
  // `bornAt` arrives in `users/{uid}` as a Firestore Timestamp (written by the
  // mobile client via TimestampConverter). We detect this by checking for the
  // `.toDate()` method and convert back to a Timestamp for profile_shares.
  const newSnapshot: Record<string, unknown> = {};

  const phone = userAfter["phone"];
  if (typeof phone === "string") newSnapshot["phone"] = phone;

  const bornAt = userAfter["bornAt"];
  if (bornAt !== null && bornAt !== undefined) {
    // Could be a Firestore Timestamp (from Admin SDK read) or a raw object.
    if (
      typeof (bornAt as admin.firestore.Timestamp).toDate === "function"
    ) {
      newSnapshot["bornAt"] = bornAt; // already a Timestamp — use as-is
    } else if (bornAt instanceof Date) {
      newSnapshot["bornAt"] = admin.firestore.Timestamp.fromDate(bornAt);
    }
  }

  const heightCm = userAfter["heightCm"];
  if (typeof heightCm === "number") newSnapshot["heightCm"] = heightCm;

  const bodyWeightKg = userAfter["bodyWeightKg"];
  if (typeof bodyWeightKg === "number")
    newSnapshot["bodyWeightKg"] = bodyWeightKg;

  const gender = userAfter["gender"];
  if (typeof gender === "string") newSnapshot["gender"] = gender;

  const experienceLevel = userAfter["experienceLevel"];
  if (typeof experienceLevel === "string")
    newSnapshot["experienceLevel"] = experienceLevel;

  // ── 4. Short-circuit if nothing changed ───────────────────────────────────
  //
  // Compare each shared field between the NEW snapshot and the EXISTING doc.
  // For Timestamps we compare seconds+nanoseconds (structural equality).
  // For primitives we use strict equality.
  //
  // A field is considered changed if:
  //   - it is present in newSnapshot but absent in existingShare (or vice versa)
  //   - it is present in both but its value differs

  function timestampSeconds(v: unknown): number | undefined {
    if (v && typeof (v as admin.firestore.Timestamp).seconds === "number") {
      return (v as admin.firestore.Timestamp).seconds;
    }
    return undefined;
  }

  function valuesEqual(a: unknown, b: unknown): boolean {
    const aTs = timestampSeconds(a);
    const bTs = timestampSeconds(b);
    if (aTs !== undefined && bTs !== undefined) {
      return (
        aTs === bTs &&
        (a as admin.firestore.Timestamp).nanoseconds ===
          (b as admin.firestore.Timestamp).nanoseconds
      );
    }
    return a === b;
  }

  const changedFields: SharedFieldName[] = [];

  for (const field of SHARED_FIELDS) {
    const newVal = newSnapshot[field];
    const oldVal = existingShare[field];
    const newPresent = newVal !== undefined;
    const oldPresent = oldVal !== undefined;

    if (newPresent !== oldPresent || !valuesEqual(newVal, oldVal)) {
      changedFields.push(field);
    }
  }

  if (changedFields.length === 0) {
    logger.info("syncSharedProfile: no shared field changed — skipping write", {
      uid,
    });
    return { updated: false, reason: "no-change" };
  }

  // ── 5. Merge updated snapshot into profile_shares/{uid} ───────────────────
  //
  // We use set+merge so `trainerId` (and any future fields we don't touch here)
  // are preserved. We ONLY write the fields that are in our new snapshot plus
  // `updatedAt` — we do NOT write null/absent fields to avoid overwriting with
  // gaps (same semantics as grant()).
  const writePayload: Record<string, unknown> = {
    ...newSnapshot,
    updatedAt: admin.firestore.Timestamp.fromDate(now),
  };

  await shareRef.set(writePayload, { merge: true });

  logger.info("syncSharedProfile: snapshot refreshed", {
    uid,
    changedFields,
  });

  return { updated: true, reason: "synced" };
}

// ---------------------------------------------------------------------------
// onDocumentWritten wrapper
// ---------------------------------------------------------------------------

/**
 * Cloud Function trigger — fires on any write to `users/{uid}`.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const syncSharedProfile = onDocumentWritten(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const uid = event.params.uid;
    const userAfter =
      (event.data?.after?.data() as Record<string, unknown> | undefined) ??
      null;
    const result = await syncSharedProfileHandler(
      getApp(),
      uid,
      userAfter,
      new Date(),
    );
    logger.info("syncSharedProfile: done", { uid, ...result });
  },
);
