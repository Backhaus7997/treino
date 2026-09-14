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

  // FLIPPED in PR4 (was assertSucceeds). This suite pins the anti-forgery
  // gate; the accept flow itself moved to the acceptTrainerLink callable, so
  // `active` is now unreachable from ANY client — trainer included. The
  // anti-forgery property this file exists for gets STRONGER, not weaker.
  it("the trainer can no longer accept (pending -> active) from the client", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });
    const ref = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertFails(ref.update({ status: "active", acceptedAt: 2 }));
  });

  it("allows the trainer to pause (active -> paused) but NOT to resume", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });
    // pause LOWERS weighted load → no gate needed, stays client-side.
    const pauseRef = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertSucceeds(pauseRef.update({ status: "paused", pausedAt: 3 }));

    // resume RAISES it (0.5 -> 1.0) → CF-only from PR4 on.
    const resumeRef = ctxDb(TRAINER).collection(COL_LINKS).doc(LINK);
    await assertFails(resumeRef.update({ status: "active" }));
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

// ── terminationReason: quién puede escribir cada razón ──────────────────────
//
// `terminationReason` no estaba pineado ni acotado: cualquiera de los dos
// members podía escribir la razón que quisiera. Eso subió de prioridad cuando
// ese campo pasó a ser INPUT DE UN DELETE (`clasificarTerminacion` en
// functions/src/purge-rejected-link.ts decide con él si el doc se borra).
//
// El ataque concreto: el PF rechaza una solicitud pero estampa
// `cancelled-by-athlete`. La notificación y la fila de historial van SÓLO al
// PF; el atleta no se entera de nada, y el doc después se purga. La solicitud
// desaparece sin dejar rastro del lado del atleta.
//
// La regla NO puede pinear el campo inmutable —`decline`, `cancel` y
// `terminate` lo escriben todos como parte de la transición—. Lo que hace es
// atar las DOS razones que disparan el borrado a quien de verdad puede
// causarlas.
describe("trainer_links — terminationReason atado al actor", () => {
  it("DENIEGA que el PF estampe 'cancelled-by-athlete' (silenciaría al atleta)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });

    await assertFails(
      ctxDb(TRAINER).collection(COL_LINKS).doc(LINK).update({
        status: "terminated",
        terminationReason: "cancelled-by-athlete",
      }),
    );
  });

  it("DENIEGA que el atleta estampe 'declined'", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });

    await assertFails(
      ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK).update({
        status: "terminated",
        terminationReason: "declined",
      }),
    );
  });

  it("PERMITE el rechazo legítimo del PF ('declined')", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });

    await assertSucceeds(
      ctxDb(TRAINER).collection(COL_LINKS).doc(LINK).update({
        status: "terminated",
        terminationReason: "declined",
      }),
    );
  });

  it("PERMITE la cancelación legítima del atleta ('cancelled-by-athlete')", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "pending",
      requestedAt: 1,
    });

    await assertSucceeds(
      ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK).update({
        status: "terminated",
        terminationReason: "cancelled-by-athlete",
      }),
    );
  });

  it.each([
    ["athlete-terminated"],
    ["trainer-terminated"],
    ["switched_trainer"],
  ])(
    "los DOS members siguen pudiendo terminar un vínculo real (reason=%s)",
    async (reason) => {
      // Estas razones NO disparan el borrado, así que no se acotan: el modelo
      // sigue sin saber quién cortó, y atarlas sería inventar una regla que el
      // producto no tiene.
      for (const uid of [TRAINER, ATHLETE]) {
        await seedLink(LINK, {
          trainerId: TRAINER,
          athleteId: ATHLETE,
          status: "active",
          requestedAt: 1,
          acceptedAt: 2,
        });

        await assertSucceeds(
          ctxDb(uid).collection(COL_LINKS).doc(LINK).update({
            status: "terminated",
            terminationReason: reason,
          }),
        );

        await testEnv.clearFirestore();
      }
    },
  );

  it("PERMITE terminar sin razón (el campo es opcional)", async () => {
    await seedLink(LINK, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      requestedAt: 1,
      acceptedAt: 2,
    });

    await assertSucceeds(
      ctxDb(ATHLETE).collection(COL_LINKS).doc(LINK).update({
        status: "terminated",
      }),
    );
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
