/**
 * Regression tests for QA-SEC-002 — an athlete must not be able to self-promote
 * a `trainer_links` doc into a reviewable state and thereby forge reviews.
 *
 * The exploit chain (all client-side, no trainer involvement):
 *   1. athlete creates trainer_links/{id} {athleteId: me, trainerId: victim,
 *      status: 'pending'}  — create rule allows it (no consent check).
 *   2. athlete updates status pending -> active  — the update rule used to let
 *      EITHER member change status with no transition/actor validation.
 *   3. athlete creates reviews/{id} — gated on the link being
 *      status in ['active','paused'], which step 2 satisfied.
 *
 * The fix hardens the trainer_links update rule: only the trainer may promote a
 * link INTO 'active'/'paused'. The athlete can still create the pending request,
 * terminate, and flip sharedWithTrainer; the trainer's accept/pause/resume are
 * unaffected. This closes the forge at its root (the link), so the review gate
 * can keep trusting link.status.
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` loaded and enforced
 * (client-authenticated contexts), NOT the Admin SDK.
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
const PROJECT_ID = "treino-rules-test-sec002";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_LINKS = "trainer_links";
const COL_REVIEWS = "reviews";

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
}

async function seedLink(linkId: string, fixture: LinkFixture): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    // Real links always carry `sharedWithTrainer`; default it so trainer-side
    // updates don't trip the rule's `sharedWithTrainer` equality check on an
    // undefined field (a pre-existing null-safety gap in the update rule that
    // only surfaces when the field is absent AND the actor is the trainer).
    await ctx
      .firestore()
      .collection(COL_LINKS)
      .doc(linkId)
      .set({ sharedWithTrainer: false, ...fixture });
  });
}

const TRAINER = "trainer-sec002";
const ATHLETE = "athlete-sec002";
const LINK = `${TRAINER}_${ATHLETE}`;

function ctxDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe("trainer_links update — QA-SEC-002 self-promotion", () => {
  it("DENIES the athlete promoting pending -> active (the forge)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });
    const ref = ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK);
    await assertFails(ref.update({ status: "active", acceptedAt: 2 }));
  });

  it("DENIES the athlete promoting pending -> paused (alternate reviewable state)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });
    const ref = ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK);
    await assertFails(ref.update({ status: "paused", pausedAt: 2 }));
  });

  it("DENIES the athlete pausing an active link (only the trainer pauses)", async () => {
    // Even on an already-active link, the athlete cannot drive status changes
    // into a reviewable state; only the trainer pauses.
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });
    const ref = ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK);
    await assertFails(ref.update({ status: "paused", pausedAt: 3 }));
  });

  it("allows the trainer to accept (pending -> active) — legit flow preserved", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });
    const ref = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(ref.update({ status: "active", acceptedAt: 2 }));
  });

  it("allows the trainer to pause (active -> paused) and resume (paused -> active)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });
    const pauseRef = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(pauseRef.update({ status: "paused", pausedAt: 3 }));

    const resumeRef = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(resumeRef.update({ status: "active" }));
  });

  it("allows the athlete to terminate (active -> terminated) — not a reviewable state", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });
    const ref = ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(ref.update({ status: "terminated" }));
  });

  it("allows the athlete to flip sharedWithTrainer on an active link (status unchanged)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      sharedWithTrainer: false,
    });
    const ref = ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(ref.update({ sharedWithTrainer: true }));
  });
});

describe("reviews — QA-SEC-002 forge closed end-to-end", () => {
  function review() {
    return {
      id: `${LINK}_${ATHLETE}`,
      linkId: LINK,
      athleteId: ATHLETE,
      trainerId: TRAINER,
      rating: 1,
      createdAt: 10,
    };
  }

  it("athlete cannot review: self-promotion is blocked, so the link stays pending", async () => {
    // The athlete creates the pending link legitimately...
    await assertSucceeds(
      ctxDb(ATHLETE)
        .collection(COL_LINKS)
        .doc(LINK)
        .set({
          athleteId: ATHLETE,
          trainerId: TRAINER,
          status: "pending",
          requestedAt: 1,
        }),
    );
    // ...but cannot self-activate it...
    await assertFails(
      ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK).update({ status: "active" }),
    );
    // ...so the link is still 'pending' and the review gate rejects.
    await assertFails(
      ctxDb(ATHLETE)
        .collection(COL_REVIEWS)
        .doc(`${LINK}_${ATHLETE}`)
        .set(review()),
    );
  });

  it("control: with a trainer-activated link, the athlete's review is allowed", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });
    await assertSucceeds(
      ctxDb(ATHLETE)
        .collection(COL_REVIEWS)
        .doc(`${LINK}_${ATHLETE}`)
        .set(review()),
    );
  });
});
