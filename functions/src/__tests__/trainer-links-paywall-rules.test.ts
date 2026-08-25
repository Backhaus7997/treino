/**
 * Firestore security-rules enforcement tests for `trainer_links/{linkId}` —
 * the CF-write-only field pins (design §5.2).
 *
 * Asserts:
 *  1. A client CANNOT write `entitlement`, `blockedAt`, or `blockedReason`
 *     on a trainer_links doc (CF-write-only, ADR-1/ADR-6).
 *  2. The Admin SDK (CF path, bypasses rules) CAN still write those fields —
 *     proves the pin doesn't block the legitimate downgrade/reactivation path.
 *  3. Existing member flows (decline, terminate, pause, resume,
 *     sharedWithTrainer flip) still pass — regression check against PR1's
 *     new pin clauses layered onto the pre-existing update rule.
 *  4. `active` is CF-only since PR4 (acceptTrainerLink / resumeTrainerLink):
 *     NO client — trainer included — can drive pending→active or resume a
 *     paused link. (This bullet used to say the opposite; PR4 flipped those
 *     assertions to `assertFails` and the header was left behind.)
 *  5. `acceptedAt` is CF-write-only too (slice 5). It is the sole ordering key
 *     of reconcileEntitlements, so an unpinned rewrite is damage BETWEEN
 *     USERS — one member pushes ANOTHER athlete out of the trainer's quota.
 *  6. That pin covers BOTH client verbs (§5 below). The client really does
 *     write `acceptedAt` on create — `TrainerLinkRepository.request()` sends
 *     the whole toJson map — so pinning only `update` would have left the
 *     forgeable half open while the comments claimed the field was closed.
 *
 * NOT asserted anywhere in this file, deliberately: nothing here READS a
 * paywall field to authorize anything. Every pin below restricts WHO WRITES a
 * field. The athlete never loses read access — that invariant is enforced
 * separately by rules-read-isolation.test.ts §6.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (same pattern as
 * user-public-profiles-rules.test.ts).
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand trainer-links-paywall-rules"
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
// `ctx.firestore()` hands back a COMPAT Firestore, so the sentinels have to
// come from the compat namespace too (the modular `deleteField()` is a
// different class and the compat layer rejects it).
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

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
      // Real docs always carry sharedWithTrainer (app model defaults it to
      // false); the update rule reads it directly, so the fixture must too.
      sharedWithTrainer: false,
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
      sharedWithTrainer: false,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(
      ref.update({ status: "paused", pausedAt: Date.now() }),
    );
  });

  // FLIPPED in PR4 (was assertSucceeds): `resume` moved to the
  // resumeTrainerLink callable. paused -> active raises weighted load
  // 0.5 -> 1.0, so it has to clear the gate; a client that can write it
  // directly makes the limit unenforceable.
  it("resume: PF can NO LONGER transition paused -> active from the client", async () => {
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
      sharedWithTrainer: false,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ status: "active" }));
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

  // FLIPPED in PR4 (was assertSucceeds under "PR1 does NOT lock
  // pending->active yet"). This assertion IS the paywall: with it green,
  // `active` is unreachable from any client and the weighted-load gate in
  // acceptTrainerLink/resumeTrainerLink is the only door in.
  it("accept: the trainer can NO LONGER write pending -> active from the client", async () => {
    const linkId = "link-accept-pr4";
    const trainerId = "trainer-7";
    const athleteId = "athlete-7";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });

    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(
      ref.update({ status: "active", acceptedAt: Date.now() }),
    );
  });

  it("accept: the athlete can NO LONGER write pending -> active either", async () => {
    const linkId = "link-accept-athlete";
    const trainerId = "trainer-7b";
    const athleteId = "athlete-7b";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });

    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(
      ref.update({ status: "active", acceptedAt: Date.now() }),
    );
  });

  // NEW hardening in PR4, deliberate and not a side effect. The old clause
  // allowed `!(status in ['active','paused'])`, so EITHER member could
  // rewrite a live link back to `pending` — resetting the relationship and,
  // combined with the create rule, muddying the lifecycle. A legitimate
  // re-request creates a NEW doc; it never revives the old one.
  it("nobody can revert a live link back to pending", async () => {
    const trainerId = "trainer-8";
    const athleteId = "athlete-8";

    const cases: [string, "active" | "paused" | "terminated"][] = [
      ["link-revert-active", "active"],
      ["link-revert-paused", "paused"],
      ["link-revert-terminated", "terminated"],
    ];
    for (const [linkId, status] of cases) {
      await seedLink(linkId, {
        trainerId,
        athleteId,
        status,
        requestedAt: 1,
        acceptedAt: 2,
        sharedWithTrainer: false,
      });

      const trainer = testEnv.authenticatedContext(trainerId);
      await assertFails(
        trainer
          .firestore()
          .collection(COL_LINKS)
          .doc(linkId)
          .update({ status: "pending" }),
      );

      const athlete = testEnv.authenticatedContext(athleteId);
      await assertFails(
        athlete
          .firestore()
          .collection(COL_LINKS)
          .doc(linkId)
          .update({ status: "pending" }),
      );
    }
  });

  // Regression pin: pausing LOWERS weighted load, so it needs no gate and
  // stays client-side — but only for the trainer (QA-SEC-002).
  it("pause: the athlete still cannot pause (QA-SEC-002 preserved)", async () => {
    const linkId = "link-pause-athlete";
    const trainerId = "trainer-9";
    const athleteId = "athlete-9";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
      sharedWithTrainer: false,
    });

    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ status: "paused", pausedAt: Date.now() }));
  });
});

// ---------------------------------------------------------------------------
// 3. acceptedAt field-pin (paywall slice 5).
// ---------------------------------------------------------------------------
// Why this pin is its own section and not a footnote to §1: the other pins stop
// a trainer from lying about their OWN entitlement. This one stops damage
// BETWEEN USERS.
//
// `acceptedAt` is the only ordering key reconcileEntitlements has
// (select-blocked-links.ts): over the limit, the OLDEST links keep the slot.
// Unpinned, either member could rewrite their own `acceptedAt` — the write
// enters through the `status == resource.data.status` branch, so no status
// transition rule ever sees it — and shove a DIFFERENT athlete out of the
// trainer's quota. The legitimate writers are acceptTrainerLink /
// resumeTrainerLink, both Admin SDK, both bypassing rules.
describe("trainer_links rules — acceptedAt CF-write-only (slice 5)", () => {
  const linkId = "link-acceptedat";
  const trainerId = "trainer-10";
  const athleteId = "athlete-10";

  async function seedActive(): Promise<void> {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 1000,
      sharedWithTrainer: false,
    });
  }

  it("denies the ATHLETE backdating acceptedAt to jump the seniority queue", async () => {
    await seedActive();
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    // Status untouched — this is precisely the path the transition rules wave
    // through, and the whole reason the pin has to be a field pin.
    await assertFails(ref.update({ acceptedAt: 1 }));
  });

  it("denies the TRAINER moving acceptedAt on a link they own", async () => {
    await seedActive();
    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ acceptedAt: 5000 }));
  });

  it("denies stamping acceptedAt onto a link that never had one (forged seniority)", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertFails(ref.update({ acceptedAt: 1 }));
  });

  it("denies smuggling acceptedAt in alongside an otherwise legitimate terminate", async () => {
    await seedActive();
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    // terminate on its own is allowed (see below); the pin must not be
    // bypassable by riding along with a permitted transition.
    await assertFails(ref.update({ status: "terminated", acceptedAt: 1 }));
  });

  it("allows re-asserting the stored acceptedAt alongside a permitted change (not a forgery)", async () => {
    await seedActive();
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(ref.update({ sharedWithTrainer: true, acceptedAt: 1000 }));
  });

  it("allows the Admin SDK (acceptTrainerLink / resumeTrainerLink) to stamp acceptedAt", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_LINKS)
          .doc(linkId)
          .update({ status: "active", acceptedAt: 2000 }),
      );
    });
  });

  // The `get(field, null)` edge. Absent on BOTH sides must compare null==null
  // and be a no-op, or every update on a link that never reached `active`
  // (declining a pending request is the common one) breaks.
  it("is a no-op when acceptedAt is absent on both sides — declining a pending link still works", async () => {
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });
    const trainer = testEnv.authenticatedContext(trainerId);
    const ref = trainer.firestore().collection(COL_LINKS).doc(linkId);

    await assertSucceeds(ref.update({ status: "terminated" }));
  });
});

// ---------------------------------------------------------------------------
// 4. Regression: the pre-existing member flows survive the acceptedAt pin.
// ---------------------------------------------------------------------------
// Half of a pin's value is proving it did NOT break the legitimate paths. A pin
// that denies everything would pass every assertFails above.
describe("trainer_links rules — existing flows unaffected by the acceptedAt pin", () => {
  const trainerId = "trainer-11";
  const athleteId = "athlete-11";

  it("terminate (athlete, active link with acceptedAt stored) still passes", async () => {
    const linkId = "link-accpin-terminate";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 1000,
      sharedWithTrainer: false,
    });
    const athlete = testEnv.authenticatedContext(athleteId);
    await assertSucceeds(
      athlete.firestore().collection(COL_LINKS).doc(linkId).update({ status: "terminated" }),
    );
  });

  it("pause (trainer) still passes", async () => {
    const linkId = "link-accpin-pause";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 1000,
      sharedWithTrainer: false,
    });
    const trainer = testEnv.authenticatedContext(trainerId);
    await assertSucceeds(
      trainer
        .firestore()
        .collection(COL_LINKS)
        .doc(linkId)
        .update({ status: "paused", pausedAt: 2000 }),
    );
  });

  it("sharedWithTrainer flip (athlete) still passes", async () => {
    const linkId = "link-accpin-shared";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 1000,
      sharedWithTrainer: false,
    });
    const athlete = testEnv.authenticatedContext(athleteId);
    await assertSucceeds(
      athlete.firestore().collection(COL_LINKS).doc(linkId).update({ sharedWithTrainer: true }),
    );
  });

  it("decline (trainer, pending link, no acceptedAt) still passes", async () => {
    const linkId = "link-accpin-decline";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "pending",
      requestedAt: 1,
      sharedWithTrainer: false,
    });
    const trainer = testEnv.authenticatedContext(trainerId);
    await assertSucceeds(
      trainer.firestore().collection(COL_LINKS).doc(linkId).update({ status: "terminated" }),
    );
  });
});

// ---------------------------------------------------------------------------
// 5. The OTHER half of the acceptedAt write path: the CREATE verb.
// ---------------------------------------------------------------------------
// Section 3 pins `acceptedAt` on `update`. That is only half the door, and the
// client walks through the other half on every single link it ever makes:
// `TrainerLinkRepository.request()` does `ref.set(link.toJson())`, and the
// generated toJson emits `acceptedAt` — null, because a pending request has
// not been accepted yet.
//
// Without the create pin an athlete could stamp 1970 on their own link.
// `acceptedAt` is the SOLE ordering key of reconcileEntitlements: when a
// trainer goes over the cap, the OLDEST links keep the slot. Today the forged
// value dies before it can pay off (promote-link.ts overwrites it on accept,
// and a `pending` link is filtered out of the sort entirely) — but the `resume`
// branch of that same `tx.update` already PRESERVES `acceptedAt`, so one future
// transition that promotes without overwriting is all it takes. A pin on one
// verb, documented as if it covered both, is the failure mode worth testing.
describe("trainer_links rules — acceptedAt on create (slice 5)", () => {
  const trainerId = "trainer-create-pin";
  const athleteId = "athlete-create-pin";

  it("denies the athlete forging an ancient acceptedAt on their own new link", async () => {
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc("link-forged-antiquity");

    await assertFails(
      ref.set({
        athleteId,
        trainerId,
        status: "pending",
        requestedAt: 9999,
        acceptedAt: 1,
      }),
    );
  });

  it("denies a non-Timestamp acceptedAt on create (the shape that used to kill the sweep)", async () => {
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc("link-garbage-acceptedat");

    // The reconcile query is `where('trainerId','==',trainerId)` with NO status
    // filter, so even a pending doc reaches readMillis(). readMillis absorbs
    // this today; the rule now keeps it from arriving in the first place.
    await assertFails(
      ref.set({
        athleteId,
        trainerId,
        status: "pending",
        requestedAt: 1,
        acceptedAt: "2026-01-01",
      }),
    );
  });

  it("allows the real request() payload — acceptedAt present and null", async () => {
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc("link-request-shape");

    // This is what TrainerLinkRepository.request() actually sends. If the pin
    // rejected an explicit null it would break EVERY link request in the app.
    await assertSucceeds(
      ref.set({
        id: "link-request-shape",
        athleteId,
        trainerId,
        status: "pending",
        requestedAt: 1,
        acceptedAt: null,
        terminatedAt: null,
        terminationReason: null,
        pausedAt: null,
        sharedWithTrainer: false,
      }),
    );
  });

  it("allows a create that omits acceptedAt entirely", async () => {
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc("link-no-acceptedat");

    await assertSucceeds(
      ref.set({
        athleteId,
        trainerId,
        status: "pending",
        requestedAt: 1,
      }),
    );
  });

  it("denies the athlete creating an already-accepted link (status + acceptedAt in one write)", async () => {
    const athlete = testEnv.authenticatedContext(athleteId);
    const ref = athlete.firestore().collection(COL_LINKS).doc("link-born-active");

    // Belt and braces: `status == 'pending'` already blocked this before slice
    // 5. Kept as a control so a future edit that loosens the status check does
    // not silently reopen the antiquity vector along with it.
    await assertFails(
      ref.set({
        athleteId,
        trainerId,
        status: "active",
        requestedAt: 1,
        acceptedAt: 1,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// 6. The update pin against the sentinel shapes, not just plain values.
// ---------------------------------------------------------------------------
// Section 3 attacks the pin with literal payloads. A client that wanted the
// field GONE would not send a literal — it would send a sentinel, and the
// resulting document has no `acceptedAt` at all. `get(...,null)` is what makes
// that come out DENIED instead of comparing an absent field against itself.
describe("trainer_links rules — acceptedAt vs. the delete sentinel", () => {
  const trainerId = "trainer-accpin-sentinel";
  const athleteId = "athlete-accpin-sentinel";

  it("denies erasing acceptedAt with FieldValue.delete()", async () => {
    const linkId = "link-accpin-sentinel";
    await seedLink(linkId, {
      trainerId,
      athleteId,
      status: "active",
      requestedAt: 1,
      acceptedAt: 1000,
      sharedWithTrainer: false,
    });
    const athlete = testEnv.authenticatedContext(athleteId);

    await assertFails(
      athlete
        .firestore()
        .collection(COL_LINKS)
        .doc(linkId)
        .update({ acceptedAt: firebase.firestore.FieldValue.delete() }),
    );
  });
});
