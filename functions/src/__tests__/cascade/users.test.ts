/**
 * Unit/integration tests for the users cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-536 — Main profile docs deleted on success (REQ-ACCDEL-CF-004)
 *   SCENARIO-537 — trainerPublicProfiles deletion is no-op when absent (REQ-ACCDEL-CF-004)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "users-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { deleteUserDocs } from "../../cascade/users";

const db = () => admin.firestore(testApp);

async function seed(uid: string): Promise<void> {
  const batch = db().batch();
  batch.set(db().collection("users").doc(uid), { uid, role: "athlete" });
  batch.set(db().collection("userPublicProfiles").doc(uid), { uid, displayName: "Test User" });
  // Seed 3 sub-collection docs (sessions)
  for (let i = 0; i < 3; i++) {
    batch.set(db().collection("users").doc(uid).collection("sessions").doc(`session-${i}`), { i });
  }
  await batch.commit();
}

async function cleanup(uid: string): Promise<void> {
  await db().collection("audit_log").doc(uid).delete().catch(() => undefined);
  await db().collection("userPublicProfiles").doc(uid).delete().catch(() => undefined);
  await db().collection("trainerPublicProfiles").doc(uid).delete().catch(() => undefined);
  // recursiveDelete covers users + sub-collections
  await db().recursiveDelete(db().collection("users").doc(uid)).catch(() => undefined);
}

describe("SCENARIO-536: main profile docs deleted on success", () => {
  const uid = "users-cascade-536";

  beforeEach(() => seed(uid));
  afterEach(() => cleanup(uid));

  it("SCENARIO-536: users/{uid} is deleted (recursively including sessions)", async () => {
    await deleteUserDocs(testApp, uid);

    const userSnap = await db().collection("users").doc(uid).get();
    expect(userSnap.exists).toBe(false);

    const sessionSnap = await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc("session-0")
      .get();
    expect(sessionSnap.exists).toBe(false);
  });

  it("SCENARIO-536: userPublicProfiles/{uid} is deleted", async () => {
    await deleteUserDocs(testApp, uid);

    const snap = await db().collection("userPublicProfiles").doc(uid).get();
    expect(snap.exists).toBe(false);
  });
});

describe("SCENARIO-537: trainerPublicProfiles deletion is no-op when absent", () => {
  const uid = "users-cascade-537";

  beforeEach(() => seed(uid));
  afterEach(() => cleanup(uid));

  it("SCENARIO-537: no error when trainerPublicProfiles/{uid} does not exist", async () => {
    // Ensure it does NOT exist
    await db().collection("trainerPublicProfiles").doc(uid).delete().catch(() => undefined);

    await expect(deleteUserDocs(testApp, uid)).resolves.not.toThrow();
  });

  it("SCENARIO-537: trainerPublicProfiles/{uid} is deleted when it exists", async () => {
    await db()
      .collection("trainerPublicProfiles")
      .doc(uid)
      .set({ uid, displayName: "Trainer" });

    await deleteUserDocs(testApp, uid);

    const snap = await db().collection("trainerPublicProfiles").doc(uid).get();
    expect(snap.exists).toBe(false);
  });
});
