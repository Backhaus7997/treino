/**
 * Integration tests for the posts cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-540 — Post author is anonymized (REQ-ACCDEL-CF-006)
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
import { anonymizePosts } from "../../cascade/posts";

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

describe("SCENARIO-540: post author is anonymized", () => {
  const uid = "posts-cascade-540";
  let docIds: string[] = [];

  beforeEach(async () => {
    docIds = await seedPosts(uid, 2);
  });
  afterEach(() => cleanupPosts(docIds));

  it("SCENARIO-540: authorDisplayName set to 'Usuario eliminado' on all user posts", async () => {
    await anonymizePosts(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("posts").doc(id).get();
      expect(snap.data()?.authorDisplayName).toBe("Usuario eliminado");
    }
  });

  it("SCENARIO-540: authorAvatarUrl set to null on all user posts", async () => {
    await anonymizePosts(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("posts").doc(id).get();
      expect(snap.data()?.authorAvatarUrl).toBeNull();
    }
  });

  it("SCENARIO-540: authorUid remains unchanged (referential integrity per ADR-ACCDEL-004)", async () => {
    await anonymizePosts(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("posts").doc(id).get();
      expect(snap.data()?.authorUid).toBe(uid);
    }
  });

  it("SCENARIO-540: posts from other authors are not modified", async () => {
    const otherUid = "other-author-not-anonymized";
    const otherId = "post-other-author";
    await db().collection("posts").doc(otherId).set({
      authorUid: otherUid,
      authorDisplayName: "Other Author",
      authorAvatarUrl: "https://example.com/other.jpg",
    });

    await anonymizePosts(testApp, uid);

    const snap = await db().collection("posts").doc(otherId).get();
    expect(snap.data()?.authorDisplayName).toBe("Other Author");
    await db().collection("posts").doc(otherId).delete();
  });
});

describe("SCENARIO-541: no posts authored is a no-op", () => {
  const uid = "posts-cascade-541";

  it("SCENARIO-541: no error thrown when user has zero posts", async () => {
    await expect(anonymizePosts(testApp, uid)).resolves.not.toThrow();
  });
});
