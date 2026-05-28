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
import { deleteAvatar } from "../../cascade/storage";

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
