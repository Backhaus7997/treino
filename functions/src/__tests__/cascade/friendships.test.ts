/**
 * Integration tests for the friendships cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-538 — Friendship documents are swept (REQ-ACCDEL-CF-005)
 *   SCENARIO-539 — No friendships is a no-op (REQ-ACCDEL-CF-005)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "friendships-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { sweepFriendships } from "../../cascade/friendships";

const db = () => admin.firestore(testApp);

async function seedFriendships(uid: string, count: number): Promise<string[]> {
  const batch = db().batch();
  const ids: string[] = [];
  for (let i = 0; i < count; i++) {
    const otherId = `other-user-${i}`;
    const docId = `friendship-${uid}-${i}`;
    ids.push(docId);
    batch.set(db().collection("friendships").doc(docId), {
      members: [uid, otherId],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return ids;
}

async function cleanupFriendships(docIds: string[]): Promise<void> {
  const batch = db().batch();
  for (const id of docIds) {
    batch.delete(db().collection("friendships").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("SCENARIO-538: friendship documents are swept", () => {
  const uid = "friendships-cascade-538";
  let docIds: string[] = [];

  beforeEach(async () => {
    docIds = await seedFriendships(uid, 3);
  });
  afterEach(() => cleanupFriendships(docIds));

  it("SCENARIO-538: deletes all 3 friendship docs where uid is a member", async () => {
    await sweepFriendships(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("friendships").doc(id).get();
      expect(snap.exists).toBe(false);
    }
  });

  it("SCENARIO-538: does not delete friendship docs for other users", async () => {
    const otherUid = "other-user-not-deleted";
    const otherId = "friendship-other-only";
    await db().collection("friendships").doc(otherId).set({
      members: ["user-a", "user-b"],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await sweepFriendships(testApp, uid);

    const snap = await db().collection("friendships").doc(otherId).get();
    expect(snap.exists).toBe(true);
    await db().collection("friendships").doc(otherId).delete();
    void otherUid;
  });
});

describe("SCENARIO-539: no friendships is a no-op", () => {
  const uid = "friendships-cascade-539";

  it("SCENARIO-539: no error thrown when user has zero friendship docs", async () => {
    await expect(sweepFriendships(testApp, uid)).resolves.not.toThrow();
  });
});
