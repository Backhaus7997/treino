/**
 * Rules tests for the three TRAINER-PRIVATE collections that hold data ABOUT
 * an athlete but are never shown to them: `athlete_files`, `follow_up_entries`
 * and `nutrition_plans`.
 *
 * WHY THIS FILE EXISTS
 * The rules-coverage matrix (docs/security.md, #680 Slice A) measured the
 * negative-test coverage of every collection in `firestore.rules`. These three
 * had **zero** negative tests — no test anywhere asserted the single privacy
 * claim their rule comments make: "el alumno NUNCA lee estos archivos".
 * They are the highest-value gap in the matrix because the data is
 * third-party (the PF writing about a person who cannot see it) and the doc
 * ids are DETERMINISTIC and enumerable — `{trainerId}_{athleteId}[_{ts}]` —
 * so a wrong rule is exploitable by anyone who knows two uids, and
 * `userPublicProfiles` is world-readable.
 *
 * WHAT IS ASSERTED, per collection:
 *   1. the subject athlete cannot get/list/delete their own dossier;
 *   2. an unrelated trainer cannot get/list it either (no fishing by docId);
 *   3. the identity fields (trainerId/athleteId) cannot be forged on create
 *      nor reassigned on update (the squat/hijack pair already fixed for
 *      `athlete_notes` in QA-2026-07-30 C1 — same idiom, never tested here);
 *   4. `athlete_files` update is `if false` and stays that way.
 * Every describe also carries the matching POSITIVE for the owner trainer, so
 * a rule that denied EVERYTHING could not turn this suite green.
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
const PROJECT_ID = "treino-rules-test-coachpriv";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_FILES = "athlete_files";
const COL_FOLLOWUP = "follow_up_entries";
const COL_NUTRITION = "nutrition_plans";

const TRAINER = "trainer-coachpriv";
const OTHER_TRAINER = "other-trainer-coachpriv";
const ATHLETE = "athlete-coachpriv";

const TEN_MB = 10 * 1024 * 1024;

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

/** Writes a doc bypassing rules, so read/update/delete tests start from a real doc. */
async function seedDoc(
  col: string,
  docId: string,
  data: Record<string, unknown>,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(col).doc(docId).set(data);
  });
}

// ─── Fixtures ────────────────────────────────────────────────────────────────
// Shapes mirror the freezed models' toJson():
//   AthleteFile   (lib/features/coach/domain/athlete_file.dart)
//   FollowUpEntry (lib/features/coach/domain/follow_up_entry.dart)
//   NutritionPlan (lib/features/coach/domain/nutrition_plan.dart)
// None of the three rules uses keys().hasOnly(), so the fixtures stay at the
// real model shape rather than a minimal one — a test that writes less than
// the app writes proves less than it looks like it does.

const FILE_ID = `${TRAINER}_${ATHLETE}_1700000000000`;

function fileDoc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: FILE_ID,
    trainerId: TRAINER,
    athleteId: ATHLETE,
    fileName: "plan-nutricional.pdf",
    kind: "pdf",
    contentType: "application/pdf",
    sizeBytes: 512 * 1024,
    storagePath: `athleteFiles/${TRAINER}_${ATHLETE}/1700000000000.pdf`,
    downloadUrl: "https://example.test/f.pdf?token=abc",
    uploadedAt: new Date(),
    ...overrides,
  };
}

const ENTRY_ID = `${TRAINER}_${ATHLETE}_1700000000001`;

function entryDoc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: ENTRY_ID,
    trainerId: TRAINER,
    athleteId: ATHLETE,
    text: "Volvió de la lesión, arrancamos con carga baja.",
    tag: "general",
    recordedAt: new Date("2026-08-01T10:00:00Z"),
    ...overrides,
  };
}

const PLAN_ID = `${TRAINER}_${ATHLETE}`;

function planDoc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: PLAN_ID,
    trainerId: TRAINER,
    athleteId: ATHLETE,
    title: "Plan de volumen",
    meals: [{ name: "Desayuno", groups: [] }],
    updatedAt: new Date(),
    ...overrides,
  };
}

// ─────────────────────────────────────────────────────────────────────────────

