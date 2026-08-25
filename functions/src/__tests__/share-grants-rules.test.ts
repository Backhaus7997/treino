/**
 * Rules tests for `session_shares/{athleteId}` and `profile_shares/{athleteId}`
 * — the two CONSENT GRANTS an athlete gives to exactly one trainer.
 *
 * WHY THIS FILE EXISTS
 * The rules-coverage matrix (docs/security.md, #680 Slice A) found both
 * collections at **zero** negative tests. They are not ordinary documents:
 * they are capability tokens. Other rules `get()` them and hand out access
 * on the strength of what they say —
 *   - `users/{uid}/sessions/**`  → the athlete's whole training history;
 *   - `users/{uid}/sessions/{sid}/setLogs/**`;
 *   - `measurements` where `recordedBy == athleteId` → self-logged body
 *     measurements, gated on BOTH grants naming the same trainer.
 * So a rule that let anyone but the athlete WRITE these docs would not leak
 * one document, it would mint the capability to read all of the above. The
 * doc id is the athlete's uid and `userPublicProfiles` is world-readable, so
 * the target path is trivially enumerable.
 *
 * WHAT IS ASSERTED
 *   1. only the athlete may write their own grant — a trainer cannot forge,
 *      flip, or delete it (create / update / delete, three separate vectors);
 *   2. the grant is not world-readable — an unrelated user cannot learn WHICH
 *      trainer an athlete works with;
 *   3. the end-to-end payload: a trainer WITH the grant reads the athlete's
 *      sessions; the same trainer, after the grant is gone, does not. This is
 *      the assertion that makes the ones above matter — without it a green
 *      suite would only prove the token is well-guarded, not that it is the
 *      thing actually opening the door.
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
const PROJECT_ID = "treino-rules-test-sharegrants";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_SESSION_SHARES = "session_shares";
const COL_PROFILE_SHARES = "profile_shares";
const COL_USERS = "users";

const ATHLETE = "athlete-grants";
const TRAINER = "trainer-grants";
const OTHER_TRAINER = "other-trainer-grants";

const SESSION_ID = "session-grants-1";

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

/** Writes a doc bypassing rules (the CF / athlete-consent path). */
async function seedDoc(
  col: string,
  docId: string,
  data: Record<string, unknown>,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(col).doc(docId).set(data);
  });
}

/** Seeds one training session under the athlete, bypassing rules. */
async function seedSession(): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_USERS)
      .doc(ATHLETE)
      .collection("sessions")
      .doc(SESSION_ID)
      .set({ id: SESSION_ID, uid: ATHLETE, startedAt: new Date() });
  });
}

function grant(trainerId: string): Record<string, unknown> {
  return { trainerId, updatedAt: new Date() };
}

// Both collections carry the SAME rule (doc id == athleteId, athlete-only
// write, two-party read), so they are exercised by the same table rather than
// two copy-pasted describes — if the two rules ever diverge, this is the file
// that has to say so out loud.
const GRANT_COLLECTIONS: Array<[string, string]> = [
  [COL_SESSION_SHARES, "session_shares — training-history grant"],
  [COL_PROFILE_SHARES, "profile_shares — personal-data grant"],
];

