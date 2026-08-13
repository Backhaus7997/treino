/**
 * Regression tests for QA #508 — `measurements` and `performance_tests` wrote
 * their value fields completely unvalidated.
 *
 * rules-hardening Slice C added a role gate to both collections (who may
 * write), but nothing ever checked WHAT was written: only `athleteId` and
 * `recordedBy` were validated. A modified client — or a legit athlete
 * self-logging through a patched app — could persist a negative body weight, a
 * string where a number belongs, an unbounded `notes` blob, or arbitrary extra
 * fields. No cross-user escalation (the role/ownership gates still hold), but
 * inconsistent with `payments` / `athlete_billing`, hardened under QA-PAY-007.
 *
 * The fix adds a shape guard to create AND update on both collections:
 * keys().hasOnly() over the exact toJson() key set, a required
 * `recordedAt is timestamp`, and per-field type/range checks.
 *
 * Bounds deliberately MIRROR each screen's own client-side validator rather
 * than inventing physiological ranges — the hole is a client that SKIPS that
 * validator, so the rule enforces what the legit form already enforces:
 *   - measurements:      [0, 500]  (log_measurement_screen.dart, _kMaxMetricValue)
 *   - performance_tests: (0, 100000]  (log_performance_test_screen.dart rejects
 *                        `<= 0` and sets no ceiling; the cap only blocks absurd
 *                        magnitudes)
 *
 * Every test below fails against the pre-fix ruleset: the writes it asserts are
 * DENIED were all accepted before.
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
const PROJECT_ID = "treino-rules-test-qa508";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_MEASUREMENTS = "measurements";
const COL_PERFORMANCE = "performance_tests";
const COL_USERS = "users";

const TRAINER = "trainer-qa508";
const ATHLETE = "athlete-qa508";
const DOC = "doc-qa508";

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

/** Seeds the users doc the trainer branch of both create rules get()s. */
async function seedRole(uid: string, role: "trainer" | "athlete"): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL_USERS).doc(uid).set({ uid, role });
  });
}

/** Writes a doc bypassing rules, so update-path tests start from a valid doc. */
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
// Both models are json_serializable WITHOUT `includeIfNull: false`, so
// toJson() emits EVERY optional key with an explicit null. These fixtures
// reproduce that exact wire shape — a doc with one metric filled and the rest
// present-but-null is the NORMAL save, and the guards must keep accepting it.

/** Full Measurement.toJson() shape (measurement.g.dart). */
function measurementDoc(
  overrides: Record<string, unknown> = {},
  opts: { athleteId?: string; recordedBy?: string; docId?: string } = {},
): Record<string, unknown> {
  return {
    id: opts.docId ?? DOC,
    athleteId: opts.athleteId ?? ATHLETE,
    recordedBy: opts.recordedBy ?? TRAINER,
    recordedAt: new Date(),
    weightKg: null,
    fatPercentage: null,
    muscleMassKg: null,
    shouldersCm: null,
    chestCm: null,
    waistCm: null,
    hipsCm: null,
    glutesCm: null,
    bicepsLCm: null,
    bicepsRCm: null,
    bicepsFlexedLCm: null,
    bicepsFlexedRCm: null,
    forearmLCm: null,
    forearmRCm: null,
    upperThighLCm: null,
    upperThighRCm: null,
    midThighLCm: null,
    midThighRCm: null,
    calfLCm: null,
    calfRCm: null,
    notes: null,
    ...overrides,
  };
}

/** Full PerformanceTest.toJson() shape (performance_test.g.dart). */
function performanceDoc(
  overrides: Record<string, unknown> = {},
  opts: { athleteId?: string; recordedBy?: string; docId?: string } = {},
): Record<string, unknown> {
  return {
    id: opts.docId ?? DOC,
    athleteId: opts.athleteId ?? ATHLETE,
    recordedBy: opts.recordedBy ?? TRAINER,
    recordedAt: new Date(),
    cmjCm: null,
    squatJumpCm: null,
    abalakovCm: null,
    broadJumpCm: null,
    sprint10mS: null,
    sprint20mS: null,
    sprint30mS: null,
    sprint40mS: null,
    squat1rmKg: null,
    benchPress1rmKg: null,
    deadlift1rmKg: null,
    overheadPress1rmKg: null,
    pullUp1rmKg: null,
    vo2maxMlKgMin: null,
    courseNavetteLevel: null,
    cooperMeters: null,
    sitAndReachCm: null,
    notes: null,
    ...overrides,
  };
}

