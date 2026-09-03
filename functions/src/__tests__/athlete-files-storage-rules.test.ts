/**
 * Storage rules tests for `athleteFiles/{pairId}/{file=**}` — the binaries
 * behind the Coach Hub «Archivos» tab: PDFs and images the PF uploads ABOUT an
 * athlete, which the athlete never sees.
 *
 * WHY THIS FILE EXISTS
 * The rules-coverage matrix (docs/security.md, #680 Slice A) found this block
 * at **zero** tests — while its Firestore twin `athlete_files` was also at
 * zero. That pair is the worst combination in the matrix: the Firestore doc
 * holds a tokenized `downloadUrl` and the Storage object holds the actual
 * bytes, so a hole on EITHER side hands over the same PDF. The
 * `coach-private-collections-rules.test.ts` suite covers the metadata side;
 * this one covers the bytes.
 *
 * The gate is the path prefix: `pairId` is `{trainerId}_{athleteId}`, and the
 * rule requires `pairId.split('_')[0] == request.auth.uid`. That makes the
 * folder name itself the authorization token, and it is fully predictable —
 * both uids are enumerable through the world-readable `userPublicProfiles`.
 * So "the athlete cannot read their own dossier" is a claim that has to be
 * tested, not assumed from the shape of the string.
 *
 * The 10 MB bound is NOT exercised here — pushing a 10 MB body through the
 * emulator on every CI run is pure drag, and it is the same
 * `request.resource.size` idiom already covered by the other storage blocks.
 * The content-type allowlist IS exercised, because that one is bespoke to
 * this block (PDF + images, videos deliberately rejected for MVP).
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

const PROJECT_ID = "treino-rules-test-athlete-files";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");

const TRAINER = "trainerfiles";
const OTHER_TRAINER = "othertrainerfiles";
const ATHLETE = "athletefiles";

const PAIR = `${TRAINER}_${ATHLETE}`;
const FILE_PATH = `athleteFiles/${PAIR}/1700000000000.pdf`;

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
  // Seed the trainer's file with rules disabled so read/list/delete tests have
  // a real target — a denial against a missing object would pass for the wrong
  // reason.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadString(ref(ctx.storage(), FILE_PATH), "seed-bytes", "raw", {
      contentType: "application/pdf",
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

describe("athleteFiles/{pairId}/** — download", () => {
  it("allows the owning trainer to download their own file", async () => {
    await assertSucceeds(getBytes(ref(storageAs(TRAINER), FILE_PATH)));
  });

  it("DENIES the subject athlete downloading the file about them", async () => {
    // The headline privacy claim of the block. The athlete owns the second
    // half of the pairId, never the first.
    await assertFails(getBytes(ref(storageAs(ATHLETE), FILE_PATH)));
  });

  it("DENIES another trainer downloading it by guessing the pair", async () => {
    await assertFails(getBytes(ref(storageAs(OTHER_TRAINER), FILE_PATH)));
  });

  it("DENIES an unauthenticated download", async () => {
    await assertFails(getBytes(ref(storageAs(null), FILE_PATH)));
  });
});

describe("athleteFiles/{pairId}/** — folder listing", () => {
  it("allows the owning trainer to list their own pair folder", async () => {
    await assertSucceeds(listAll(ref(storageAs(TRAINER), `athleteFiles/${PAIR}`)));
  });

  it("DENIES the subject athlete enumerating the folder", async () => {
    await assertFails(listAll(ref(storageAs(ATHLETE), `athleteFiles/${PAIR}`)));
  });

  it("DENIES another trainer enumerating the folder", async () => {
    await assertFails(
      listAll(ref(storageAs(OTHER_TRAINER), `athleteFiles/${PAIR}`)),
    );
  });
});

describe("athleteFiles/{pairId}/** — upload", () => {
  const NEW_PDF = `athleteFiles/${PAIR}/1700000000001.pdf`;
  const NEW_IMG = `athleteFiles/${PAIR}/1700000000002.jpg`;

  it("allows the owning trainer to upload a PDF", async () => {
    await assertSucceeds(
      uploadString(ref(storageAs(TRAINER), NEW_PDF), "bytes", "raw", {
        contentType: "application/pdf",
      }),
    );
  });

  it("allows the owning trainer to upload an image", async () => {
    await assertSucceeds(
      uploadString(ref(storageAs(TRAINER), NEW_IMG), "bytes", "raw", {
        contentType: "image/jpeg",
      }),
    );
  });

  it("DENIES the athlete uploading into the pair folder", async () => {
    await assertFails(
      uploadString(ref(storageAs(ATHLETE), NEW_PDF), "bytes", "raw", {
        contentType: "application/pdf",
      }),
    );
  });

  it("DENIES another trainer planting a file in the victim PF's folder", async () => {
    await assertFails(
      uploadString(ref(storageAs(OTHER_TRAINER), NEW_PDF), "bytes", "raw", {
        contentType: "application/pdf",
      }),
    );
  });

  it("DENIES a video — the allowlist is PDF + images for MVP", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(TRAINER), `athleteFiles/${PAIR}/clip.mp4`),
        "bytes",
        "raw",
        { contentType: "video/mp4" },
      ),
    );
  });

  it("DENIES an arbitrary binary content type", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(TRAINER), `athleteFiles/${PAIR}/payload.zip`),
        "bytes",
        "raw",
        { contentType: "application/zip" },
      ),
    );
  });
});

describe("athleteFiles/{pairId}/** — delete", () => {
  it("allows the owning trainer to delete their own file", async () => {
    await assertSucceeds(deleteObject(ref(storageAs(TRAINER), FILE_PATH)));
  });

  it("DENIES the subject athlete deleting it", async () => {
    await assertFails(deleteObject(ref(storageAs(ATHLETE), FILE_PATH)));
  });

  it("DENIES another trainer deleting it", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER_TRAINER), FILE_PATH)));
  });
});
