/**
 * Routines cascade — hard-deletes the `routines` documents that belong to the
 * athlete being deleted. QA-CMP-004.
 *
 * This is the step that `cleanupAssignedPlansOnUnlink` has been delegating to
 * since it was written. That trigger short-circuits on
 * `reason === 'account-deleted'` ("the account-deletion cascade owns that
 * flow"), and `'account-deleted'` is exactly the reason
 * `cascade/trainer-links.ts` stamps on every link it terminates — so until
 * this module existed, the only mechanism that would have swept the athlete's
 * assigned plans turned itself off precisely when it was needed.
 *
 * Disposition (product decision, 2026-08-24):
 *   assignedTo == uid  — the private plans a trainer built FOR this athlete
 *                        (`source: 'trainer-assigned'`)              → DELETE
 *   createdBy  == uid  — the athlete's own routines
 *                        (`source: 'user-created'`)                  → DELETE
 *   assignedBy == uid  — NOT a predicate here. Deliberate — see below.
 *
 * Why `createdBy` IS safe to delete (the half that is not obvious):
 *   The case worth fearing — a PUBLIC trainer template that other athletes are
 *   using — can never be a `createdBy` document. Templates are keyed by
 *   `assignedBy` (firestore.rules CREATE branch 1; `createdBy` is only written
 *   by CREATE branch 2, which pins `source == 'user-created'`), and a trainer
 *   cannot reach this cascade at all: `runDeleteAccount` refuses `role ==
 *   'trainer'` before step 1. `Routine.createdBy` says the same thing from the
 *   model side — "null para plantillas del sistema y planes asignados por PF".
 *
 *   A `user-created` routine CAN be `visibility: 'public'` (REQ-USR-012,
 *   "share to my public profile"), which makes it readable by any
 *   authenticated user that holds its id. It is still the deleted athlete's
 *   own content and it is unreachable once they are gone: the single surface
 *   that lists these is `publicRoutinesByUserProvider`, the RUTINAS PÚBLICAS
 *   tab of *that user's* public profile, and `userPublicProfiles/{uid}` is
 *   deleted by `cascade/users.ts`. The catalogue queries never see it either —
 *   `listSystemTemplates` filters `source == 'system'` and
 *   `listPublishedTemplates` filters `source == 'trainer-template'`. And no
 *   third party can have adopted one: `activeRoutineId` is only ever written
 *   from the athlete's OWN routine list.
 *
 * Why `assignedBy` is deliberately NOT swept (the dangerous predicate):
 *   The trainer role guard reads `users/{uid}`. On an idempotent RE-RUN after
 *   a partial failure — `deleteUserDocs` succeeded, Auth deletion did not
 *   (REQ-ACCDEL-CF-013) — that document is already gone and the guard CANNOT
 *   fire. A cascade keyed on `assignedBy` would then delete every template the
 *   trainer owns plus every plan they ever assigned to every one of their
 *   athletes. `assignedTo` and `createdBy` are both immune to that scenario:
 *   neither field ever carries a trainer uid in well-formed data.
 *   The residue this leaves is a forged athlete-held `trainer-template` (an
 *   athlete CAN create one — CREATE branch 1 predates the role check). It is
 *   private, unpublishable (UPDATE path 5 requires `role == 'trainer'`) and
 *   readable only by its now-deleted author. Not worth that blast radius.
 *
 * Subcollections: `recursiveDelete`, never `batch.delete`. Firestore does NOT
 * cascade subcollections, and `routines/{id}/ratings/{userId}` carries
 * `allow delete: if false` — an orphan under a deleted parent can never be
 * removed by anyone except the Admin SDK. QA-CMP-006.
 *   Still open, and NOT fixed here: the ratings this athlete left on OTHER
 *   people's templates (`routines/*\/ratings/{uid}` under a third party's
 *   routine). That is the other half of QA-CMP-006 and needs a collection-group
 *   sweep, not this module's two queries.
 *   Deleting a rating fires `templateRatingAggregate`; it is a no-op or an
 *   overwrite of a document this module is about to delete — that trigger
 *   checks parent existence before writing and uses `update()`, so it cannot
 *   resurrect a routine as a stub (QA-507).
 *
 * TRUST BOUNDARY: Admin SDK bypasses firestore.rules (including the narrow
 * `allow delete` on /routines, which lets neither the athlete nor anyone else
 * remove these). Server-side (Cloud Function) only. ADR-ACCDEL-013.
 */

import * as admin from "firebase-admin";

/**
 * Deletes every routine document that belongs to [uid], with its
 * subcollections. Returns the count of ROUTINE documents removed
 * (subcollection documents are not counted).
 *
 * Both queries are single-field equality filters, so they ride Firestore's
 * automatic indexes — no composite index to declare.
 *
 * Idempotent: a second run finds nothing and returns 0.
 */
export async function deleteAthleteRoutines(
  app: admin.app.App,
  uid: string
): Promise<{ deleted: number }> {
  const db = admin.firestore(app);
  const routines = db.collection("routines");

  const [assigned, authored] = await Promise.all([
    routines.where("assignedTo", "==", uid).get(),
    routines.where("createdBy", "==", uid).get(),
  ]);

  // Dedupe by document id. The two predicates are mutually exclusive in
  // well-formed data (a `trainer-assigned` doc has no `createdBy`), but a
  // hand-written or legacy document carrying both would otherwise be
  // recursiveDeleted twice and counted twice.
  const refs = new Map<string, admin.firestore.DocumentReference>();
  for (const doc of [...assigned.docs, ...authored.docs]) {
    refs.set(doc.id, doc.ref);
  }

  // Sequential on purpose: each recursiveDelete drives its own BulkWriter,
  // which already batches the subtree internally. A single athlete's routine
  // count is bounded by hand-authoring (tens, not thousands), so the extra
  // round-trips are cheaper than reasoning about a shared writer's lifetime
  // inside a cascade step that must not throw halfway through.
  for (const ref of refs.values()) {
    await db.recursiveDelete(ref);
  }

  return { deleted: refs.size };
}
