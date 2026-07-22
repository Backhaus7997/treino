/**
 * Regression tests for QA-CHAT-004 — a chat may only be created between two
 * users with a real relationship: an ACCEPTED friendship, or an active
 * trainer_link named by a verified `linkId`. Before the fix the chats create
 * rule only validated the doc shape, so any authenticated user could open a
 * chat with (and message) anyone.
 *
 * Uses @firebase/rules-unit-testing with firestore.rules loaded and enforced.
 * Run against the Firestore emulator (Java 21):
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

// Isolated projectId — the rules suites share one emulator + clearFirestore().
const PROJECT_ID = "treino-rules-test-chat004";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const ATHLETE = "aaa-athlete";
const TRAINER = "zzz-trainer";
const STRANGER = "mmm-stranger";
// chatId is the two members sorted and joined with "_".
const sorted = (a: string, b: string) => (a < b ? [a, b] : [b, a]);
const chatIdOf = (a: string, b: string) => sorted(a, b).join("_");

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

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedFriendship(a: string, b: string, status: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("friendships")
      .doc(chatIdOf(a, b))
      .set({ members: sorted(a, b), status, requesterId: a });
  });
}

async function seedLink(
  linkId: string,
  trainerId: string,
  athleteId: string,
  status: string
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("trainer_links")
      .doc(linkId)
      .set({ trainerId, athleteId, status, requestedAt: 1 });
  });
}

function chatDoc(a: string, b: string, extra: Record<string, unknown> = {}) {
  return {
    chatId: chatIdOf(a, b),
    members: sorted(a, b),
    createdAt: 1,
    ...extra,
  };
}

/** A create attempt authenticated as [self]. */
function createChat(self: string, a: string, b: string, extra = {}) {
  return testEnv
    .authenticatedContext(self)
    .firestore()
    .collection("chats")
    .doc(chatIdOf(a, b))
    .set(chatDoc(a, b, extra));
}

describe("chats create — QA-CHAT-004 relationship gate", () => {
  it("allows a chat between ACCEPTED friends (no linkId)", async () => {
    await seedFriendship(ATHLETE, STRANGER, "accepted");
    await assertSucceeds(createChat(ATHLETE, ATHLETE, STRANGER));
  });

  it("DENIES a chat when the friendship is only pending", async () => {
    await seedFriendship(ATHLETE, STRANGER, "pending");
    await assertFails(createChat(ATHLETE, ATHLETE, STRANGER));
  });

  it("DENIES a chat between strangers with no relationship", async () => {
    await assertFails(createChat(ATHLETE, ATHLETE, STRANGER));
  });

  it("allows a coach↔athlete chat backed by an active trainer_link", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertSucceeds(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" })
    );
    // ...and the trainer side can open it too.
    await testEnv.clearFirestore();
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertSucceeds(
      createChat(TRAINER, ATHLETE, TRAINER, { linkId: "link-1" })
    );
  });

  it("DENIES a linkId whose members do not match the chat members", async () => {
    // Active link is trainer↔athlete, but the chat is athlete↔stranger.
    await seedLink("link-1", TRAINER, ATHLETE, "active");
    await assertFails(
      createChat(ATHLETE, ATHLETE, STRANGER, { linkId: "link-1" })
    );
  });

  it("DENIES a linkId pointing to a non-active (pending) link", async () => {
    await seedLink("link-1", TRAINER, ATHLETE, "pending");
    await assertFails(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "link-1" })
    );
  });

  it("DENIES a non-existent linkId", async () => {
    await assertFails(
      createChat(ATHLETE, ATHLETE, TRAINER, { linkId: "does-not-exist" })
    );
  });
});
