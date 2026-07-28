/**
 * Firestore rules tests — template publishing + community ratings (Fase W3).
 *
 * Covers the three new/changed surfaces in firestore.rules:
 *   1. UPDATE path 5 on /routines: the owning trainer flips ONLY `visibility`
 *      between 'private' and 'public' on their trainer-template.
 *   2. CF-only aggregates: `ratingAvg`/`ratingsCount` can never be seeded on
 *      create nor mutated by any client update — while a template that DOES
 *      carry CF-written aggregates must remain content-editable (hasOnly
 *      regression).
 *   3. /routines/{routineId}/ratings/{userId}: one upsert-able doc per rater
 *      on published templates only; the author cannot rate their own work.
 *
 * Runs against the Firestore emulator via `npm --prefix functions test`
 * (CI: firebase emulators:exec). Shares the --runInBand requirement with the
 * other rules suites.
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

const PROJECT_ID = "treino-rules-test-tplpub001";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER_A = "trainer-a";
const TRAINER_B = "trainer-b";
const ATHLETE = "athlete-1";
const RATER = "rater-1";

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

function templateDoc(overrides: Record<string, unknown> = {}) {
  return {
    name: "Plantilla PPL",
    split: "PPL",
    level: "beginner",
    days: [],
    numWeeks: 1,
    source: "trainer-template",
    visibility: "private",
    assignedBy: TRAINER_A,
    assignedTo: null,
    status: "active",
    createdAt: new Date(),
    ...overrides,
  };
}

function ratingPayload(uid: string, overrides: Record<string, unknown> = {}) {
  return {
    userId: uid,
    rating: 4,
    comment: null,
    createdAt: new Date(1000),
    updatedAt: new Date(1000),
    ...overrides,
  };
}

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // Private template owned by TRAINER_A.
    await db.collection("routines").doc("tpl-private").set(templateDoc());
    // Published template owned by TRAINER_A.
    await db
      .collection("routines")
      .doc("tpl-public")
      .set(templateDoc({ visibility: "public" }));
    // Published template that already carries CF-written aggregates.
    await db
      .collection("routines")
      .doc("tpl-rated")
      .set(
        templateDoc({ visibility: "public", ratingAvg: 4.5, ratingsCount: 3 }),
      );
    // Athlete-owned public routine — ratings must NOT attach to these.
    await db.collection("routines").doc("user-pub").set({
      name: "Mi rutina",
      level: "beginner",
      days: [],
      numWeeks: 1,
      source: "user-created",
      createdBy: ATHLETE,
      visibility: "public",
      status: "active",
      createdAt: new Date(),
    });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

// ---------------------------------------------------------------------------
// 1. Publish / unpublish (UPDATE path 5)
// ---------------------------------------------------------------------------
describe("publish/unpublish a trainer template (UPDATE path 5)", () => {
  it("ALLOWS the owner to publish (private → public)", async () => {
    await assertSucceeds(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-private")
        .update({ visibility: "public" }),
    );
  });

  it("ALLOWS the owner to unpublish (public → private)", async () => {
    await assertSucceeds(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-public")
        .update({ visibility: "private" }),
    );
  });

  it("DENIES flipping visibility to 'shared'", async () => {
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-private")
        .update({ visibility: "shared" }),
    );
  });

  it("DENIES another trainer publishing someone else's template", async () => {
    await assertFails(
      asUser(TRAINER_B)
        .collection("routines")
        .doc("tpl-private")
        .update({ visibility: "public" }),
    );
  });

  it("DENIES an athlete publishing a template", async () => {
    await assertFails(
      asUser(ATHLETE)
        .collection("routines")
        .doc("tpl-private")
        .update({ visibility: "public" }),
    );
  });

  it("DENIES a visibility flip that smuggles a content edit", async () => {
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-private")
        .update({ visibility: "public", name: "Renombrada" }),
    );
  });

  it("DENIES publishing a user-created routine via this path", async () => {
    // The narrow path is trainer-template only; user-created visibility
    // flips ride UPDATE path 2 (owner content edits), not path 5.
    await assertFails(
      asUser(TRAINER_B)
        .collection("routines")
        .doc("user-pub")
        .update({ visibility: "private" }),
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Read/list of published templates
// ---------------------------------------------------------------------------
describe("reading published templates", () => {
  it("ALLOWS any authenticated user to read a public trainer-template", async () => {
    await assertSucceeds(
      asUser(RATER).collection("routines").doc("tpl-public").get(),
    );
  });

  it("DENIES a stranger reading a private trainer-template", async () => {
    // No userPublicProfiles/{TRAINER_A} doc is seeded, so the
    // sharedTemplatesWithAthletes carve-out cannot apply either.
    await assertFails(
      asUser(RATER).collection("routines").doc("tpl-private").get(),
    );
  });

  it("ALLOWS the community-catalogue query (source + visibility filters)", async () => {
    await assertSucceeds(
      asUser(RATER)
        .collection("routines")
        .where("source", "==", "trainer-template")
        .where("visibility", "==", "public")
        .get(),
    );
  });

  it("DENIES an unauthenticated read of a public template", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("routines")
        .doc("tpl-public")
        .get(),
    );
  });
});

// ---------------------------------------------------------------------------
// 3. CF-only aggregates (ratingAvg / ratingsCount)
// ---------------------------------------------------------------------------
describe("ratingAvg/ratingsCount are CF-write-only", () => {
  it("DENIES creating a template pre-seeded with forged aggregates", async () => {
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-forged")
        .set(templateDoc({ ratingAvg: 5.0, ratingsCount: 999 })),
    );
  });

  it("DENIES creating a template with even a null aggregate key", async () => {
    // Absence guard: a present-null key would pollute the post-state keys()
    // of every later content edit.
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-forged")
        .set(templateDoc({ ratingAvg: null })),
    );
  });

  it("DENIES creating a user-created routine seeded with aggregates", async () => {
    await assertFails(
      asUser(ATHLETE).collection("routines").doc("user-forged").set({
        name: "Mi rutina",
        level: "beginner",
        days: [],
        numWeeks: 1,
        source: "user-created",
        createdBy: ATHLETE,
        visibility: "private",
        status: "active",
        createdAt: new Date(),
        ratingsCount: 50,
      }),
    );
  });

  it("DENIES the owner mutating ratingAvg directly", async () => {
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-rated")
        .update({ ratingAvg: 5.0 }),
    );
  });

  it("DENIES smuggling an aggregate change into a content edit", async () => {
    await assertFails(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-rated")
        .update({ name: "Renombrada", ratingsCount: 999 }),
    );
  });

  it("ALLOWS a content edit on a template that carries CF aggregates (hasOnly regression)", async () => {
    // request.resource.data is the POST-state: it includes the CF-written
    // ratingAvg/ratingsCount. Without them in the keys().hasOnly allowlist
    // of UPDATE path 4, every content edit on a rated template would fail.
    await assertSucceeds(
      asUser(TRAINER_A).collection("routines").doc("tpl-rated").update({
        name: "Plantilla PPL v2",
        split: "PPL",
        level: "beginner",
        days: [],
        numWeeks: 2,
      }),
    );
  });

  it("ALLOWS publish/unpublish on a template that carries CF aggregates", async () => {
    await assertSucceeds(
      asUser(TRAINER_A)
        .collection("routines")
        .doc("tpl-rated")
        .update({ visibility: "private" }),
    );
  });
});

// ---------------------------------------------------------------------------
// 4. Ratings subcollection — create
// ---------------------------------------------------------------------------
describe("ratings create", () => {
  const rate = (
    uid: string,
    routineId: string,
    payload: Record<string, unknown>,
  ) =>
    asUser(uid)
      .collection("routines")
      .doc(routineId)
      .collection("ratings")
      .doc(uid)
      .set(payload);

  it("ALLOWS a user rating a published template (full payload)", async () => {
    await assertSucceeds(
      rate(RATER, "tpl-public", ratingPayload(RATER, { comment: "Muy buena" })),
    );
  });

  it("ALLOWS a rating with a null comment (client wire shape)", async () => {
    await assertSucceeds(rate(RATER, "tpl-public", ratingPayload(RATER)));
  });

  it("ALLOWS a 500-char comment (boundary)", async () => {
    await assertSucceeds(
      rate(
        RATER,
        "tpl-public",
        ratingPayload(RATER, { comment: "x".repeat(500) }),
      ),
    );
  });

  it("DENIES a 501-char comment", async () => {
    await assertFails(
      rate(
        RATER,
        "tpl-public",
        ratingPayload(RATER, { comment: "x".repeat(501) }),
      ),
    );
  });

  it("DENIES rating 0, 6 and non-integer ratings", async () => {
    await assertFails(
      rate(RATER, "tpl-public", ratingPayload(RATER, { rating: 0 })),
    );
    await assertFails(
      rate(RATER, "tpl-public", ratingPayload(RATER, { rating: 6 })),
    );
    await assertFails(
      rate(RATER, "tpl-public", ratingPayload(RATER, { rating: 4.5 })),
    );
  });

  it("DENIES writing under another user's doc id", async () => {
    await assertFails(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc("someone-else")
        .set(ratingPayload("someone-else")),
    );
  });

  it("DENIES a userId body field that mismatches the doc id", async () => {
    await assertFails(
      rate(RATER, "tpl-public", ratingPayload(RATER, { userId: "spoofed" })),
    );
  });

  it("DENIES the template author rating their own work", async () => {
    await assertFails(
      rate(TRAINER_A, "tpl-public", ratingPayload(TRAINER_A)),
    );
  });

  it("DENIES rating a PRIVATE template", async () => {
    await assertFails(rate(RATER, "tpl-private", ratingPayload(RATER)));
  });

  it("DENIES rating a public user-created routine (not a trainer template)", async () => {
    await assertFails(rate(RATER, "user-pub", ratingPayload(RATER)));
  });

  it("DENIES rating a nonexistent routine", async () => {
    await assertFails(rate(RATER, "no-such-routine", ratingPayload(RATER)));
  });

  it("DENIES extra keys in the payload", async () => {
    await assertFails(
      rate(
        RATER,
        "tpl-public",
        ratingPayload(RATER, { boost: true }),
      ),
    );
  });

  it("DENIES a payload missing the timestamps", async () => {
    await assertFails(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set({ userId: RATER, rating: 4 }),
    );
  });
});

// ---------------------------------------------------------------------------
// 5. Ratings subcollection — update / delete / read
// ---------------------------------------------------------------------------
describe("ratings update, delete and read", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set(ratingPayload(RATER, { comment: "Original" }));
    });
  });

  it("ALLOWS the rater editing their own rating (createdAt pinned)", async () => {
    await assertSucceeds(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set(
          ratingPayload(RATER, {
            rating: 2,
            comment: "Cambié de opinión",
            updatedAt: new Date(5000),
          }),
        ),
    );
  });

  it("DENIES rewriting createdAt on edit", async () => {
    await assertFails(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set(ratingPayload(RATER, { createdAt: new Date(9999) })),
    );
  });

  it("DENIES editing someone else's rating", async () => {
    await assertFails(
      asUser(ATHLETE)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set(ratingPayload(RATER, { rating: 1 })),
    );
  });

  it("DENIES editing a rating after the template was unpublished", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("routines")
        .doc("tpl-public")
        .update({ visibility: "private" });
    });

    await assertFails(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .set(ratingPayload(RATER, { rating: 1 })),
    );
  });

  it("DENIES deleting a rating (even one's own)", async () => {
    await assertFails(
      asUser(RATER)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .doc(RATER)
        .delete(),
    );
  });

  it("ALLOWS any authenticated user to read/list ratings", async () => {
    await assertSucceeds(
      asUser(ATHLETE)
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .get(),
    );
  });

  it("DENIES unauthenticated reads of ratings", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("routines")
        .doc("tpl-public")
        .collection("ratings")
        .get(),
    );
  });
});
