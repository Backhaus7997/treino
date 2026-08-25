/**
 * Firestore security-rules enforcement tests for `users/{uid}` — the
 * CF-write-only field pins on the trainer's own document (design §5.1).
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
 *  5. `blockedAthleteIds` is CF-write-only too (slice 5). The field is INERT
 *     today — no rule reads it to authorize anything — and this pin does not
 *     change that: it constrains WHO WRITES it, not what anyone may read.
 *  6. The pin covers BOTH client verbs. `create` refuses the field outright,
 *     because the update pin would otherwise make a value planted at create
 *     INDELIBLE from the client, and reconcileEntitlements only runs for
 *     trainers. Section 4 also exercises the write SHAPES the app actually
 *     sends (`set(..., {merge:true})`, `FieldValue.delete()`, `arrayRemove`)
 *     rather than only the `update()` used in section 3.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (same pattern as
 * user-public-profiles-rules.test.ts).
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand users-subscription-rules"
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
// `ctx.firestore()` hands back a COMPAT Firestore (see the .collection().doc()
// calls below), so the sentinels have to come from the compat namespace too —
// the modular `deleteField()` is a different class and the compat layer would
// reject it.
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

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
  blockedAthleteIds?: string[];
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

// ---------------------------------------------------------------------------
// 3. blockedAthleteIds field-pin (paywall slice 5).
// ---------------------------------------------------------------------------
// The `users/{uid}` update rule is a conjunction of per-field pins WITHOUT
// `hasOnly` — its own comment says the owner "can still freely update every
// OTHER field on their own doc". `blockedAthleteIds` was one of those others,
// so a trainer could wipe the denormalized blocked list with a single client
// write. Worse than a plain lie: that write does not touch the `subscription`
// map, so `subscriptionChanged` returns false and NO trigger reconciles — the
// forged value survives until the 04:00 sweep.
//
// Today the field is INERT (no rule reads it), so the pin fixes nothing
// user-visible. That is the point of landing it now: the day enforcement reads
// the field, the bypass would already be one write deep.
describe("users rules — blockedAthleteIds CF-write-only (slice 5)", () => {
  const uid = "trainer-blocked-ids";

  async function seedWithBlocked(): Promise<void> {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
      displayName: "Coach",
      blockedAthleteIds: ["athlete-a", "athlete-b"],
    });
  }

  it("denies the trainer emptying their own blockedAthleteIds (the one-write bypass)", async () => {
    await seedWithBlocked();
    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ blockedAthleteIds: [] }));
  });

  it("denies dropping a single athlete from the list", async () => {
    await seedWithBlocked();
    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ blockedAthleteIds: ["athlete-a"] }));
  });

  it("denies materializing the field on a doc that does not have it", async () => {
    await seedUser({
      uid,
      role: "trainer",
      email: `${uid}@example.test`,
      createdAt: 0,
    });
    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(ref.update({ blockedAthleteIds: [] }));
  });

  it("denies smuggling the wipe in alongside a legitimate profile edit", async () => {
    await seedWithBlocked();
    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertFails(
      ref.update({ displayName: "Coach Renamed", blockedAthleteIds: [] }),
    );
  });

  it("allows re-asserting the stored list alongside an allowed field change (not a forgery)", async () => {
    await seedWithBlocked();
    const trainer = testEnv.authenticatedContext(uid);
    const ref = trainer.firestore().collection(COL_USERS).doc(uid);

    await assertSucceeds(
      ref.update({
        displayName: "Coach Renamed",
        blockedAthleteIds: ["athlete-a", "athlete-b"],
      }),
    );
  });

  it("allows the Admin SDK (reconcileEntitlements) to write blockedAthleteIds", async () => {
    await seedWithBlocked();

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_USERS)
          .doc(uid)
          .update({ blockedAthleteIds: ["athlete-c"] }),
      );
    });
  });

  // The `get(field, null)` edge, and the reason it is not a footnote: nearly
  // every user doc in the database has NO `blockedAthleteIds` (only trainers
  // over their limit get one). If absence on both sides did not compare
  // null==null, this pin would deny ordinary profile edits for every athlete
  // in the product.
  it("is a no-op when the field is absent on both sides — ordinary profile edits still pass", async () => {
    const plainUid = "athlete-no-blocked-field";
    await seedUser({
      uid: plainUid,
      role: "athlete",
      email: `${plainUid}@example.test`,
      createdAt: 0,
      displayName: "Bob",
    });
    const athlete = testEnv.authenticatedContext(plainUid);
    const ref = athlete.firestore().collection(COL_USERS).doc(plainUid);

    await assertSucceeds(ref.update({ displayName: "Roberto" }));
  });
});

// ---------------------------------------------------------------------------
// 4. The OTHER verb, and the write shapes the app actually sends.
// ---------------------------------------------------------------------------
// Section 3 only ever calls `update()`. Two things hide in that gap.
//
// (a) THE CREATE. `allow create` pins uid and role and nothing else, so a
//     brand-new user could plant `blockedAthleteIds: ['victim']` in their own
//     document — and the update pin then made it INDELIBLE from the client.
//     Worse than inert: reconcileEntitlements only runs for trainers, so on an
//     `athlete` doc the planted array survives indefinitely, and the trainer
//     role is provisioned by the Admin SDK ON TOP of a doc that was born as an
//     athlete. Half a pin, documented as a whole one, is worse than no pin.
//
// (b) THE SHAPE. Production never calls `update()` on this collection:
//     UserRepository writes `set(sanitized, SetOptions(merge: true))` and the
//     FCM repository writes `set({fcmTokens: arrayUnion(...)}, merge: true)`.
//     A regression test that proves "ordinary profile edits still pass" using
//     a shape the app does not send proves less than it looks.
describe("users rules — blockedAthleteIds: create verb + real write shapes", () => {
  const uid = "athlete-plants-blocked-ids";

  it("denies planting blockedAthleteIds in a freshly created own doc", async () => {
    const client = testEnv.authenticatedContext(uid);
    const ref = client.firestore().collection(COL_USERS).doc(uid);

    await assertFails(
      ref.set({
        uid,
        role: "athlete",
        email: `${uid}@example.test`,
        createdAt: 0,
        blockedAthleteIds: ["victim-x"],
      }),
    );
  });

  it("allows the ordinary signup create — the pin only refuses the field", async () => {
    const freshUid = "athlete-ordinary-signup";
    const client = testEnv.authenticatedContext(freshUid);
    const ref = client.firestore().collection(COL_USERS).doc(freshUid);

    // Exactly the shape UserProfile.toJson() produces: the Dart model has no
    // `blockedAthleteIds` field at all, so no legitimate create carries it.
    await assertSucceeds(
      ref.set({
        uid: freshUid,
        role: "athlete",
        email: `${freshUid}@example.test`,
        displayName: null,
        createdAt: 1,
        updatedAt: 1,
      }),
    );
  });

  // El mismo agujero, pero en el campo que SI cobra: `subscription`. Estaba
  // abierto en produccion y era explotable — verificado contra el emulador:
  //   create con subscription {tier:'plan3'} -> PERMITIDO
  //   update para sacarsela                  -> denegado (el pin de update)
  // O sea que el pin que existe para proteger el campo lo volvia INDELEBLE:
  // el plan mas caro, forjado y para siempre, sin escritura de cliente que lo
  // revierta. El rol creado es 'athlete' y el paywall mide entrenadores, pero
  // los PF se aprovisionan a mano sobre el doc que YA existe, asi que un
  // `update({role:'trainer'})` deja la suscripcion forjada intacta.
  it("denies forging a subscription at create — era un plan3 gratis e indeleble", async () => {
    const forger = "athlete-forges-subscription";
    const ref = testEnv.authenticatedContext(forger).firestore().collection(COL_USERS).doc(forger);

    await assertFails(
      ref.set({
        uid: forger,
        role: "athlete",
        email: `${forger}@example.test`,
        createdAt: 0,
        subscription: { tier: "plan3", status: "active" },
      }),
    );
  });

  it("denies forging weightedLoad at create", async () => {
    const forger = "athlete-forges-load";
    const ref = testEnv.authenticatedContext(forger).firestore().collection(COL_USERS).doc(forger);

    await assertFails(
      ref.set({
        uid: forger,
        role: "athlete",
        email: `${forger}@example.test`,
        createdAt: 0,
        weightedLoad: 0,
      }),
    );
  });

  it("el Admin SDK SI puede sembrar subscription — el aprovisionamiento manual no se rompe", async () => {
    // Sin esta mitad, un pin que denegara todo tambien pasaria los assertFails.
    const provisioned = "trainer-provisioned-by-team";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection(COL_USERS).doc(provisioned).set({
        uid: provisioned,
        role: "trainer",
        email: `${provisioned}@example.test`,
        createdAt: 0,
        subscription: { tier: "plan2", status: "active" },
      });
    });
  });

  it("allows a create that carries an explicit null (same get(...,null) idiom)", async () => {
    const freshUid = "athlete-explicit-null";
    const client = testEnv.authenticatedContext(freshUid);
    const ref = client.firestore().collection(COL_USERS).doc(freshUid);

    await assertSucceeds(
      ref.set({
        uid: freshUid,
        role: "athlete",
        email: `${freshUid}@example.test`,
        createdAt: 1,
        blockedAthleteIds: null,
      }),
    );
  });

  it("allows the production profile-edit shape: set(..., {merge: true})", async () => {
    const trainerUid = "trainer-merge-shape";
    await seedUser({
      uid: trainerUid,
      role: "trainer",
      email: `${trainerUid}@example.test`,
      createdAt: 0,
      displayName: "Coach",
      blockedAthleteIds: ["athlete-a"],
    });
    const trainer = testEnv.authenticatedContext(trainerUid);
    const ref = trainer.firestore().collection(COL_USERS).doc(trainerUid);

    // UserRepository.save() → set(sanitized, SetOptions(merge: true)). With
    // merge semantics `request.resource.data` is the full POST-merge document,
    // so the stored blocked list is part of every unrelated write from now on.
    // If that tripped the pin, the pin would brick profile editing outright.
    await assertSucceeds(ref.set({ displayName: "Coach Renamed" }, { merge: true }));
  });

  it("denies deleting the field with the FieldValue.delete() sentinel", async () => {
    const trainerUid = "trainer-delete-sentinel";
    await seedUser({
      uid: trainerUid,
      role: "trainer",
      email: `${trainerUid}@example.test`,
      createdAt: 0,
      blockedAthleteIds: ["athlete-a"],
    });
    const trainer = testEnv.authenticatedContext(trainerUid);
    const ref = trainer.firestore().collection(COL_USERS).doc(trainerUid);

    // The most natural way a client would try to drop the field: it is not an
    // empty array, so it does not look like the section-3 payloads at all.
    await assertFails(
      ref.update({ blockedAthleteIds: firebase.firestore.FieldValue.delete() }),
    );
  });

  it("denies removing one athlete with the arrayRemove sentinel", async () => {
    const trainerUid = "trainer-array-remove";
    await seedUser({
      uid: trainerUid,
      role: "trainer",
      email: `${trainerUid}@example.test`,
      createdAt: 0,
      blockedAthleteIds: ["athlete-a", "athlete-b"],
    });
    const trainer = testEnv.authenticatedContext(trainerUid);
    const ref = trainer.firestore().collection(COL_USERS).doc(trainerUid);

    await assertFails(
      ref.update({
        blockedAthleteIds: firebase.firestore.FieldValue.arrayRemove("athlete-a"),
      }),
    );
  });
});
