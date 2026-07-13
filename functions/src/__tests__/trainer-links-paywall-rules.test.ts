/**
 * Firestore security-rules enforcement tests for `trainer_links/{linkId}` —
 * paywall Fase 7 PR1 entitlement field-pin (design §5.2, entitlement half).
 *
 * Asserts:
 *  1. A client CANNOT write `entitlement`, `blockedAt`, or `blockedReason`
 *     on a trainer_links doc (CF-write-only, ADR-1/ADR-6).
 *  2. The Admin SDK (CF path, bypasses rules) CAN still write those fields —
 *     proves the pin doesn't block the legitimate downgrade/reactivation path.
 *  3. Existing member flows (decline, terminate, pause, resume,
 *     sharedWithTrainer flip) still pass — regression check against PR1's
 *     new pin clauses layered onto the pre-existing update rule.
 *  4. PR1 explicitly does NOT lock the pending→active promotion yet (that
 *     lands in PR4 alongside acceptTrainerLink CF) — a plain client accept()
 *     write must still succeed here, or PR4's sequencing note is violated.
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

const COL_LINKS = "trainer_links";

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

interface LinkFixture {
  trainerId: string;
  athleteId: string;
  status: "pending" | "active" | "paused" | "terminated";
  requestedAt: number;
  acceptedAt?: number | null;
  pausedAt?: number | null;
  sharedWithTrainer?: boolean;
  entitlement?: "entitled" | "blocked";
  blockedAt?: number | null;
  blockedReason?: string | null;
}

/** Seed a trainer_links doc via an Admin-privileged context (rules disabled). */
async function seedLink(
  linkId: string,
  fixture: LinkFixture,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_LINKS)
      .doc(linkId)
      .set(fixture);
  });
}

// ---------------------------------------------------------------------------
// 1. Entitlement field-pin — the headline paywall security assertion.
// ---------------------------------------------------------------------------
describe("trainer_links rules — entitlement CF-write-only (PR1, design §5.2)", () => {
  const linkId = "link-entitlement-forge";
  const trainerId = "trainer-1";
  const athleteId = "athlete-1";

  it("denies the trainer forging entitlement from blocked to entitled", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      entitlement: "blocked",
      blockedAt: 3,
      blockedReason: "nonpayment",
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ entitlement: "entitled" }));
  });

  it("denies the trainer forging entitlement from entitled to blocked (self-favoring bypass check)", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      entitlement: "entitled",
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ entitlement: "blocked" }));
  });

  it("denies the athlete writing blockedAt/blockedReason directly", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      entitlement: "entitled",
    });

    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(
      ref.update({ blockedAt: Date.now(), blockedReason: "nonpayment" }),
    );
  });

  it("allows re-asserting the currently stored entitlement value alongside an allowed field change (not a forgery)", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      entitlement: "entitled",
      sharedWithTrainer: false,
    });

    // Athlete flips sharedWithTrainer (allowed) while entitlement stays the
    // same value it already had — must NOT be treated as a forged write.
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(
      ref.update({ sharedWithTrainer: true, entitlement: "entitled" }),
    );
  });

  it("allows the Admin SDK (downgrade/reactivation CF path) to write entitlement/blockedAt/blockedReason", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      entitlement: "entitled",
    });

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_LINKS)
          .doc(linkId)
          .update({
            entitlement: "blocked",
            blockedAt: Date.now(),
            blockedReason: "nonpayment",
          }),
      );
    });
  });
});

// ---------------------------------------------------------------------------
// 2. Regression: existing member flows still pass with PR1's added pin.
// ---------------------------------------------------------------------------
describe("trainer_links rules — existing flows unaffected by entitlement pin", () => {
  it("decline: PF can transition pending -> terminated", async () => {
    const linkId = "link-decline";
    const trainerId = "trainer-2";
    const athleteId = "athlete-2";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(
      ref.update({
        status: "terminated",
        terminatedAt: Date.now(),
        terminationReason: "declined",
      }),
    );
  });

  it("terminate: athlete can transition active -> terminated", async () => {
    const linkId = "link-terminate";
    const trainerId = "trainer-3";
    const athleteId = "athlete-3";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });

    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(
      ref.update({ status: "terminated", terminatedAt: Date.now() }),
    );
  });

  it("pause: PF can transition active -> paused", async () => {
    const linkId = "link-pause";
    const trainerId = "trainer-4";
    const athleteId = "athlete-4";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(
      ref.update({ status: "paused", pausedAt: Date.now() }),
    );
  });

  it("resume: PF can transition paused -> active", async () => {
    const linkId = "link-resume";
    const trainerId = "trainer-5";
    const athleteId = "athlete-5";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "paused",
      requestedAt: 1,
      acceptedAt: 2,
      pausedAt: 3,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(ref.update({ status: "active" }));
  });

  it("sharedWithTrainer: only the athlete can flip the privacy flag", async () => {
    const linkId = "link-shared";
    const trainerId = "trainer-6";
    const athleteId = "athlete-6";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      sharedWithTrainer: false,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const trainerRef = trainer.firestore().collection(COL_LINKS).doc(linkId);
    await assertFails(trainerRef.update({ sharedWithTrainer: true }));

    const athlete = testEnv.authenticatedContext(athleteId);
    const athleteRef = athlete.firestore().collection(COL_LINKS).doc(linkId);
    await assertSucceeds(athleteRef.update({ sharedWithTrainer: true }));
  });

  it(
    "PR1 does NOT lock pending->active yet: client accept() still succeeds " +
      "(the lock lands in PR4 alongside acceptTrainerLink CF)",
    async () => {
      const linkId = "link-accept-pr1";
      const trainerId = "trainer-7";
      const athleteId = "athlete-7";
      await seedLink(linkId, {
        trainerId,
        athleteId,
        status: "pending",
        requestedAt: 1,
      });

      const trainer = testEnv.authenticatedContext(trainerId);
      const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

      await assertSucceeds(
        ref.update({ status: "active", acceptedAt: Date.now() }),
      );
    },
  );
});
