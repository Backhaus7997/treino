/**
 * Storage rules tests for the `postPhotos/{userId}/{fileName}` block
 * (share-composer PR1) — first storage-RULES suite in the repo (the cascade
 * suite uses the Admin SDK, which bypasses rules entirely).
 *
 * The block mirrors the avatars/customExerciseVideos style: only the owner
 * writes/deletes under their folder, images only, any authenticated user can
 * `get` (post visibility is governed by firestore.rules over posts/ — the
 * tokenized download URL only travels inside the post doc), and `list` is
 * unconditionally closed so nobody can enumerate another user's photos.
 *
 * The 15 MB size bound is NOT exercised here — pushing a 15 MB body through
 * the emulator per run is pure CI drag, and the bound is the same
 * `request.resource.size` idiom already shipping in the four other blocks.
 *
 * Run against the emulators (Java 21 required):
 *   npm --prefix functions run test:rules:emulator
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteObject,
  getBytes,
  listAll,
  ref,
  uploadString,
} from "firebase/storage";

const PROJECT_ID = "treino-rules-test-post-photos";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");

const AUTHOR = "author-uid";
const OTHER = "other-uid";
const PHOTO_PATH = `postPhotos/${AUTHOR}/p1.jpg`;

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  // Seed AUTHOR's photo with rules disabled so read/delete tests have a target.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadString(ref(ctx.storage(), PHOTO_PATH), "seed-bytes", "raw", {
      contentType: "image/jpeg",
    });
  });
});

afterEach(async () => {
  await testEnv.clearStorage();
});

function storageAs(uid: string | null) {
  return uid === null
    ? testEnv.unauthenticatedContext().storage()
    : testEnv.authenticatedContext(uid).storage();
}

describe("postPhotos/{userId}/{fileName} — storage rules", () => {
  it("allows the owner to upload an image under their folder", async () => {
    await assertSucceeds(
      uploadString(
        ref(storageAs(AUTHOR), `postPhotos/${AUTHOR}/p2.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" }
      )
    );
  });

  it("DENIES uploading into ANOTHER user's folder", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(OTHER), `postPhotos/${AUTHOR}/hijack.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" }
      )
    );
  });

  it("DENIES a non-image contentType even for the owner", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(AUTHOR), `postPhotos/${AUTHOR}/p3.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" }
      )
    );
  });

  it("allows any authenticated user to get a photo", async () => {
    await assertSucceeds(getBytes(ref(storageAs(OTHER), PHOTO_PATH)));
  });

  it("DENIES an unauthenticated get", async () => {
    await assertFails(getBytes(ref(storageAs(null), PHOTO_PATH)));
  });

  it("DENIES listing a user's photo folder — even one's own", async () => {
    await assertFails(listAll(ref(storageAs(OTHER), `postPhotos/${AUTHOR}`)));
    await assertFails(listAll(ref(storageAs(AUTHOR), `postPhotos/${AUTHOR}`)));
  });

  it("allows the owner to delete their photo", async () => {
    await assertSucceeds(deleteObject(ref(storageAs(AUTHOR), PHOTO_PATH)));
  });

  it("DENIES a non-owner delete", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER), PHOTO_PATH)));
  });
});
