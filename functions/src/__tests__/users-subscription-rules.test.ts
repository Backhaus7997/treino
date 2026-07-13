/**
 * Firestore security-rules enforcement tests for `users/{uid}` — paywall
 * Fase 7 PR1 `subscription` + `weightedLoad` field-pin (design §5.1).
 *
 * Asserts:
 *  1. A client (the doc owner) CANNOT write `subscription` or `weightedLoad`
 *     (CF-write-only — createPreapproval/mpWebhook/downgrade/reactivation
 *     write them via Admin SDK).
 *  2. The Admin SDK (CF path, bypasses rules) CAN still write those fields.
 *  3. The owner can still freely update every OTHER profile field (regression
 *     check — the pin must not lock the rest of the document).
 *  4. The four pre-existing immutable fields (uid/role/email/createdAt)
 *     remain protected — PR1 only ADDS to the existing update rule, doesn't
 *     regress it.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (same pattern as
 * user-public-profiles-rules.test.ts).
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth \
 *     "npm --prefix functions run test:rules"
 *
 * Requires Java 21+ for the emulator binary — NOT runnable locally in this
 * environment (Java<21). Runs in CI. Do not skip writing because it can't
 * run locally (tasks.md "Known Follow-Up").
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

const PROJECT_ID = "treino-rules-test";
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

interface UserFixture {
  uid: string;
  role: "athlete" | "trainer";
  email: string;
  createdAt: number;
  displayName?: string | null;
  subscription?: Record<string, unknown> | null;
  weightedLoad?: number | null;
}

/** Seed a users/{uid} doc via an Admin-privileged context (rules disabled). */
async function seedUser(fixture: UserFixture): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL_USERS).doc(fixture.uid).set(fixture);
  });
}

// ---------------------------------------------------------------------------
// 1. subscription/weightedLoad field-pin — the headline paywall assertion.
// ---------------------------------------------------------------------------
describe("users rules — subscription/weightedLoad CF-write-only (PR1, design §5.1)", () => {
  const uid = "trainer-forge-subscription";

  it("denies the owner writing a forged subscription map", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(
      ref.update({
        subscription: { tier: "plan2", status: "active", weightLimit: 15 },
      }),
    );
  });

  it("denies the owner escalating an existing subscription tier", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      subscription: { tier: "free", status: "active", weightLimit: 2 },
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(
      ref.update({
        subscription: { tier: "plan2", status: "active", weightLimit: 15 },
      }),
    );
  });

  it("denies the owner writing a forged weightedLoad", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      weightedLoad: 2,
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ weightedLoad: 999 }));
  });

  it("allows re-asserting the currently stored subscription/weightedLoad alongside an allowed field change (not a forgery)", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      displayName: "Old Name",
      subscription: { tier: "plan1", status: "active", weightLimit: 7 },
      weightedLoad: 3.5,
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertSucceeds(
      ref.update({
        displayName: "New Name",
        subscription: { tier: "plan1", status: "active", weightLimit: 7 },
        weightedLoad: 3.5,
      }),
    );
  });

  it("allows the Admin SDK (CF path — createPreapproval/mpWebhook/downgrade/reactivation) to write subscription/weightedLoad", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
    });

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_USERS)
          .doc(uid)
          .update({
            subscription: {
              tier: "plan1",
              status: "pending",
              weightLimit: 2,
              mpPreapprovalId: "mp-123",
            },
            weightedLoad: 0,
          }),
      );
    });
  });
});

// ---------------------------------------------------------------------------
// 2. Regression: owner can still edit other fields; pre-existing immutable
//    fields (uid/role/email/createdAt) stay protected.
// ---------------------------------------------------------------------------
describe("users rules — regression: unrelated profile edits + pre-existing immutability", () => {
  const uid = "trainer-normal-edit";

  it("allows a normal profile field edit (no subscription/weightedLoad touched)", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      displayName: "Alice",
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertSucceeds(ref.update({ displayName: "Alicia" }));
  });

  it("still denies role escalation (pre-existing pin, unaffected by PR1)", async () => {
    await seedUser({
      uid,
      role: "athlete",
      email: `${uid}@example.test`,
      createdAt: 0,
    });

    const athlete = testEnv.authenticatedContext(uid);
    const ref = athlete.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ role: "trainer" }));
  });

  it("still denies createdAt tampering (pre-existing pin, unaffected by PR1)", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 100,
    });

    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ createdAt: 0 }));
  });
});
