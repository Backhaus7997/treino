/**
 * Trainer (PF) account-deletion cascade — #1333.
 *
 * Every function here runs UNCONDITIONALLY from `runDeleteAccount`, with no
 * role check: for an athlete uid every query (`trainerId == uid`,
 * `assignedBy == uid`) comes back empty, so the whole module is a no-op. That
 * is deliberate. The old role guard read `users/{uid}`, which is already gone
 * on an idempotent re-run after a partial failure; a cascade that depended on
 * it would silently skip the PF's data on the retry.
 *
 * Why this is safe even without the role guard (the warning in
 * `cascade/routines.ts` about `assignedBy`): trainer-keyed fields never carry
 * an athlete uid in well-formed data, and the routines sweep is filtered by
 * `source == 'trainer-template'`, which can never match an assigned plan.
 *
 * Index rule: the emulator does NOT enforce indexes. Every query below is a
 * single/multiple equality filter (automatic indexes) except the appointments
 * one, which matches the existing (trainerId, status, startsAt) composite in
 * `firestore.indexes.json`. No new index.
 *
 * TRUST BOUNDARY: Admin SDK bypasses firestore.rules. Server-side only.
 */

import { App } from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Query,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

/** Page size for paged deletes: below the 500-ops batch ceiling. */
const PAGE_SIZE = 400;

/**
 * Motivo con el que se terminan los vinculos / se cancelan los turnos del PF
 * que borra su cuenta.
 *
 * CONTRATO CF->CF: lo consumen `notify-link-change`, `notify-appointment`,
 * `purge-rejected-link` (+ `scripts/cleanup_rejected_links.js`) y
 * `cleanup-assigned-plans`. Mismo patron que
 * `ATHLETE_ACCOUNT_DELETED_REASON`: un solo simbolo en el productor, importado
 * por los consumidores, para que renombrarlo no rompa un guard en silencio.
 */
export const TRAINER_ACCOUNT_DELETED_REASON = "trainer-account-deleted";

/**
 * Deletes every document matched by [query], one page at a time, until a page
 * comes back empty. Returns the number of deleted documents.
 *
 * Unlike the athlete cascade (`get()` with no limit) a PF can own thousands of
 * `follow_up_entries`, so the result set is never loaded in one go.
 */
export async function deleteByQueryPaged(
  db: Firestore,
  query: Query
): Promise<number> {
  let deleted = 0;
  for (;;) {
    const snap = await query.limit(PAGE_SIZE).get();
    if (snap.empty) return deleted;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += snap.size;
    if (snap.size < PAGE_SIZE) return deleted;
  }
}

/**
 * T1 — terminates every non-terminal link where this uid is the TRAINER.
 *
 * Query is `trainerId == uid` only (automatic index; there is NO
 * (trainerId, status) composite) and the terminal ones are filtered in
 * memory. Writes exactly the keys the athlete cascade writes
 * (`status`, `reason`, `terminatedAt`): a new key would trip the #846 hasOnly
 * trap. The athlete is notified by `notify-link-change`, which reacts to this
 * reason; idempotency comes from the terminal status (a re-run finds nothing).
 */