describe.each(GRANT_COLLECTIONS)("%s", (col) => {
  describe("write — only the athlete may grant", () => {
    it("allows the athlete to create their own grant", async () => {
      await assertSucceeds(
        ctxDb(ATHLETE).collection(col).doc(ATHLETE).set(grant(TRAINER)),
      );
    });

    it("DENIES a trainer forging the grant that names themselves", async () => {
      // The whole capability: if this passed, the trainer would mint their
      // own access to the athlete's history without the athlete ever
      // touching the consent toggle.
      await assertFails(
        ctxDb(TRAINER).collection(col).doc(ATHLETE).set(grant(TRAINER)),
      );
    });

    it("DENIES an unrelated user forging a grant for someone else", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(col).doc(ATHLETE).set(grant(OTHER_TRAINER)),
      );
    });

    it("DENIES a non-string trainerId", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(col).doc(ATHLETE).set({ trainerId: 42 }),
      );
      await assertFails(
        ctxDb(ATHLETE).collection(col).doc(ATHLETE).set({ updatedAt: new Date() }),
      );
    });

    it("DENIES an unauthenticated write", async () => {
      await assertFails(
        testEnv
          .unauthenticatedContext()
          .firestore()
          .collection(col)
          .doc(ATHLETE)
          .set(grant(TRAINER)),
      );
    });
  });

  describe("update / delete on an existing grant", () => {
    beforeEach(async () => {
      await seedDoc(col, ATHLETE, grant(TRAINER));
    });

    it("allows the athlete to move the grant to a different trainer", async () => {
      await assertSucceeds(
        ctxDb(ATHLETE).collection(col).doc(ATHLETE).set(grant(OTHER_TRAINER)),
      );
    });

    it("allows the athlete to revoke by deleting the grant", async () => {
      await assertSucceeds(
        ctxDb(ATHLETE).collection(col).doc(ATHLETE).delete(),
      );
    });

    it("DENIES the granted trainer redirecting the grant to themselves-forever", async () => {
      // Even the legitimately-granted trainer may not touch the doc: the
      // grant is the athlete's to move and to revoke.
      await assertFails(
        ctxDb(TRAINER)
          .collection(col)
          .doc(ATHLETE)
          .set({ trainerId: TRAINER }, { merge: true }),
      );
    });

    it("DENIES an outsider stealing the grant", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(col)
          .doc(ATHLETE)
          .set({ trainerId: OTHER_TRAINER }, { merge: true }),
      );
    });

    it("DENIES a trainer deleting the athlete's grant", async () => {
      await assertFails(
        ctxDb(TRAINER).collection(col).doc(ATHLETE).delete(),
      );
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(col).doc(ATHLETE).delete(),
      );
    });
  });

  describe("read — two parties only", () => {
    beforeEach(async () => {
      await seedDoc(col, ATHLETE, grant(TRAINER));
    });

    it("allows the athlete to read their own grant", async () => {
      await assertSucceeds(ctxDb(ATHLETE).collection(col).doc(ATHLETE).get());
    });

    it("allows the granted trainer to read it", async () => {
      await assertSucceeds(ctxDb(TRAINER).collection(col).doc(ATHLETE).get());
    });

    it("DENIES an unrelated user learning who the athlete's trainer is", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(col).doc(ATHLETE).get(),
      );
    });

    it("DENIES an unauthenticated read", async () => {
      await assertFails(
        testEnv
          .unauthenticatedContext()
          .firestore()
          .collection(col)
          .doc(ATHLETE)
          .get(),
      );
    });

    it("DENIES enumerating the whole grant collection", async () => {
      // `list` has no owner filter to short-circuit on, so a collection-wide
      // query would hand over the entire PF↔alumno graph in one round trip.
      await assertFails(ctxDb(OTHER_TRAINER).collection(col).get());
      await assertFails(ctxDb(ATHLETE).collection(col).get());
    });
  });
});

// ─── The payload the grant actually unlocks ──────────────────────────────────

describe("session_shares is what opens users/{uid}/sessions to a trainer", () => {
  beforeEach(async () => {
    await seedSession();
  });

  it("DENIES a trainer reading the athlete's sessions with no grant", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(ATHLETE)
        .collection("sessions")
        .doc(SESSION_ID)
        .get(),
    );
  });

  it("allows the granted trainer to read them", async () => {
    await seedDoc(COL_SESSION_SHARES, ATHLETE, grant(TRAINER));
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(ATHLETE)
        .collection("sessions")
        .doc(SESSION_ID)
        .get(),
    );
  });

  it("DENIES a DIFFERENT trainer even while a grant exists for someone else", async () => {
    await seedDoc(COL_SESSION_SHARES, ATHLETE, grant(TRAINER));
    await assertFails(
      ctxDb(OTHER_TRAINER)
        .collection(COL_USERS)
        .doc(ATHLETE)
        .collection("sessions")
        .doc(SESSION_ID)
        .get(),
    );
  });

  it("DENIES the trainer again once the athlete revokes the grant", async () => {
    await seedDoc(COL_SESSION_SHARES, ATHLETE, grant(TRAINER));
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(ATHLETE)
        .collection("sessions")
        .doc(SESSION_ID)
        .get(),
    );

    await assertSucceeds(
      ctxDb(ATHLETE).collection(COL_SESSION_SHARES).doc(ATHLETE).delete(),
    );

    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_USERS)
        .doc(ATHLETE)
        .collection("sessions")
        .doc(SESSION_ID)
        .get(),
    );
  });
});
