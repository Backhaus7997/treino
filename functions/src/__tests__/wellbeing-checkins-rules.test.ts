/**
 * Rules tests for `users/{uid}/wellbeingCheckIns/{checkInId}` — the athlete's
 * self-reported wellbeing log (#643).
 *
 * WHY THIS FILE EXISTS
 * This is the most sensitive data the app stores: self-reported health — how
 * the athlete felt, whether something hurt, and where. docs/security.md §1.8
 * asks every new `match` block to arrive with its own negatives, and a brand
 * new subcollection starts at zero cells.
 *
 * WHAT IS ASSERTED
 *   1. the owner reads and writes their own log (the positive control — a
 *      suite where everything is denied proves nothing about the rule);
 *   2. a stranger cannot read it, write it, or list the collection;
 *   3. an UNAUTHENTICATED client cannot read it;
 *   4. — the one that matters most — a trainer holding BOTH consent grants
 *      (`session_shares` + `profile_shares`) still cannot read it. Those
 *      grants open the training history and the profile snapshot; #643 puts
 *      wellbeing explicitly outside them. Without this assertion, someone
 *      widening the block to "owner OR shared trainer" would find a green
 *      suite. This is the regression that the rest of the file cannot catch.
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` actually loaded
 * and enforced (client-authenticated contexts), NOT the Admin SDK.
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

// Distinct projectId: the rules suites share one emulator and clearFirestore()
// in afterEach; a distinct projectId keeps this suite's data out of the others'
// namespace so parallel Jest workers don't wipe each other.
const PROJECT_ID = "treino-rules-test-wellbeing";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_USERS = "users";
const SUB_WELLBEING = "wellbeingCheckIns";
const COL_SESSION_SHARES = "session_shares";
const COL_PROFILE_SHARES = "profile_shares";

const OWNER = "athlete-wellbeing";
const STRANGER = "stranger-wellbeing";
const TRAINER = "trainer-wellbeing";

// '{date}_{millisUTC}' — the id scheme that replaced the bare date, so a
// second workout on the same day stops overwriting the first one's record.
const CHECK_IN_ID = "2026-08-24_1787529600000";

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

function ctxDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function checkInDoc(db: ReturnType<typeof ctxDb>, uid: string, id = CHECK_IN_ID) {
  return db.collection(COL_USERS).doc(uid).collection(SUB_WELLBEING).doc(id);
}

/** The real client payload — feeling + pain + zones in the MuscleGroup vocabulary. */
function payload(): Record<string, unknown> {
  return {
    date: "2026-08-24",
    feeling: "bad",
    hasPain: true,
    painAreas: ["back", "quads"],
    note: "molestia lumbar al levantarme",
    recordedAt: new Date(),
    sessionId: null,
  };
}

/** Writes a check-in bypassing rules, so read tests do not depend on write tests. */
async function seedCheckIn(uid: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_USERS)
      .doc(uid)
      .collection(SUB_WELLBEING)
      .doc(CHECK_IN_ID)
      .set(payload());
  });
}

/** Grants the trainer BOTH consent capabilities over the owner. */
async function seedBothGrants(): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db
      .collection(COL_SESSION_SHARES)
      .doc(OWNER)
      .set({ trainerId: TRAINER, updatedAt: new Date() });
    await db
      .collection(COL_PROFILE_SHARES)
      .doc(OWNER)
      .set({ trainerId: TRAINER, updatedAt: new Date() });
  });
}

describe("users/{uid}/wellbeingCheckIns — owner", () => {
  it("allows the owner to create their own check-in", async () => {
    await assertSucceeds(checkInDoc(ctxDb(OWNER), OWNER).set(payload()));
  });

  it("allows the owner to read their own check-in", async () => {
    await seedCheckIn(OWNER);
    await assertSucceeds(checkInDoc(ctxDb(OWNER), OWNER).get());
  });

  it("allows the owner to list their own check-ins (the trend range query)", async () => {
    await seedCheckIn(OWNER);
    await assertSucceeds(
      ctxDb(OWNER)
        .collection(COL_USERS)
        .doc(OWNER)
        .collection(SUB_WELLBEING)
        .where("date", ">=", "2026-08-01")
        .where("date", "<=", "2026-08-31")
        .get(),
    );
  });

  it("allows the owner to edit an existing check-in in place", async () => {
    await seedCheckIn(OWNER);
    await assertSucceeds(
      checkInDoc(ctxDb(OWNER), OWNER).set({ ...payload(), feeling: "good" }),
    );
  });
});

describe("users/{uid}/wellbeingCheckIns — everyone else", () => {
  it("DENIES a stranger reading another user's check-in", async () => {
    await seedCheckIn(OWNER);
    await assertFails(checkInDoc(ctxDb(STRANGER), OWNER).get());
  });

  it("DENIES a stranger listing another user's check-ins", async () => {
    await seedCheckIn(OWNER);
    await assertFails(
      ctxDb(STRANGER)
        .collection(COL_USERS)
        .doc(OWNER)
        .collection(SUB_WELLBEING)
        .get(),
    );
  });

  it("DENIES a stranger writing into another user's check-ins", async () => {
    await assertFails(checkInDoc(ctxDb(STRANGER), OWNER).set(payload()));
  });

  it("DENIES a stranger deleting another user's check-in", async () => {
    await seedCheckIn(OWNER);
    await assertFails(checkInDoc(ctxDb(STRANGER), OWNER).delete());
  });

  it("DENIES an unauthenticated client reading a check-in", async () => {
    await seedCheckIn(OWNER);
    await assertFails(checkInDoc(anonDb(), OWNER).get());
  });
});

describe("users/{uid}/wellbeingCheckIns — consent grants do NOT reach it", () => {
  // The point of the whole file. `session_shares` + `profile_shares` are the
  // capabilities that open the athlete's training history and profile
  // snapshot to one trainer. #643 keeps wellbeing outside them on purpose:
  // sharing health data needs its own explicit opt-in, not a side effect of
  // the training-history toggle.
  it("DENIES a trainer holding BOTH grants from reading the check-in", async () => {
    await seedCheckIn(OWNER);
    await seedBothGrants();
    await assertFails(checkInDoc(ctxDb(TRAINER), OWNER).get());
  });

  it("DENIES a trainer holding BOTH grants from listing the check-ins", async () => {
    await seedCheckIn(OWNER);
    await seedBothGrants();
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(OWNER)
        .collection(SUB_WELLBEING)
        .get(),
    );
  });

  it("DENIES a trainer holding BOTH grants from writing a check-in", async () => {
    await seedBothGrants();
    await assertFails(checkInDoc(ctxDb(TRAINER), OWNER).set(payload()));
  });

  it("proves the grants are real: the same trainer DOES read the athlete's sessions", async () => {
    // Without this control the four denials above would also pass if the
    // grants had simply failed to seed.
    await seedBothGrants();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection(COL_USERS)
        .doc(OWNER)
        .collection("sessions")
        .doc("session-wellbeing-1")
        .set({ id: "session-wellbeing-1", uid: OWNER, startedAt: new Date() });
    });
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(OWNER)
        .collection("sessions")
        .doc("session-wellbeing-1")
        .get(),
    );
  });
});
