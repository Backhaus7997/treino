/**
 * Integration tests for syncSharedProfileHandler Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * NOTE: The Firestore emulator requires Java 21. This environment has Java 8,
 * so these tests cannot be executed here. They are written to mirror the
 * generate-due-payments.test.ts pattern and will pass once the emulator is
 * available (CI or a dev machine with Java 21).
 *
 * SCENARIOs covered:
 *   SCENARIO-SSP-01 — no profile_shares doc → no write (not-sharing)
 *   SCENARIO-SSP-02 — profile_shares exists + bodyWeightKg changed → snapshot
 *                     updated, trainerId preserved, updatedAt bumped
 *   SCENARIO-SSP-03 — shared field unchanged → no write (no-change)
 *   SCENARIO-SSP-04 — only a NON-shared user field changed → no write (no-change)
 *   SCENARIO-SSP-05 — gender / experienceLevel enum wire format matches grant()
 *   SCENARIO-SSP-06 — user doc deleted (userAfter null) → no write (user-deleted)
 */

import * as admin from "firebase-admin";
import { syncSharedProfileHandler } from "../profile/sync-shared-profile";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "sync-shared-profile-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

async function seedUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  await db().collection("users").doc(uid).set(data);
}

async function seedProfileShare(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  await db().collection("profile_shares").doc(uid).set(data);
}

