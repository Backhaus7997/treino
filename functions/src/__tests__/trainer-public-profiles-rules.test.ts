/**
 * Rules tests for the trainerPublicProfiles `athleteCount` pin (#388).
 *
 * `athleteCount` is a derived aggregate (count of active trainer_links)
 * written exclusively by the `linkAggregate` Cloud Function via the Admin
 * SDK. The rules extend the AD-3 CF-write-only idiom already guarding
 * `averageRating`/`reviewCount`: a client write may only (a) omit the field,
 * or (b) on update, re-assert the exact currently-stored value. Anything
 * else — including seeding a value at create time — is denied, so a trainer
 * cannot forge their own student count on the discovery sales surface.
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` loaded and
 * enforced (client-authenticated contexts), NOT the Admin SDK.
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

// Isolated projectId: the rules suites share one emulator and clearFirestore()
// in afterEach; a distinct projectId keeps this suite's data out of the others'
// namespace so parallel Jest workers don't wipe each other.
const PROJECT_ID = "treino-rules-test-388";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_PROFILES = "trainerPublicProfiles";

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

const TRAINER = "trainer-388";

function ctxDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

/** Seeds a profile doc bypassing rules (as the linkAggregate CF would). */
async function seedProfile(data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_PROFILES)
      .doc(TRAINER)
      .set({ uid: TRAINER, ...data });
  });
}

describe("trainerPublicProfiles create — athleteCount pin (#388)", () => {
  it("ALLOWS the owner creating their doc without athleteCount", async () => {
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .set({ uid: TRAINER, trainerBio: "Bio inicial del PF." }),
    );
  });

  it("DENIES the owner seeding athleteCount at create time", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .set({ uid: TRAINER, athleteCount: 500 }),
    );
  });
});

describe("trainerPublicProfiles update — athleteCount pin (#388)", () => {
  it("ALLOWS a normal owner profile update that omits athleteCount", async () => {
    await seedProfile({ trainerBio: "Bio vieja", athleteCount: 2 });

    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .set(
          { trainerBio: "Bio nueva", trainerExperienceYears: 5 },
          { merge: true },
        ),
    );
  });

  it("DENIES the owner forging athleteCount on update", async () => {
    await seedProfile({ athleteCount: 2 });

    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .update({ athleteCount: 500 }),
    );
  });

  it("DENIES the owner seeding athleteCount when the field is absent", async () => {
    await seedProfile({ trainerBio: "Sin aggregate todavía" });

    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .update({ athleteCount: 3 }),
    );
  });

  it("ALLOWS re-asserting the exact stored athleteCount value", async () => {
    await seedProfile({ athleteCount: 2 });

    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .update({ trainerBio: "Bio nueva", athleteCount: 2 }),
    );
  });

  it("DENIES a non-owner touching the doc at all", async () => {
    await seedProfile({ athleteCount: 2 });

    await assertFails(
      ctxDb("otro-user")
        .collection(COL_PROFILES)
        .doc(TRAINER)
        .update({ trainerBio: "vandalismo" }),
    );
  });
});
