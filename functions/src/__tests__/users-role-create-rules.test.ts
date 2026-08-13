/**
 * Regression tests for QA-SEC-001 — `users/{uid}` create rule must NOT let a
 * client self-assign `role: 'trainer'`.
 *
 * Roles are intrinsic (AGENTS.md rule 3): `trainer` is provisioned exclusively
 * via the Admin SDK, which bypasses security rules. Self-registration from the
 * client is therefore ALWAYS `athlete`. Before the fix, the create rule allowed
 * `role in ['athlete','trainer']`, letting any newly-registered user mint a
 * permanent trainer (role is pinned immutable on update) and unlock every
 * trainer-gated write surface (payments, routines, reviews, ...).
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` actually loaded and
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

// Distinct projectId so this suite runs in its own emulator namespace. Rules
// suites call clearFirestore() in afterEach; sharing a projectId with the other
// rules suites would let parallel Jest workers wipe each other's seed data
// mid-test. Same rules file, isolated data.
const PROJECT_ID = "treino-rules-test-sec001";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_USERS = "users";

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

/** A realistic self-registration payload, parameterised by role. */
function userDoc(uid: string, role: string): Record<string, unknown> {
  return {
    uid,
    role,
    email: `${uid}@example.test`,
    createdAt: 0,
    updatedAt: 0,
  };
}

describe("users/{uid} create — QA-SEC-001 role escalation", () => {
  const uid = "self-registrant";

  it("allows a client to self-register as 'athlete'", async () => {
    const me = testEnv.authenticatedContext(uid);
    const ref = me.firestore().collection(COL_USERS).doc(uid);
    await assertSucceeds(ref.set(userDoc(uid, "athlete")));
  });

  it("DENIES a client self-assigning 'trainer' on create (the escalation)", async () => {
    const me = testEnv.authenticatedContext(uid);
    const ref = me.firestore().collection(COL_USERS).doc(uid);
    await assertFails(ref.set(userDoc(uid, "trainer")));
  });

  it("denies an unknown/invalid role on create", async () => {
    const me = testEnv.authenticatedContext(uid);
    const ref = me.firestore().collection(COL_USERS).doc(uid);
    await assertFails(ref.set(userDoc(uid, "admin")));
    await assertFails(ref.set(userDoc(uid, "")));
  });

  it("denies creating a doc for a different uid (identity guard, unchanged)", async () => {
    const me = testEnv.authenticatedContext(uid);
    const ref = me.firestore().collection(COL_USERS).doc("someone-else");
    await assertFails(ref.set(userDoc("someone-else", "athlete")));
  });

  it("still lets the Admin SDK provision a trainer (rules bypassed)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_USERS)
          .doc("trainer-by-admin")
          .set(userDoc("trainer-by-admin", "trainer")),
      );
    });
  });
});