describe("athlete_files — trainer-only dossier the athlete never sees", () => {
  describe("read / list", () => {
    beforeEach(async () => {
      await seedDoc(COL_FILES, FILE_ID, fileDoc());
    });

    it("allows the owner trainer to read their own file doc", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FILES).doc(FILE_ID).get(),
      );
    });

    it("allows the owner trainer to list their own files", async () => {
      await assertSucceeds(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .where("trainerId", "==", TRAINER)
          .get(),
      );
    });

    it("DENIES the subject athlete reading the file about them", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_FILES).doc(FILE_ID).get(),
      );
    });

    it("DENIES the subject athlete listing the files about them", async () => {
      await assertFails(
        ctxDb(ATHLETE)
          .collection(COL_FILES)
          .where("athleteId", "==", ATHLETE)
          .get(),
      );
    });

    it("DENIES another trainer reading the doc by its enumerable id", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(COL_FILES).doc(FILE_ID).get(),
      );
    });

    it("DENIES another trainer fishing the athlete's files by athleteId", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_FILES)
          .where("athleteId", "==", ATHLETE)
          .get(),
      );
    });

    it("DENIES an unauthenticated caller", async () => {
      await assertFails(
        testEnv
          .unauthenticatedContext()
          .firestore()
          .collection(COL_FILES)
          .doc(FILE_ID)
          .get(),
      );
    });
  });

  describe("create", () => {
    it("allows the trainer to create a file doc naming themselves", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FILES).doc(FILE_ID).set(fileDoc()),
      );
    });

    it("DENIES planting a doc that names ANOTHER trainer as owner", async () => {
      // Squat vector: the attacker writes into the victim PF's namespace.
      // Denied because trainerId must equal the signing uid.
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set(fileDoc()),
      );
    });

    it("DENIES the athlete forging a file doc about themselves", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_FILES).doc(FILE_ID).set(fileDoc()),
      );
    });

    it("DENIES a file above the 10 MB cap", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set(fileDoc({ sizeBytes: TEN_MB + 1 })),
      );
    });

    it("DENIES a zero-byte / non-int sizeBytes", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set(fileDoc({ sizeBytes: 0 })),
      );
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set(fileDoc({ sizeBytes: "512" })),
      );
    });

    it("DENIES an empty athleteId (unaddressed dossier)", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set(fileDoc({ athleteId: "" })),
      );
    });
  });

  describe("update — deliberately closed (`allow update: if false`)", () => {
    beforeEach(async () => {
      await seedDoc(COL_FILES, FILE_ID, fileDoc());
    });

    it("DENIES even the owner trainer updating the doc", async () => {
      // Replacement is delete-then-upload, so downloadUrl can never drift
      // away from storagePath.
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .update({ fileName: "otro-nombre.pdf" }),
      );
    });

    it("DENIES a third party reassigning trainerId (read-gate hijack)", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_FILES)
          .doc(FILE_ID)
          .set({ trainerId: OTHER_TRAINER }, { merge: true }),
      );
    });
  });

  describe("delete", () => {
    beforeEach(async () => {
      await seedDoc(COL_FILES, FILE_ID, fileDoc());
    });

    it("allows the owner trainer to delete their own file doc", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FILES).doc(FILE_ID).delete(),
      );
    });

    it("DENIES the subject athlete deleting it", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_FILES).doc(FILE_ID).delete(),
      );
    });

    it("DENIES another trainer deleting it", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(COL_FILES).doc(FILE_ID).delete(),
      );
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────

