/**
 * Integration tests for the posts cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-540 — Post author's posts are deleted (REQ-ACCDEL-CF-006)
 *   SCENARIO-541 — No posts authored is a no-op (REQ-ACCDEL-CF-006)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "posts-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { deletePosts } from "../../cascade/posts";

const db = () => admin.firestore(testApp);

async function seedPosts(uid: string, count: number): Promise<string[]> {
  const batch = db().batch();
  const ids: string[] = [];
  for (let i = 0; i < count; i++) {
    const docId = `post-${uid}-${i}`;
    ids.push(docId);
    batch.set(db().collection("posts").doc(docId), {
      authorUid: uid,
      authorDisplayName: "Real Name",
      authorAvatarUrl: "https://example.com/avatar.jpg",
      content: `Post content ${i}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return ids;
}

async function cleanupPosts(docIds: string[]): Promise<void> {
  const batch = db().batch();
  for (const id of docIds) {
    batch.delete(db().collection("posts").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("SCENARIO-540: posts authored by uid are deleted", () => {
  const uid = "posts-cascade-540";
  let docIds: string[] = [];

  beforeEach(async () => {
    docIds = await seedPosts(uid, 2);
  });
  afterEach(() => cleanupPosts(docIds));

  it("SCENARIO-540: all posts authored by uid no longer exist", async () => {
    await deletePosts(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("posts").doc(id).get();
      expect(snap.exists).toBe(false);
    }
  });

  it("SCENARIO-540: returns the count of deleted documents", async () => {
    const result = await deletePosts(testApp, uid);
    expect(result.count).toBe(docIds.length);
  });

  it("SCENARIO-540: posts from other authors are not deleted", async () => {
    const otherUid = "other-author-not-deleted";
    const otherId = "post-other-author";
    await db().collection("posts").doc(otherId).set({
      authorUid: otherUid,
      authorDisplayName: "Other Author",
      authorAvatarUrl: "https://example.com/other.jpg",
    });

    await deletePosts(testApp, uid);

    const snap = await db().collection("posts").doc(otherId).get();
    expect(snap.exists).toBe(true);
    expect(snap.data()?.authorDisplayName).toBe("Other Author");
    await db().collection("posts").doc(otherId).delete();
  });

  it("SCENARIO-540: running twice is idempotent (second run deletes nothing)", async () => {
    await deletePosts(testApp, uid);
    const second = await deletePosts(testApp, uid);
    expect(second.count).toBe(0);

    for (const id of docIds) {
      const snap = await db().collection("posts").doc(id).get();
      expect(snap.exists).toBe(false);
    }
  });
});

describe("SCENARIO-541: no posts authored is a no-op", () => {
  const uid = "posts-cascade-541";

  it("SCENARIO-541: no error thrown when user has zero posts", async () => {
    await expect(deletePosts(testApp, uid)).resolves.not.toThrow();
  });

  it("SCENARIO-541: returns count 0 when user has zero posts", async () => {
    const result = await deletePosts(testApp, uid);
    expect(result.count).toBe(0);
  });
});
