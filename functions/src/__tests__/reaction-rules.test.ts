/**
 * Rules tests for `posts/{postId}/reactions/{reactorUid}` and the
 * Cloud-Function-only `posts/{postId}.reactionCounts` field.
 *
 * Requires the Firestore emulator; the implementation sandbox cannot execute
 * this suite because it cannot open sockets.
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

const PROJECT_ID = "treino-rules-test-reactions";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AUTHOR = "reaction-author";
const REACTOR = "reaction-owner";
const OTHER = "reaction-other";
const POST_ID = "reaction-post";

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

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("posts").doc(POST_ID).set({
      authorUid: AUTHOR,
      privacy: "public",
      text: "Post with reactions",
    });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function reaction(uid: string, reactorUid: string) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection("posts")
    .doc(POST_ID)
    .collection("reactions")
    .doc(reactorUid);
}

describe("post reactions rules", () => {
  it("denies creating a reaction under another user's uid", async () => {
    await assertFails(
      reaction(REACTOR, OTHER).set({
        type: "strong",
        createdAt: new Date(),
      }),
    );
  });

  it("rejects an unsupported reaction type", async () => {
    await assertFails(
      reaction(REACTOR, REACTOR).set({
        type: "heart",
        createdAt: new Date(),
      }),
    );
  });

  it("denies a client write to reactionCounts on the parent post", async () => {
    const post = testEnv
      .authenticatedContext(AUTHOR)
      .firestore()
      .collection("posts")
      .doc(POST_ID);

    await assertFails(post.update({ reactionCounts: { fire: 999 } }));
  });

  it("lets the owner delete their own reaction", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("posts")
        .doc(POST_ID)
        .collection("reactions")
        .doc(REACTOR)
        .set({ type: "clap", createdAt: new Date() });
    });

    await assertSucceeds(reaction(REACTOR, REACTOR).delete());
  });

  it("denies deleting another user's reaction", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("posts")
        .doc(POST_ID)
        .collection("reactions")
        .doc(OTHER)
        .set({ type: "fire", createdAt: new Date() });
    });

    await assertFails(reaction(REACTOR, OTHER).delete());
  });
});