describe("follow_up_entries — the PF's private log about an athlete", () => {
  describe("read / list", () => {
    beforeEach(async () => {
      await seedDoc(COL_FOLLOWUP, ENTRY_ID, entryDoc());
    });

    it("allows the owner trainer to read their own entry", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FOLLOWUP).doc(ENTRY_ID).get(),
      );
    });

    it("DENIES the subject athlete reading what the PF wrote about them", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_FOLLOWUP).doc(ENTRY_ID).get(),
      );
    });

    it("DENIES the subject athlete listing the entries about them", async () => {
      await assertFails(
        ctxDb(ATHLETE)
          .collection(COL_FOLLOWUP)
          .where("athleteId", "==", ATHLETE)
          .get(),
      );
    });

    it("DENIES another trainer reading the entry", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(COL_FOLLOWUP).doc(ENTRY_ID).get(),
      );
    });
  });

  describe("create", () => {
    it("allows the trainer to log an entry naming themselves", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FOLLOWUP).doc(ENTRY_ID).set(entryDoc()),
      );
    });

    it("DENIES planting an entry in ANOTHER trainer's name", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc()),
      );
    });

    it("DENIES an empty text body", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ text: "" })),
      );
    });

    it("DENIES an unbounded text blob (>= 5000 chars)", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ text: "x".repeat(5000) })),
      );
    });
  });

  describe("update — identity and timestamp pinned to the pre-image", () => {
    beforeEach(async () => {
      await seedDoc(COL_FOLLOWUP, ENTRY_ID, entryDoc());
    });

    it("allows the owner trainer to edit the text and tag", async () => {
      await assertSucceeds(
        ctxDb(TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ text: "Corregido: carga media.", tag: "lesion" })),
      );
    });

    it("DENIES a third party hijacking trainerId to unlock the read gate", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ trainerId: OTHER_TRAINER })),
      );
    });

    it("DENIES the owner reassigning the entry to another athlete", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ athleteId: "otro-alumno" })),
      );
    });

    it("DENIES moving recordedAt (the log is chronological evidence)", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_FOLLOWUP)
          .doc(ENTRY_ID)
          .set(entryDoc({ recordedAt: new Date("2020-01-01T00:00:00Z") })),
      );
    });
  });

  describe("delete", () => {
    beforeEach(async () => {
      await seedDoc(COL_FOLLOWUP, ENTRY_ID, entryDoc());
    });

    it("allows the owner trainer to delete their own entry", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_FOLLOWUP).doc(ENTRY_ID).delete(),
      );
    });

    it("DENIES the subject athlete deleting the entry about them", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_FOLLOWUP).doc(ENTRY_ID).delete(),
      );
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────

describe("nutrition_plans — one plan per PF↔athlete pair, trainer-only", () => {
  describe("read / list", () => {
    beforeEach(async () => {
      await seedDoc(COL_NUTRITION, PLAN_ID, planDoc());
    });

    it("allows the owner trainer to read the plan", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_NUTRITION).doc(PLAN_ID).get(),
      );
    });

    it("DENIES the subject athlete reading their own plan doc", async () => {
      // Deliberate today: the athlete surface is a separate, unshipped
      // feature. If that changes, this test is the one that must change WITH
      // the rule — not silently drift.
      await assertFails(
        ctxDb(ATHLETE).collection(COL_NUTRITION).doc(PLAN_ID).get(),
      );
    });

    it("DENIES another trainer reading the pair's plan", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(COL_NUTRITION).doc(PLAN_ID).get(),
      );
    });

    it("DENIES another trainer fishing plans by athleteId", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_NUTRITION)
          .where("athleteId", "==", ATHLETE)
          .get(),
      );
    });
  });

  describe("create", () => {
    it("allows the trainer to create the pair's plan", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_NUTRITION).doc(PLAN_ID).set(planDoc()),
      );
    });

    it("DENIES planting a plan in ANOTHER trainer's name", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc()),
      );
    });

    it("DENIES a non-list meals field", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc({ meals: "desayuno, almuerzo" })),
      );
    });

    it("DENIES a title over the 200-char bound", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc({ title: "t".repeat(200) })),
      );
    });
  });

  describe("update", () => {
    beforeEach(async () => {
      await seedDoc(COL_NUTRITION, PLAN_ID, planDoc());
    });

    it("allows the owner trainer to edit the plan", async () => {
      await assertSucceeds(
        ctxDb(TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc({ title: "Plan de definición" })),
      );
    });

    it("DENIES a third party hijacking trainerId on the pair's plan", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc({ trainerId: OTHER_TRAINER })),
      );
    });

    it("DENIES reassigning the plan to another athlete", async () => {
      await assertFails(
        ctxDb(TRAINER)
          .collection(COL_NUTRITION)
          .doc(PLAN_ID)
          .set(planDoc({ athleteId: "otro-alumno" })),
      );
    });
  });

  describe("delete", () => {
    beforeEach(async () => {
      await seedDoc(COL_NUTRITION, PLAN_ID, planDoc());
    });

    it("allows the owner trainer to delete the plan", async () => {
      await assertSucceeds(
        ctxDb(TRAINER).collection(COL_NUTRITION).doc(PLAN_ID).delete(),
      );
    });

    it("DENIES the subject athlete deleting the plan", async () => {
      await assertFails(
        ctxDb(ATHLETE).collection(COL_NUTRITION).doc(PLAN_ID).delete(),
      );
    });

    it("DENIES another trainer deleting the plan", async () => {
      await assertFails(
        ctxDb(OTHER_TRAINER).collection(COL_NUTRITION).doc(PLAN_ID).delete(),
      );
    });
  });
});