// ─── measurements ────────────────────────────────────────────────────────────

describe("measurements create — QA #508 value validation", () => {
  // Self-log path: no users doc needed, the athlete-self branch short-circuits
  // before the role get(). This is the cheapest route a modified client has.
  const selfOpts = { athleteId: ATHLETE, recordedBy: ATHLETE };
  const selfRef = () => ctxDb(ATHLETE).collection(COL_MEASUREMENTS).doc(DOC);

  it("DENIES a negative weightKg (the issue's repro)", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ weightKg: -80 }, selfOpts)),
    );
  });

  it("DENIES a weightKg above the client's 500 ceiling", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ weightKg: 501 }, selfOpts)),
    );
  });

  it("DENIES a string where a number belongs", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ weightKg: "80" }, selfOpts)),
    );
  });

  it("DENIES a boolean where a number belongs", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ waistCm: true }, selfOpts)),
    );
  });

  it("DENIES an out-of-range circumference", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ bicepsLCm: -1 }, selfOpts)),
    );
  });

  it("DENIES an unbounded notes blob", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ notes: "x".repeat(2001) }, selfOpts)),
    );
  });

  it("DENIES a non-string notes", async () => {
    await assertFails(selfRef().set(measurementDoc({ notes: 42 }, selfOpts)));
  });

  it("DENIES an unknown extra field (hasOnly allowlist)", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ isAdmin: true }, selfOpts)),
    );
  });

  it("DENIES a missing recordedAt", async () => {
    const doc = measurementDoc({}, selfOpts);
    delete doc.recordedAt;
    await assertFails(selfRef().set(doc));
  });

  it("DENIES a non-timestamp recordedAt", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ recordedAt: "2026-07-23" }, selfOpts)),
    );
  });

  it("DENIES a non-string id", async () => {
    await assertFails(selfRef().set(measurementDoc({ id: 12345 }, selfOpts)));
  });

  // `id` is type-checked but NOT pinned to the doc id: _fromDoc rebuilds the
  // model with `{...data, 'id': snap.id}`, so the body copy is never read and
  // pinning it would reject the legitimately id-less docs that
  // scripts/rules_test/measurements-self-log.test.js writes.
  it("allows an id-less doc — the body copy is inert, snap.id wins on read", async () => {
    const doc = measurementDoc({ weightKg: 80 }, selfOpts);
    delete doc.id;
    await assertSucceeds(selfRef().set(doc));
  });

  // ─── legit paths must keep working ─────────────────────────────────────────

  it("allows an athlete self-log with one metric and the rest null", async () => {
    await assertSucceeds(
      selfRef().set(measurementDoc({ weightKg: 82.4 }, selfOpts)),
    );
  });

  it("allows the boundary values 0 and 500 (client validator is inclusive)", async () => {
    await assertSucceeds(
      selfRef().set(
        measurementDoc({ weightKg: 0, waistCm: 500 }, selfOpts),
      ),
    );
  });

  it("allows a notes-only measurement", async () => {
    await assertSucceeds(
      selfRef().set(measurementDoc({ notes: "Post-vacaciones" }, selfOpts)),
    );
  });

  it("allows a trainer to log a full-body measurement for their athlete", async () => {
    await seedRole(TRAINER, "trainer");
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_MEASUREMENTS)
        .doc(DOC)
        .set(
          measurementDoc({
            weightKg: 78.2,
            fatPercentage: 14.5,
            muscleMassKg: 36.1,
            shouldersCm: 122,
            chestCm: 104,
            waistCm: 81,
            hipsCm: 98,
            bicepsLCm: 35.5,
            bicepsRCm: 36,
            calfLCm: 38,
            calfRCm: 38.5,
            notes: "Control mensual",
          }),
        ),
    );
  });
});

