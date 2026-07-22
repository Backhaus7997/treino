/**
 * Regression tests for QA-FEED-001 — `posts/{postId}` READ rule must enforce
 * post privacy SERVER-SIDE (was client-side only, REQ-PFM-009).
 *
 * Before the fix, `allow read` on posts was effectively "any authenticated
 * user", so anyone could pull every `friends`/`gym` post straight from the SDK,
 * bypassing the client-side filter on the profile "ACTIVIDAD" tab. The rule now
 * allows a read only when the post is public, is the caller's own, is a
 * `friends` post authored by an ACCEPTED friend, or is a `gym` post whose
 * `authorGymId` matches the caller's own gym.
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` actually loaded and
 * enforced (client-authenticated contexts), NOT the Admin SDK. Seed data is
 * written with rules disabled so we can plant arbitrary authors/gyms/friendships.
 *
 * Run against the Firestore emulator (Java 21 required):
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
import { setLogLevel } from "firebase/firestore";

// Distinct projectId so this suite runs in its own emulator namespace and its
// clearFirestore() never wipes another parallel rules suite's seed data.
const PROJECT_ID = "treino-rules-test-feed001";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AUTHOR = "author-uid";
const FRIEND = "friend-uid"; // accepted friend of AUTHOR
const PENDING = "pending-uid"; // friendship with AUTHOR is only pending
const STRANGER = "stranger-uid"; // no relationship with AUTHOR
const SAME_GYM = "same-gym-uid"; // shares AUTHOR's gym
const OTHER_GYM = "other-gym-uid"; // in a different gym
const GYM_A = "gym-A";
const GYM_B = "gym-B";

/** friendships/{id} format the rule reconstructs: sorted uid pair joined by _. */
function friendshipId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

// Seed the shared graph before each test (users, friendships, posts) with rules
// disabled, then clear afterwards. Every test reads against the same fixtures.
beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Users with gyms (the rule reads users/{caller}.gymId for the gym tier).
    await db.collection("users").doc(AUTHOR).set({ uid: AUTHOR, gymId: GYM_A });
    await db.collection("users").doc(SAME_GYM).set({ uid: SAME_GYM, gymId: GYM_A });
    await db.collection("users").doc(OTHER_GYM).set({ uid: OTHER_GYM, gymId: GYM_B });
    // FRIEND/PENDING/STRANGER intentionally have no gym doc.

    // Friendships: FRIEND accepted, PENDING pending. STRANGER has none.
    await db
      .collection("friendships")
      .doc(friendshipId(AUTHOR, FRIEND))
      .set({ status: "accepted", members: [AUTHOR, FRIEND] });
    await db
      .collection("friendships")
      .doc(friendshipId(AUTHOR, PENDING))
      .set({ status: "pending", members: [AUTHOR, PENDING] });

    // Posts by AUTHOR, one per privacy tier.
    await db
      .collection("posts")
      .doc("p-public")
      .set({ authorUid: AUTHOR, privacy: "public", text: "pub" });
    await db
      .collection("posts")
      .doc("p-friends")
      .set({ authorUid: AUTHOR, privacy: "friends", text: "fr" });
    await db
      .collection("posts")
      .doc("p-gym")
      .set({ authorUid: AUTHOR, privacy: "gym", authorGymId: GYM_A, text: "gym" });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function readPost(uid: string | null, postId: string) {
  const ctx =
    uid === null
      ? testEnv.unauthenticatedContext()
      : testEnv.authenticatedContext(uid);
  return ctx.firestore().collection("posts").doc(postId).get();
}

describe("posts/{postId} read — QA-FEED-001 privacy enforcement", () => {
  it("DENIES an unauthenticated read of a public post", async () => {
    await assertFails(readPost(null, "p-public"));
  });

  it("allows any authenticated user to read a public post", async () => {
    await assertSucceeds(readPost(STRANGER, "p-public"));
  });

  it("lets the author read their own friends post", async () => {
    await assertSucceeds(readPost(AUTHOR, "p-friends"));
  });

  it("lets the author read their own gym post", async () => {
    await assertSucceeds(readPost(AUTHOR, "p-gym"));
  });

  it("DENIES a stranger reading a friends post (the exploit)", async () => {
    await assertFails(readPost(STRANGER, "p-friends"));
  });

  it("DENIES a pending-friend reading a friends post", async () => {
    await assertFails(readPost(PENDING, "p-friends"));
  });

  it("allows an accepted friend to read a friends post", async () => {
    await assertSucceeds(readPost(FRIEND, "p-friends"));
  });

  it("allows a same-gym viewer to read a gym post", async () => {
    await assertSucceeds(readPost(SAME_GYM, "p-gym"));
  });

  it("DENIES an other-gym viewer reading a gym post", async () => {
    await assertFails(readPost(OTHER_GYM, "p-gym"));
  });

  it("DENIES a viewer with no gym reading a gym post", async () => {
    await assertFails(readPost(STRANGER, "p-gym"));
  });

  it("DENIES an accepted friend (no shared gym) reading a gym post", async () => {
    // The tiers are independent: being an accepted friend grants friends posts,
    // not gym posts. FRIEND has no gym doc, so the gym gate still fails.
    await assertFails(readPost(FRIEND, "p-gym"));
  });
});
