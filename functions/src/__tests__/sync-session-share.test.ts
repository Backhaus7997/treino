/**
 * Unit tests for syncSessionShareHandler.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   - active link → session_shares/{athleteId} created/updated with trainerId
 *   - link becomes terminated → share removed
 *   - link becomes terminated but share belongs to a different trainer → NOT removed
 *   - link deleted (after=undefined) → share removed
 *   - link deleted but share belongs to a different trainer → NOT removed
 *   - no-op: non-active status with no existing share → nothing happens
 *   - missing trainerId/athleteId → skipped gracefully
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "sync-session-share-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

import { syncSessionShareHandler } from "../sync-session-share";

const db = () => admin.firestore(testApp);

const TRAINER_A = "trainer-A";
const TRAINER_B = "trainer-B";
const ATHLETE = "athlete-X";

function link(
  status: string,
  trainerId = TRAINER_A,
  athleteId = ATHLETE,
  extra: Record<string, unknown> = {},
) {
  return { trainerId, athleteId, status, ...extra };
}

async function getShare(
  athleteId: string,
): Promise<admin.firestore.DocumentData | undefined> {
  const snap = await db().collection("session_shares").doc(athleteId).get();
  return snap.exists ? snap.data() : undefined;
}

async function seedShare(athleteId: string, trainerId: string): Promise<void> {
  await db()
    .collection("session_shares")
    .doc(athleteId)
    .set({ trainerId, updatedAt: admin.firestore.Timestamp.now() });
}

async function cleanupShare(athleteId: string): Promise<void> {
  await db()
    .collection("session_shares")
    .doc(athleteId)
    .delete()
    .catch(() => undefined);
}

// ---------------------------------------------------------------------------
// Active link → share created
// ---------------------------------------------------------------------------

describe("active link → share granted", () => {
  afterEach(() => cleanupShare(ATHLETE));

  it("creates session_shares/{athleteId} with correct trainerId", async () => {
    await syncSessionShareHandler(
      testApp,
      link("pending"),
      link("active"),
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeDefined();
    expect(share?.trainerId).toBe(TRAINER_A);
  });

  it("overwrites an existing share from the same trainer when link goes active", async () => {
    await seedShare(ATHLETE, TRAINER_A);

    await syncSessionShareHandler(
      testApp,
      link("pending"),
      link("active"),
    );

    const share = await getShare(ATHLETE);
    expect(share?.trainerId).toBe(TRAINER_A);
  });
});

// ---------------------------------------------------------------------------
// Link becomes non-active → share removed (same trainer)
// ---------------------------------------------------------------------------

describe("link→terminated → share removed when it belongs to this trainer", () => {
  beforeEach(() => seedShare(ATHLETE, TRAINER_A));
  afterEach(() => cleanupShare(ATHLETE));

  it("removes the share when status changes to terminated", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active"),
      link("terminated"),
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeUndefined();
  });

  it("removes the share when status changes to paused", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active"),
      link("paused"),
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Link→terminated but share belongs to a DIFFERENT trainer → NOT removed
// ---------------------------------------------------------------------------

describe("link→terminated but share belongs to different trainer → NOT removed", () => {
  beforeEach(() => seedShare(ATHLETE, TRAINER_B));
  afterEach(() => cleanupShare(ATHLETE));

  it("leaves share untouched when it points to TRAINER_B and this link is TRAINER_A", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active", TRAINER_A),
      link("terminated", TRAINER_A),
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeDefined();
    expect(share?.trainerId).toBe(TRAINER_B);
  });
});

// ---------------------------------------------------------------------------
// Link deleted (after=undefined) → share removed (same trainer)
// ---------------------------------------------------------------------------

describe("link deleted (after=undefined) → share removed", () => {
  beforeEach(() => seedShare(ATHLETE, TRAINER_A));
  afterEach(() => cleanupShare(ATHLETE));

  it("removes the share when the link document is deleted", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active"),
      undefined,
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Link deleted but share belongs to a DIFFERENT trainer → NOT removed
// ---------------------------------------------------------------------------

describe("link deleted but share belongs to different trainer → NOT removed", () => {
  beforeEach(() => seedShare(ATHLETE, TRAINER_B));
  afterEach(() => cleanupShare(ATHLETE));

  it("leaves share untouched when it points to TRAINER_B and deleted link is TRAINER_A", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active", TRAINER_A),
      undefined,
    );

    const share = await getShare(ATHLETE);
    expect(share).toBeDefined();
    expect(share?.trainerId).toBe(TRAINER_B);
  });
});

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

describe("edge cases", () => {
  afterEach(() => cleanupShare(ATHLETE));

  it("is a no-op when status is not active and no share doc exists", async () => {
    await syncSessionShareHandler(
      testApp,
      link("active"),
      link("terminated"),
    );

    // No share was seeded — nothing to delete.
    const share = await getShare(ATHLETE);
    expect(share).toBeUndefined();
  });

  it("skips gracefully when trainerId is missing", async () => {
    await expect(
      syncSessionShareHandler(
        testApp,
        undefined,
        { athleteId: ATHLETE, status: "active" } as Record<string, unknown>,
      ),
    ).resolves.toBeUndefined();
  });

  it("skips gracefully when athleteId is missing", async () => {
    await expect(
      syncSessionShareHandler(
        testApp,
        undefined,
        { trainerId: TRAINER_A, status: "active" } as Record<string, unknown>,
      ),
    ).resolves.toBeUndefined();
  });
});
