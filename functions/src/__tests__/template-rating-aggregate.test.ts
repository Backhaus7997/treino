/**
 * Integration tests for the templateRatingAggregate Cloud Function.
 *
 * Tests run against the Firebase Local Emulator (Firestore).
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * Covered:
 *   - first rating created → ratingAvg + ratingsCount written to the routine
 *   - several ratings → fractional average recomputed
 *   - rating updated → average recomputed
 *   - rating deleted → average recomputed / cleared to null + 0
 *   - re-run with same data → idempotent
 *   - routine doc missing → warn + no-op, no throw, no resurrection
 *
 * Fase W3 (template publishing).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "template-rating-aggregate-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

import { recomputeTemplateRating } from "../template-rating-aggregate";

const db = () => admin.firestore(testApp);

function ratingsCol(routineId: string) {
  return db().collection("routines").doc(routineId).collection("ratings");
}

async function seedRoutine(routineId: string): Promise<void> {
  await db().collection("routines").doc(routineId).set({
    name: "Plantilla test",
    level: "beginner",
    days: [],
    numWeeks: 1,
    source: "trainer-template",
    visibility: "public",
    assignedBy: "trainer-agg",
    assignedTo: null,
    status: "active",
    createdAt: admin.firestore.Timestamp.now(),
  });
}

async function seedRating(
  routineId: string,
  uid: string,
  rating: number,
): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  await ratingsCol(routineId).doc(uid).set({
    userId: uid,
    rating,
    comment: null,
    createdAt: now,
    updatedAt: now,
  });
}

async function getAgg(
  routineId: string,
): Promise<{ ratingAvg: number | null; ratingsCount: number | null } | null> {
  const snap = await db().collection("routines").doc(routineId).get();
  if (!snap.exists) return null;
  const data = snap.data()!;
  return {
    ratingAvg: data.ratingAvg ?? null,
    ratingsCount: data.ratingsCount ?? null,
  };
}

async function cleanupRoutine(routineId: string): Promise<void> {
  const snap = await ratingsCol(routineId).get();
  const batch = db().batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  await db().collection("routines").doc(routineId).delete().catch(() => undefined);
}

describe("first rating created → aggregate written", () => {
  const routineId = "tpl-agg-001";

  beforeEach(() => seedRoutine(routineId));
  afterEach(() => cleanupRoutine(routineId));

  it("writes ratingAvg and ratingsCount after the first rating", async () => {
    await seedRating(routineId, "user-1", 4);

    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg).not.toBeNull();
    expect(agg!.ratingsCount).toBe(1);
    expect(agg!.ratingAvg).toBeCloseTo(4, 6);
  });
});

describe("several ratings → fractional average", () => {
  const routineId = "tpl-agg-002";

  beforeEach(() => seedRoutine(routineId));
  afterEach(() => cleanupRoutine(routineId));

  it("recomputes the average across raters", async () => {
    await seedRating(routineId, "user-1", 5);
    await seedRating(routineId, "user-2", 4);
    await seedRating(routineId, "user-3", 4);

    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg!.ratingsCount).toBe(3);
    expect(agg!.ratingAvg).toBeCloseTo(13 / 3, 6);
  });
});

describe("rating updated → recomputed", () => {
  const routineId = "tpl-agg-003";

  beforeEach(() => seedRoutine(routineId));
  afterEach(() => cleanupRoutine(routineId));

  it("reflects an edited rating", async () => {
    await seedRating(routineId, "user-1", 2);
    await seedRating(routineId, "user-2", 2);
    await ratingsCol(routineId).doc("user-2").update({ rating: 4 });

    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg!.ratingsCount).toBe(2);
    expect(agg!.ratingAvg).toBeCloseTo(3, 6);
  });
});

describe("rating deleted → recomputed / cleared", () => {
  const routineId = "tpl-agg-004";

  beforeEach(() => seedRoutine(routineId));
  afterEach(() => cleanupRoutine(routineId));

  it("recomputes after deleting one of two ratings", async () => {
    await seedRating(routineId, "user-1", 5);
    await seedRating(routineId, "user-2", 3);
    await ratingsCol(routineId).doc("user-1").delete();

    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg!.ratingsCount).toBe(1);
    expect(agg!.ratingAvg).toBeCloseTo(3, 6);
  });

  it("clears to null + 0 when the last rating disappears", async () => {
    await seedRating(routineId, "user-1", 5);
    await recomputeTemplateRating(testApp, routineId);
    await ratingsCol(routineId).doc("user-1").delete();

    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg!.ratingAvg).toBeNull();
    expect(agg!.ratingsCount).toBe(0);
  });
});

describe("idempotent re-run", () => {
  const routineId = "tpl-agg-005";

  beforeEach(() => seedRoutine(routineId));
  afterEach(() => cleanupRoutine(routineId));

  it("same result on a second call with the same data", async () => {
    await seedRating(routineId, "user-1", 5);

    await recomputeTemplateRating(testApp, routineId);
    await recomputeTemplateRating(testApp, routineId);

    const agg = await getAgg(routineId);
    expect(agg!.ratingsCount).toBe(1);
    expect(agg!.ratingAvg).toBeCloseTo(5, 6);
  });
});

describe("routine doc missing → no-op, no resurrection", () => {
  const routineId = "tpl-agg-006-missing";

  afterEach(() => cleanupRoutine(routineId));

  it("does not throw and does not create a stub routine doc", async () => {
    // Orphaned rating: the routine was deleted but its subcollection
    // survived (Firestore never cascades deletes).
    await seedRating(routineId, "user-1", 4);

    await expect(
      recomputeTemplateRating(testApp, routineId),
    ).resolves.not.toThrow();

    const snap = await db().collection("routines").doc(routineId).get();
    expect(snap.exists).toBe(false);
  });
});
