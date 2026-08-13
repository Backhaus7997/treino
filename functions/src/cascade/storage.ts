/**
 * Storage cascade module — deletes the athlete's objects from Firebase Storage.
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
 * Deletes the avatar file(s) for the given uid from Storage.
 *
 * QA-CMP-002: matches `avatars/{uid}.<ext>` for ANY extension — storage.rules
 * allows any `image/*`, so the old hardcoded `avatars/{uid}.jpg` left `.heic`
 * (and other) avatars orphaned. Returns the number of objects deleted.
 */
export async function deleteAvatar(
  app: admin.app.App,
  uid: string
): Promise<{ deleted: number }> {
  // Admin SDK bypasses Storage security rules (ADR-ACCDEL-013)
  const bucket = admin.storage(app).bucket();
  const [files] = await bucket.getFiles({ prefix: `avatars/${uid}` });
  // Guard against a different uid that merely has this uid as a prefix: only
  // `avatars/{uid}.<ext>` counts (the file name is exactly the uid + extension).
  const owned = files.filter((f) => f.name.startsWith(`avatars/${uid}.`));
  await Promise.all(owned.map((f) => f.delete()));
  return { deleted: owned.length };
}

/**
 * Deletes the athlete's non-avatar Storage objects (QA-CMP-002):
 *  - temp/uploads/{uid}/**            (uid-prefixed tree)
 *  - customExerciseVideos/{uid}/**    (uid-prefixed tree)
 *  - chatMedia/{chatId}/{uid}/**      (uid is the 2nd segment — scoped to the
 *    athlete's chats, resolved from Firestore)
 *  - athleteFiles/{trainerId}_{uid}/** (trainer-authored files about the
 *    athlete — deleted per the trainer-authored-data product decision)
 *
 * Returns the total number of objects deleted.
 */
export async function deleteAthleteStorage(
  app: admin.app.App,
  uid: string
): Promise<{ deleted: number }> {
  const bucket = admin.storage(app).bucket();
  let deleted = 0;

  const deleteByPrefix = async (prefix: string): Promise<void> => {
    const [files] = await bucket.getFiles({ prefix });
    await Promise.all(files.map((f) => f.delete()));
    deleted += files.length;
  };

  await deleteByPrefix(`temp/uploads/${uid}/`);
  await deleteByPrefix(`customExerciseVideos/${uid}/`);

  // chatMedia is keyed chatMedia/{chatId}/{uid}/… — the uid is the SECOND
  // segment, so there is no single prefix. Scope by the athlete's chats.
  const db = admin.firestore(app);
  const chats = await db
    .collection("chats")
    .where("members", "array-contains", uid)
    .get();
  for (const chat of chats.docs) {
    await deleteByPrefix(`chatMedia/${chat.id}/${uid}/`);
  }

  // athleteFiles/{trainerId}_{athleteId}/… — the athlete is the second half of
  // the pair id, so filter the listing rather than prefix-match.
  const [athleteFiles] = await bucket.getFiles({ prefix: "athleteFiles/" });
  const owned = athleteFiles.filter(
    (f) => (f.name.split("/")[1] ?? "").endsWith(`_${uid}`)
  );
  await Promise.all(owned.map((f) => f.delete()));
  deleted += owned.length;

  return { deleted };
}