describe("measurements update — QA #508 value validation", () => {
  const selfOpts = { athleteId: ATHLETE, recordedBy: ATHLETE };
  const selfRef = () => ctxDb(ATHLETE).collection(COL_MEASUREMENTS).doc(DOC);

  beforeEach(async () => {
    await seedDoc(
      COL_MEASUREMENTS,
      DOC,
      measurementDoc({ weightKg: 80 }, selfOpts),
    );
  });

  it("DENIES an update that poisons a value (repository writes the full doc)", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ weightKg: -80 }, selfOpts)),
    );
  });

  it("DENIES an update that smuggles in an extra field", async () => {
    await assertFails(
      selfRef().set(measurementDoc({ weightKg: 80, role: "trainer" }, selfOpts)),
    );
  });

  it("allows a legit value correction", async () => {
    await assertSucceeds(
      selfRef().set(measurementDoc({ weightKg: 79.5 }, selfOpts)),
    );
  });
});

// ─── performance_tests ───────────────────────────────────────────────────────

describe("performance_tests create — QA #508 value validation", () => {
  // Create is trainer-only here (no athlete-self branch), so every case needs
  // the role doc seeded — otherwise the denial would prove nothing about the
  // new value guard.
  beforeEach(async () => {
    await seedRole(TRAINER, "trainer");
  });

  const ref = () => ctxDb(TRAINER).collection(COL_PERFORMANCE).doc(DOC);

  it("DENIES a negative 1RM", async () => {
    await assertFails(ref().set(performanceDoc({ squat1rmKg: -200 })));
  });

  it("DENIES a zero metric (client validator rejects <= 0)", async () => {
    await assertFails(ref().set(performanceDoc({ sprint10mS: 0 })));
  });

  it("DENIES a negative sitAndReachCm — the app's contract is positive-only", async () => {
    await assertFails(ref().set(performanceDoc({ sitAndReachCm: -5 })));
  });

  it("DENIES an absurd magnitude above the cap", async () => {
    await assertFails(ref().set(performanceDoc({ cooperMeters: 100001 })));
  });

  it("DENIES a string where a number belongs", async () => {
    await assertFails(ref().set(performanceDoc({ deadlift1rmKg: "250" })));
  });

  it("DENIES an unbounded notes blob", async () => {
    await assertFails(ref().set(performanceDoc({ notes: "x".repeat(2001) })));
  });

  it("DENIES an unknown extra field (hasOnly allowlist)", async () => {
    await assertFails(ref().set(performanceDoc({ verified: true })));
  });

  it("DENIES a non-timestamp recordedAt", async () => {
    await assertFails(ref().set(performanceDoc({ recordedAt: 1753228800 })));
  });

  it("DENIES a non-string id", async () => {
    await assertFails(ref().set(performanceDoc({ id: 12345 })));
  });

  it("allows an id-less doc — the body copy is inert, snap.id wins on read", async () => {
    const doc = performanceDoc({ cmjCm: 40 });
    delete doc.id;
    await assertSucceeds(ref().set(doc));
  });

  // ─── legit paths must keep working ─────────────────────────────────────────

  it("allows a trainer to log a realistic evaluation", async () => {
    await assertSucceeds(
      ref().set(
        performanceDoc({
          cmjCm: 42.5,
          squatJumpCm: 38,
          broadJumpCm: 235,
          sprint10mS: 1.78,
          sprint30mS: 4.21,
          squat1rmKg: 180,
          benchPress1rmKg: 120,
          deadlift1rmKg: 220,
          vo2maxMlKgMin: 58.3,
          courseNavetteLevel: 12.5,
          cooperMeters: 3100,
          sitAndReachCm: 8,
          notes: "Evaluación de pretemporada",
        }),
      ),
    );
  });

  it("allows a single-metric evaluation with the rest null", async () => {
    await assertSucceeds(ref().set(performanceDoc({ cmjCm: 40 })));
  });
});

describe("performance_tests update — QA #508 value validation", () => {
  beforeEach(async () => {
    await seedDoc(COL_PERFORMANCE, DOC, performanceDoc({ squat1rmKg: 180 }));
  });

  const ref = () => ctxDb(TRAINER).collection(COL_PERFORMANCE).doc(DOC);

  it("DENIES an update that poisons a value", async () => {
    await assertFails(ref().set(performanceDoc({ squat1rmKg: -1 })));
  });

  it("allows a legit value correction", async () => {
    await assertSucceeds(ref().set(performanceDoc({ squat1rmKg: 185 })));
  });
});