export async function terminateLinksAsTrainer(
  app: App,
  uid: string
): Promise<{ count: number }> {
  const db = getFirestore(app);
  const snap = await db
    .collection("trainer_links")
    .where("trainerId", "==", uid)
    .get();

  const open = snap.docs.filter((d) => d.data().status !== "terminated");
  let count = 0;
  for (let i = 0; i < open.length; i += PAGE_SIZE) {
    const chunk = open.slice(i, i + PAGE_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "terminated",
        reason: TRAINER_ACCOUNT_DELETED_REASON,
        terminatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    count += chunk.length;
  }
  return { count };
}

/**
 * T2 — cancels the trainer's FUTURE open appointments and deletes their
 * availability (`coach_availability_rules` / `coach_availability_overrides`).
 *
 * Query: `trainerId == uid AND status in [requested, confirmed] AND
 * startsAt > now` — the existing (trainerId, status, startsAt) composite.
 * `requested` is not in the Dart enum (`confirmed|cancelled`) but
 * `notify-appointment` handles it, so it is cancelled too if it exists.
 *
 * Writes the same shape as `cascade/appointments.ts`: `reason` (the only key
 * the client cannot write: pinned in firestore.rules, #846), `cancelledBy` and
 * a `cancellationLog` entry. `notify-appointment` suppresses its own push for
 * this reason: the athlete is told once, through the link push, instead of N
 * times for a recurring series.
 */
export async function cancelFutureAppointmentsAsTrainer(
  app: App,
  uid: string
): Promise<{ count: number }> {
  const db = getFirestore(app);
  const snap = await db
    .collection("appointments")
    .where("trainerId", "==", uid)
    .where("status", "in", ["requested", "confirmed"])
    .where("startsAt", ">", Timestamp.now())
    .get();

  const atMs = Date.now();
  let count = 0;
  for (let i = 0; i < snap.docs.length; i += PAGE_SIZE) {
    const chunk = snap.docs.slice(i, i + PAGE_SIZE);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        status: "cancelled",
        reason: TRAINER_ACCOUNT_DELETED_REASON,
        cancelledBy: uid,
        cancellationLog: FieldValue.arrayUnion({
          byUid: uid,
          atMs,
          reason: TRAINER_ACCOUNT_DELETED_REASON,
        }),
      });
    }
    await batch.commit();
    count += chunk.length;
  }

  for (const col of ["coach_availability_rules", "coach_availability_overrides"]) {
    await deleteByQueryPaged(db, db.collection(col).where("trainerId", "==", uid));
  }
  return { count };
}

/**
 * Collections where the PF is the author / grantee and the doc carries
 * `trainerId == uid`. All single-equality queries (automatic indexes).
 *
 *  - athlete_notes, athlete_billing, athlete_files, follow_up_entries,
 *    nutrition_plans: trainer-authored records about athletes (no legal
 *    retention) — same disposition the athlete cascade applies from the
 *    other side.
 *  - reviews: written to/about this PF (`trainerId == uid`).
 *  - session_shares, profile_shares: doc id is the ATHLETE, `trainerId` is the
 *    grantee. They hold athlete PII granted to this PF; with the PF gone the
 *    grant is void.
 *
 * NOT here, on purpose:
 *  - `payments`: fiscal retention (SC-PSD-18).
 *  - `gyms`: shared catalogue (SC-PSD-21).
 *  - `users/{uid}/customExercises` and `customExerciseVideos/{uid}/`: V3 —
 *    already swept by `deleteUserDocs` (recursiveDelete of `users/{uid}`) and
 *    `deleteAthleteStorage` (uid-prefixed tree), both unconditional. Owner
 *    decision (#1341): they go with the account.
 */
const TRAINER_KEYED_COLLECTIONS = [
  "athlete_notes",
  "athlete_billing",
  "athlete_files",
  "follow_up_entries",
  "nutrition_plans",
  "reviews",
  "session_shares",
  "profile_shares",
];

/** T4 — deletes the data the PF wrote or was granted about athletes. */
export async function deleteTrainerOwnedData(
  app: App,
  uid: string
): Promise<{ deleted: number }> {
  const db = getFirestore(app);
  let deleted = 0;
  for (const col of TRAINER_KEYED_COLLECTIONS) {
    deleted += await deleteByQueryPaged(
      db,
      db.collection(col).where("trainerId", "==", uid)
    );
  }
  return { deleted };
}

/**
 * T5 — deletes the PF's routine TEMPLATES (private and published: same docs,
 * `visibility: 'public'`), with their `ratings` subcollection.
 *
 * The filter `source == 'trainer-template'` is what makes the `assignedBy`
 * predicate safe (see the header of `cascade/routines.ts`): assigned plans are
 * `source == 'trainer-assigned'` and are never matched, so they stay with the
 * athlete (owner decision #1335). Copies an athlete adopted from a published
 * template are separate `user-created` docs and survive.
 *
 * Equality-only query. `recursiveDelete` per doc: Firestore does not cascade
 * subcollections and `ratings` has `allow delete: if false`.
 */
export async function deleteTrainerTemplates(
  app: App,
  uid: string
): Promise<{ deleted: number }> {
  const db = getFirestore(app);
  const snap = await db
    .collection("routines")
    .where("assignedBy", "==", uid)
    .where("source", "==", "trainer-template")
    .get();
  for (const doc of snap.docs) {
    await db.recursiveDelete(doc.ref);
  }
  return { deleted: snap.size };
}
