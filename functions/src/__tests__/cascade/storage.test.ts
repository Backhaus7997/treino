/**
 * Integration tests for the storage cascade module.
 * Run against Firebase Local Emulator (Storage).
 *
 * SCENARIOS covered:
 *   SCENARIO-545 — Avatar file deleted when it exists (REQ-ACCDEL-CF-010)
 *   SCENARIO-546 — Missing avatar file is a no-op (REQ-ACCDEL-CF-010)
 *
 * NOTE: Admin SDK bypasses Storage security rules (ADR-ACCDEL-013).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "storage-cascade-test"
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { deleteAvatar, deleteAthleteStorage } from "../../cascade/storage";

async function uploadFakeAvatar(uid: string): Promise<void> {
  const bucket = admin.storage(testApp).bucket();
  const file = bucket.file(`avatars/${uid}.jpg`);
  await file.save(Buffer.from("fake-image-data"), { contentType: "image/jpeg" });
}

async function avatarExists(uid: string): Promise<boolean> {
  const bucket = admin.storage(testApp).bucket();
  const file = bucket.file(`avatars/${uid}.jpg`);
  const [exists] = await file.exists();
  return exists;
}

describe("SCENARIO-545: avatar file deleted when it exists", () => {
  const uid = "storage-cascade-545";

  beforeEach(() => uploadFakeAvatar(uid));
  afterEach(async () => {
    const bucket = admin.storage(testApp).bucket();
    await bucket.file(`avatars/${uid}.jpg`).delete().catch(() => undefined);
  });

  it("SCENARIO-545: avatars/{uid}.jpg no longer exists after deleteAvatar", async () => {
    await deleteAvatar(testApp, uid);
    expect(await avatarExists(uid)).toBe(false);
  });
});

describe("SCENARIO-546: missing avatar file is a no-op", () => {
  const uid = "storage-cascade-546";

  it("SCENARIO-546: no error thrown when avatar does not exist", async () => {
    // Ensure file does not exist
    const bucket = admin.storage(testApp).bucket();
    await bucket.file(`avatars/${uid}.jpg`).delete().catch(() => undefined);

    await expect(deleteAvatar(testApp, uid)).resolves.not.toThrow();
  });
});

// QA-CMP-002: avatars can be any image/* extension, not just .jpg.
describe("QA-CMP-002: deleteAvatar removes non-jpg avatars too", () => {
  const uid = "storage-cascade-heic";

  afterEach(async () => {
    const bucket = admin.storage(testApp).bucket();
    await bucket.file(`avatars/${uid}.heic`).delete().catch(() => undefined);
  });

  it("deletes avatars/{uid}.heic", async () => {
    const bucket = admin.storage(testApp).bucket();
    await bucket
      .file(`avatars/${uid}.heic`)
      .save(Buffer.from("fake"), { contentType: "image/heic" });

    const { deleted } = await deleteAvatar(testApp, uid);

    expect(deleted).toBeGreaterThanOrEqual(1);
    const [exists] = await bucket.file(`avatars/${uid}.heic`).exists();
    expect(exists).toBe(false);
  });
});

// QA-CMP-002: the athlete's non-avatar Storage trees.
describe("QA-CMP-002: deleteAthleteStorage removes the athlete's objects", () => {
  const uid = "storage-athlete-cmp";
  const other = "storage-athlete-other";
  const chatId = `${uid}_trainer-x`;

  async function save(path: string): Promise<void> {
    await admin
      .storage(testApp)
      .bucket()
      .file(path)
      .save(Buffer.from("x"), { contentType: "application/octet-stream" });
  }
  async function exists(path: string): Promise<boolean> {
    const [e] = await admin.storage(testApp).bucket().file(path).exists();
    return e;
  }

  afterEach(async () => {
    const bucket = admin.storage(testApp).bucket();
    const [files] = await bucket.getFiles();
    await Promise.all(files.map((f) => f.delete().catch(() => undefined)));
    await db()
      .collection("chats")
      .doc(chatId)
      .delete()
      .catch(() => undefined);
  });

  it("deletes temp/customExerciseVideos/chatMedia/athleteFiles for the uid, keeps others", async () => {
    await db()
      .collection("chats")
      .doc(chatId)
      .set({ chatId, members: [uid, "trainer-x"] });

    await save(`temp/uploads/${uid}/a.jpg`);
    await save(`customExerciseVideos/${uid}/v.mp4`);
    await save(`chatMedia/${chatId}/${uid}/img.jpg`);
    await save(`athleteFiles/trainer-x_${uid}/plan.pdf`);
    // Control — another athlete's object must survive.
    await save(`temp/uploads/${other}/keep.jpg`);

    await deleteAthleteStorage(testApp, uid);

    expect(await exists(`temp/uploads/${uid}/a.jpg`)).toBe(false);
    expect(await exists(`customExerciseVideos/${uid}/v.mp4`)).toBe(false);
    expect(await exists(`chatMedia/${chatId}/${uid}/img.jpg`)).toBe(false);
    expect(await exists(`athleteFiles/trainer-x_${uid}/plan.pdf`)).toBe(false);
    expect(await exists(`temp/uploads/${other}/keep.jpg`)).toBe(true);
  });
});

const db = () => admin.firestore(testApp);
