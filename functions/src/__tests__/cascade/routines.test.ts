/**
 * Integration tests for the routines cascade module (QA-CMP-004).
 * Run against the Firebase Local Emulator (Firestore).
 *
 * This is a DESTRUCTIVE deletion path, so the negative assertions carry as
 * much weight as the positive ones: every "leaves X untouched" test below
 * pins a document that a slightly wider predicate would silently destroy —
 * a trainer's own template library, the plans that trainer assigned to their
 * OTHER athletes, the seeded system catalogue.
 *
 * The `assignedBy` test pins a deliberate NON-deletion. See the module header
 * for why sweeping that field would let an idempotent re-run (where the
 * trainer role guard can no longer read `users/{uid}`) wipe a trainer's whole
 * library.
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "routines-cascade-test"
  );
});

afterAll(async () => {
  await testApp.delete();
});

import { deleteAthleteRoutines } from "../../cascade/routines";

const db = () => admin.firestore(testApp);

const UID = "athlete-routines-cmp";
const OTHER_ATHLETE = "athlete-routines-other";
const TRAINER = "trainer-routines-x";

/** Every routine id this suite writes, so cleanup never leaks into siblings. */
const ALL_IDS = [
  "rt-assigned-1",
  "rt-assigned-2",
  "rt-own-private",
  "rt-own-public",
  "rt-own-archived",
  "rt-other-assigned",
  "rt-other-own",
  "rt-trainer-template",
  "rt-trainer-published",
  "rt-system",
  "rt-forged-by-uid",
];

/**
 * Seeds the full fixture: what must go, and what must survive.
 * Mirrors the shapes firestore.rules actually admits (CREATE branch 1 for
 * trainer docs, branch 2 for athlete docs).
 */
async function seed(): Promise<void> {
  const batch = db().batch();
  const r = (id: string) => db().collection("routines").doc(id);

  // ── MUST BE DELETED ──────────────────────────────────────────────────────
  // Plans the trainer built for this athlete.
  batch.set(r("rt-assigned-1"), {
    name: "Plan del coach 1",
    source: "trainer-assigned",
    assignedBy: TRAINER,
    assignedTo: UID,
    visibility: "private",
  });
  batch.set(r("rt-assigned-2"), {
    name: "Plan del coach 2",
    source: "trainer-assigned",
    assignedBy: TRAINER,
    assignedTo: UID,
    visibility: "shared",
  });
  // The athlete's own routines — private, public (REQ-USR-012) and archived.
  batch.set(r("rt-own-private"), {
    name: "Mi rutina",
    source: "user-created",
    createdBy: UID,
    visibility: "private",
    status: "active",
  });
  batch.set(r("rt-own-public"), {
    name: "Mi rutina publicada",
    source: "user-created",
    createdBy: UID,
    visibility: "public",
    status: "active",
  });
  batch.set(r("rt-own-archived"), {
    name: "Mi rutina archivada",
    source: "user-created",
    createdBy: UID,
    visibility: "private",
    status: "archived",
  });

  // ── MUST SURVIVE ─────────────────────────────────────────────────────────
  // Same trainer, a DIFFERENT athlete.
  batch.set(r("rt-other-assigned"), {
    name: "Plan de otro alumno",
    source: "trainer-assigned",
    assignedBy: TRAINER,
    assignedTo: OTHER_ATHLETE,
    visibility: "private",
  });
  // Another athlete's own routine.
  batch.set(r("rt-other-own"), {
    name: "Rutina de otro",
    source: "user-created",
    createdBy: OTHER_ATHLETE,
    visibility: "public",
    status: "active",
  });
  // The trainer's reusable library — `assignedTo: null`, never an athlete's.
  batch.set(r("rt-trainer-template"), {
    name: "Plantilla del PF",
    source: "trainer-template",
    assignedBy: TRAINER,
    assignedTo: null,
    visibility: "private",
  });
  // A community-published trainer template other athletes are using.
  batch.set(r("rt-trainer-published"), {
    name: "Plantilla publicada",
    source: "trainer-template",
    assignedBy: TRAINER,
    assignedTo: null,
    visibility: "public",
    ratingAvg: 4.5,
    ratingsCount: 2,
  });
  // The seeded system catalogue.
  batch.set(r("rt-system"), {
    name: "Full Body 3 días",
    source: "system",
    visibility: "public",
  });

  await batch.commit();
}