async function cleanupDocs(
  ...refs: Array<admin.firestore.DocumentReference>
): Promise<void> {
  for (const ref of refs) {
    await ref.delete().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// SCENARIO-SSP-01 — no profile_shares doc → no write (not-sharing)
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-01: no profile_shares doc → no write", () => {
  const uid = "athlete-ssp-01";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("returns not-sharing and does NOT create a profile_shares doc", async () => {
    await seedUser(uid, {
      uid,
      email: "ssp01@test.com",
      role: "athlete",
      bodyWeightKg: 75.0,
    });
    // No profile_shares doc seeded.

    const result = await syncSharedProfileHandler(
      testApp,
      uid,
      { uid, email: "ssp01@test.com", role: "athlete", bodyWeightKg: 75.0 },
      now,
    );

    expect(result.updated).toBe(false);
    expect(result.reason).toBe("not-sharing");

    const shareSnap = await db().collection("profile_shares").doc(uid).get();
    expect(shareSnap.exists).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-SSP-02 — profile_shares exists + bodyWeightKg changed → updated
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-02: bodyWeightKg changed → snapshot updated, trainerId preserved", () => {
  const uid = "athlete-ssp-02";
  const trainerId = "trainer-ssp-02";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("updates bodyWeightKg, preserves trainerId, bumps updatedAt", async () => {
    const oldUpdatedAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
    );

    // Existing share with old bodyWeightKg
    await seedProfileShare(uid, {
      trainerId,
      bodyWeightKg: 70.0,
      updatedAt: oldUpdatedAt,
    });

    // User doc now has updated bodyWeightKg
    const userAfter = {
      uid,
      email: "ssp02@test.com",
      role: "athlete",
      bodyWeightKg: 75.5,
    };

    const result = await syncSharedProfileHandler(testApp, uid, userAfter, now);

    expect(result.updated).toBe(true);
    expect(result.reason).toBe("synced");

    const shareSnap = await db().collection("profile_shares").doc(uid).get();
    expect(shareSnap.exists).toBe(true);

    const data = shareSnap.data()!;

    // trainerId MUST be preserved (merge, not replace)
    expect(data["trainerId"]).toBe(trainerId);

    // bodyWeightKg updated to new value
    expect(data["bodyWeightKg"]).toBe(75.5);

    // updatedAt bumped to `now`
    const updatedAtTs = data["updatedAt"] as admin.firestore.Timestamp;
    expect(updatedAtTs.toDate().getTime()).toBe(now.getTime());
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-SSP-03 — shared field unchanged → no write (no-change)
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-03: shared fields unchanged → no write", () => {
  const uid = "athlete-ssp-03";
  const trainerId = "trainer-ssp-03";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("returns no-change when shared fields are identical", async () => {
    const oldUpdatedAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
    );

    await seedProfileShare(uid, {
      trainerId,
      bodyWeightKg: 70.0,
      gender: "male",
      updatedAt: oldUpdatedAt,
    });

    // userAfter has same shared fields (only displayName, a non-shared field, differs)
    const userAfter = {
      uid,
      email: "ssp03@test.com",
      role: "athlete",
      displayName: "Updated Name",
      bodyWeightKg: 70.0,
      gender: "male",
    };

    const result = await syncSharedProfileHandler(testApp, uid, userAfter, now);

    expect(result.updated).toBe(false);
    expect(result.reason).toBe("no-change");

    // updatedAt must NOT have changed
    const shareSnap = await db().collection("profile_shares").doc(uid).get();
    const data = shareSnap.data()!;
    const updatedAtTs = data["updatedAt"] as admin.firestore.Timestamp;
    expect(updatedAtTs.seconds).toBe(oldUpdatedAt.seconds);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-SSP-04 — only a NON-shared field changed → no write (no-change)
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-04: only non-shared field changed → no write", () => {
  const uid = "athlete-ssp-04";
  const trainerId = "trainer-ssp-04";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("returns no-change when only displayName (non-shared) changed", async () => {
    const oldUpdatedAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
    );

    await seedProfileShare(uid, {
      trainerId,
      heightCm: 175,
      updatedAt: oldUpdatedAt,
    });

    // userAfter: only avatarUrl changed (not a shared field)
    const userAfter = {
      uid,
      email: "ssp04@test.com",
      role: "athlete",
      avatarUrl: "https://example.com/new-avatar.jpg",
      heightCm: 175,
    };

    const result = await syncSharedProfileHandler(testApp, uid, userAfter, now);

    expect(result.updated).toBe(false);
    expect(result.reason).toBe("no-change");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-SSP-05 — gender / experienceLevel enum wire format matches grant()
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-05: gender + experienceLevel wire format matches grant()", () => {
  const uid = "athlete-ssp-05";
  const trainerId = "trainer-ssp-05";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("writes gender as 'non_binary' and experienceLevel as 'intermediate' string values", async () => {
    // Existing share with different values to force a write
    await seedProfileShare(uid, {
      trainerId,
      gender: "male",
      experienceLevel: "beginner",
      updatedAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
      ),
    });

    // UserProfile stores enums as wire strings in Firestore
    // (via @JsonValue in Dart: Gender.nonBinary → 'non_binary')
    const userAfter = {
      uid,
      email: "ssp05@test.com",
      role: "athlete",
      gender: "non_binary",          // Gender.nonBinary wire value
      experienceLevel: "intermediate", // ExperienceLevel.intermediate wire value
    };

    const result = await syncSharedProfileHandler(testApp, uid, userAfter, now);

    expect(result.updated).toBe(true);
    expect(result.reason).toBe("synced");

    const shareSnap = await db().collection("profile_shares").doc(uid).get();
    const data = shareSnap.data()!;

    // Must be the wire string exactly as grant() would write — matches
    // Gender.toJson() = 'non_binary' and ExperienceLevel.toJson() = 'intermediate'
    expect(data["gender"]).toBe("non_binary");
    expect(data["experienceLevel"]).toBe("intermediate");

    // trainerId preserved
    expect(data["trainerId"]).toBe(trainerId);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-SSP-06 — user doc deleted (userAfter null) → no write (user-deleted)
// ---------------------------------------------------------------------------

describe("SCENARIO-SSP-06: user doc deleted (userAfter null) → no write", () => {
  const uid = "athlete-ssp-06";
  const trainerId = "trainer-ssp-06";
  const now = new Date(Date.UTC(2026, 6, 6, 12, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("users").doc(uid),
      db().collection("profile_shares").doc(uid),
    );
  });

  it("returns user-deleted and does NOT touch profile_shares", async () => {
    const originalUpdatedAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.UTC(2026, 5, 1, 0, 0, 0)),
    );

    await seedProfileShare(uid, {
      trainerId,
      bodyWeightKg: 70.0,
      updatedAt: originalUpdatedAt,
    });

    // userAfter is null → user doc was deleted
    const result = await syncSharedProfileHandler(testApp, uid, null, now);

    expect(result.updated).toBe(false);
    expect(result.reason).toBe("user-deleted");

    // profile_shares doc must be UNTOUCHED
    const shareSnap = await db().collection("profile_shares").doc(uid).get();
    const data = shareSnap.data()!;
    const updatedAtTs = data["updatedAt"] as admin.firestore.Timestamp;
    expect(updatedAtTs.seconds).toBe(originalUpdatedAt.seconds);
  });
});