/** Ids still present in Firestore, from [ALL_IDS]. */
async function surviving(): Promise<string[]> {
  const snaps = await db().getAll(
    ...ALL_IDS.map((id) => db().collection("routines").doc(id))
  );
  return snaps.filter((s) => s.exists).map((s) => s.id);
}

async function cleanup(): Promise<void> {
  for (const id of ALL_IDS) {
    await db().recursiveDelete(db().collection("routines").doc(id));
  }
}

describe("deleteAthleteRoutines — QA-CMP-004", () => {
  beforeEach(seed);
  afterEach(cleanup);

  it("deletes the plans the trainer assigned TO the athlete", async () => {
    await deleteAthleteRoutines(testApp, UID);

    const left = await surviving();
    expect(left).not.toContain("rt-assigned-1");
    expect(left).not.toContain("rt-assigned-2");
  });

  it("deletes the athlete's own routines, public and archived included", async () => {
    await deleteAthleteRoutines(testApp, UID);

    const left = await surviving();
    expect(left).not.toContain("rt-own-private");
    expect(left).not.toContain("rt-own-public");
    expect(left).not.toContain("rt-own-archived");
  });

  it("reports the number of routine documents deleted", async () => {
    const { deleted } = await deleteAthleteRoutines(testApp, UID);
    expect(deleted).toBe(5);
  });

  it("leaves every third-party routine untouched", async () => {
    await deleteAthleteRoutines(testApp, UID);

    // Exactly the five survivors — nothing more, nothing less.
    expect((await surviving()).sort()).toEqual(
      [
        "rt-other-assigned",
        "rt-other-own",
        "rt-system",
        "rt-trainer-published",
        "rt-trainer-template",
      ].sort()
    );
  });

  it("does not touch the trainer's library when the trainer's own uid is passed", async () => {
    // Pins the deliberate decision NOT to sweep `assignedBy`. If someone
    // widens the predicate, this fails loudly instead of a trainer losing
    // every template and every athlete losing every assigned plan on an
    // idempotent re-run.
    const { deleted } = await deleteAthleteRoutines(testApp, TRAINER);

    expect(deleted).toBe(0);
    const left = await surviving();
    expect(left).toContain("rt-trainer-template");
    expect(left).toContain("rt-trainer-published");
    expect(left).toContain("rt-assigned-1");
    expect(left).toContain("rt-other-assigned");
  });

  it("deletes the ratings subcollection along with the parent routine", async () => {
    // Firestore does NOT cascade subcollections, and
    // routines/{id}/ratings/{userId} is `allow delete: if false` — an orphan
    // here can never be removed by anyone but the Admin SDK (QA-CMP-006).
    const parent = db().collection("routines").doc("rt-own-public");
    await parent.collection("ratings").doc("rater-a").set({
      userId: "rater-a",
      rating: 5,
      comment: "buenísima",
    });
    await parent.collection("ratings").doc("rater-b").set({
      userId: "rater-b",
      rating: 4,
    });
    expect((await parent.collection("ratings").get()).size).toBe(2);

    await deleteAthleteRoutines(testApp, UID);

    expect((await parent.get()).exists).toBe(false);
    expect((await parent.collection("ratings").get()).empty).toBe(true);
  });

  it("counts a document matching both predicates once", async () => {
    // Not producible through firestore.rules, but a legacy or Admin-written
    // doc could carry both fields; the dedupe must not double-count it.
    await db().collection("routines").doc("rt-forged-by-uid").set({
      name: "Doc con los dos campos",
      source: "trainer-assigned",
      assignedBy: TRAINER,
      assignedTo: UID,
      createdBy: UID,
      visibility: "private",
    });

    const { deleted } = await deleteAthleteRoutines(testApp, UID);

    expect(deleted).toBe(6);
    expect(await surviving()).not.toContain("rt-forged-by-uid");
  });

  it("is a no-op for an athlete with no routines", async () => {
    const { deleted } = await deleteAthleteRoutines(testApp, "nobody-here");
    expect(deleted).toBe(0);
    expect((await surviving()).length).toBe(ALL_IDS.length - 1);
  });

  it("is idempotent — a second run deletes nothing and throws nothing", async () => {
    await deleteAthleteRoutines(testApp, UID);
    const { deleted } = await deleteAthleteRoutines(testApp, UID);
    expect(deleted).toBe(0);
  });
});
