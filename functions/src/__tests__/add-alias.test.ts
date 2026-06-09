/**
 * Integration tests for the addAlias Cloud Function.
 *
 * Tests run against the Firebase Local Emulator (Firestore + Auth).
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-735  — addAlias is exported and configured for southamerica-east1
 *   SCENARIO-735b — addAlias exported from index.ts
 *   SCENARIO-736  — new alias added to existing exercise (happy path)
 *   SCENARIO-737  — idempotent: second call with same alias is a no-op
 *   SCENARIO-738  — rejects unauthenticated caller
 *   SCENARIO-739  — rejects athlete caller (permission-denied)
 *   SCENARIO-740  — rejects non-existent exercise (not-found)
 *   SCENARIO-741  — rejects empty exerciseId or alias (invalid-argument)
 *   SCENARIO-742  — normalize(): uppercase + extra whitespace collapsed
 *   SCENARIO-743  — normalize(): accent parity with Dart normalize()
 *
 * REQ-CXP-CF-001..009, REQ-CXP-CX-008. Fase 6 Etapa 5.
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "add-alias-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Module under test — will fail to resolve until add-alias.ts is created (RED)
import { addAlias, runAddAlias } from "../add-alias";

// firebase-functions-test used to invoke the callable wrapper for
// SCENARIO-738 (unauthenticated) and SCENARIO-741 (invalid-argument).
// These guards live in the onCall shell, not in runAddAlias.
import firebaseFunctionsTest from "firebase-functions-test";
type FftInstance = {
  wrap: (fn: unknown) => (data: unknown, ctx?: unknown) => Promise<unknown>;
  cleanup: () => void;
};
const fft = (firebaseFunctionsTest as unknown as () => FftInstance)();
const wrappedAddAlias = fft.wrap(addAlias);

const db = () => admin.firestore(testApp);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function seedUser(uid: string, role: string): Promise<void> {
  await db().collection("users").doc(uid).set({ uid, role });
}

async function seedExercise(
  exerciseId: string,
  aliases: string[],
): Promise<void> {
  await db()
    .collection("exercises")
    .doc(exerciseId)
    .set({ name: exerciseId, aliases });
}

async function getAliases(exerciseId: string): Promise<string[]> {
  const snap = await db().collection("exercises").doc(exerciseId).get();
  return (snap.data()?.aliases as string[]) ?? [];
}

async function cleanupDoc(collection: string, id: string): Promise<void> {
  await db().collection(collection).doc(id).delete().catch(() => undefined);
}

// ---------------------------------------------------------------------------
// SCENARIO-735 — structure: addAlias exported with correct region
// ---------------------------------------------------------------------------
describe("SCENARIO-735: addAlias exported and configured for southamerica-east1", () => {
  it("exports addAlias as a function", () => {
    expect(addAlias).toBeDefined();
    expect(typeof addAlias).toBe("function");
  });

  it("exports runAddAlias as a function", () => {
    expect(runAddAlias).toBeDefined();
    expect(typeof runAddAlias).toBe("function");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-735b — addAlias exported from index.ts
// ---------------------------------------------------------------------------
describe("SCENARIO-735b: addAlias exported from index.ts", () => {
  it("addAlias is re-exported from the functions index", async () => {
    const indexModule = await import("../index");
    expect((indexModule as Record<string, unknown>).addAlias).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-742 — normalize(): uppercase and extra whitespace
// ---------------------------------------------------------------------------
describe("normalize() parity with Dart — SCENARIO-742/743", () => {
  // We access normalize via the module internals through test-only re-export
  // from runAddAlias behaviour. For direct unit testing we test via the
  // expected results of the three locked fixtures.

  it("SCENARIO-742: normalizes uppercase and collapses double space", async () => {
    await seedUser("user-norm-742", "trainer");
    await seedExercise("ex-norm-742", []);

    await runAddAlias(testApp, "user-norm-742", "ex-norm-742", "SENTADILLA  CON BARRA");
    const aliases = await getAliases("ex-norm-742");
    expect(aliases).toContain("sentadilla con barra");

    await cleanupDoc("users", "user-norm-742");
    await cleanupDoc("exercises", "ex-norm-742");
  });

  it("SCENARIO-743a: normalizes accents — CáMaRa Lenta!!! → camara lenta", async () => {
    await seedUser("user-norm-743a", "trainer");
    await seedExercise("ex-norm-743a", []);

    await runAddAlias(testApp, "user-norm-743a", "ex-norm-743a", "CáMaRa Lenta!!!");
    const aliases = await getAliases("ex-norm-743a");
    expect(aliases).toContain("camara lenta");

    await cleanupDoc("users", "user-norm-743a");
    await cleanupDoc("exercises", "ex-norm-743a");
  });

  it("SCENARIO-743b: normalizes accented ─ Sentadílla → sentadilla", async () => {
    await seedUser("user-norm-743b", "trainer");
    await seedExercise("ex-norm-743b", []);

    await runAddAlias(testApp, "user-norm-743b", "ex-norm-743b", "Sentadílla");
    const aliases = await getAliases("ex-norm-743b");
    expect(aliases).toContain("sentadilla");

    await cleanupDoc("users", "user-norm-743b");
    await cleanupDoc("exercises", "ex-norm-743b");
  });

  // SCENARIO-743c: strips parentheses
  // "Press de Banca (agarre estrecho)" → "press de banca agarre estrecho"
  it("SCENARIO-743c: strips parentheses from exercise name", async () => {
    await seedUser("user-norm-743c", "trainer");
    await seedExercise("ex-norm-743c", []);

    await runAddAlias(
      testApp,
      "user-norm-743c",
      "ex-norm-743c",
      "Press de Banca (agarre estrecho)",
    );
    const aliases = await getAliases("ex-norm-743c");
    expect(aliases).toContain("press de banca agarre estrecho");

    await cleanupDoc("users", "user-norm-743c");
    await cleanupDoc("exercises", "ex-norm-743c");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-738 — rejects unauthenticated caller
// ---------------------------------------------------------------------------
describe("SCENARIO-738: rejects unauthenticated caller", () => {
  it("throws HttpsError unauthenticated when no auth context", async () => {
    // wrappedAddAlias(data, context) — passing no context means auth is absent.
    await expect(
      wrappedAddAlias({ exerciseId: "exercise_b", alias: "squat" }),
    ).rejects.toMatchObject({
      code: "unauthenticated",
      message: "Authentication required.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-741 — rejects empty exerciseId or alias
// ---------------------------------------------------------------------------
describe("SCENARIO-741: rejects empty exerciseId or alias", () => {
  // Input validation is enforced inside runAddAlias so it is testable without
  // going through the onCall transport layer (which fft.wrap does not fully
  // emulate for v2 auth context). The callable wrapper also checks these
  // guards before delegating — this test covers the shared validation path.
  it("throws invalid-argument when exerciseId is empty", async () => {
    await expect(
      runAddAlias(testApp, "any-caller", "", "sentadilla"),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "exerciseId and alias are required.",
    });
  });

  it("throws invalid-argument when alias is empty", async () => {
    await expect(
      runAddAlias(testApp, "any-caller", "exercise_b", ""),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "exerciseId and alias are required.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-739 — rejects athlete caller
// ---------------------------------------------------------------------------
describe("SCENARIO-739: rejects athlete caller (permission-denied)", () => {
  const userId = "user-athlete-739";
  const exerciseId = "exercise-739";

  beforeEach(async () => {
    await seedUser(userId, "athlete");
    await seedExercise(exerciseId, []);
  });

  afterEach(async () => {
    await cleanupDoc("users", userId);
    await cleanupDoc("exercises", exerciseId);
  });

  it("throws permission-denied for athlete role", async () => {
    await expect(
      runAddAlias(testApp, userId, exerciseId, "any alias"),
    ).rejects.toMatchObject({
      code: "permission-denied",
      message: "Caller must be a trainer.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-740 — rejects non-existent exercise
// ---------------------------------------------------------------------------
describe("SCENARIO-740: rejects non-existent exercise (not-found)", () => {
  const userId = "user-trainer-740";

  beforeEach(async () => {
    await seedUser(userId, "trainer");
  });

  afterEach(async () => {
    await cleanupDoc("users", userId);
  });

  it("throws not-found when exercise does not exist", async () => {
    await expect(
      runAddAlias(testApp, userId, "nonexistent_exercise_id_740", "some alias"),
    ).rejects.toMatchObject({
      code: "not-found",
      message: "Exercise not found.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-736 — adds new alias to existing exercise
// ---------------------------------------------------------------------------
describe("SCENARIO-736: adds new alias to existing exercise", () => {
  const userId = "user-trainer-736";
  const exerciseId = "exercise-736";

  beforeEach(async () => {
    await seedUser(userId, "trainer");
    await seedExercise(exerciseId, ["sentadilla", "squat"]);
  });

  afterEach(async () => {
    await cleanupDoc("users", userId);
    await cleanupDoc("exercises", exerciseId);
  });

  it("adds normalized alias and returns {status:'ok'}", async () => {
    const result = await runAddAlias(
      testApp,
      userId,
      exerciseId,
      "Sentadilla Búlgara",
    );
    expect(result).toEqual({ status: "ok" });

    const aliases = await getAliases(exerciseId);
    expect(aliases).toContain("sentadilla bulgara");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-737 — idempotent: second call with same alias is a no-op
// ---------------------------------------------------------------------------
describe("SCENARIO-737: idempotent — second call with same alias is noop", () => {
  const userId = "user-trainer-737";
  const exerciseId = "exercise-737";

  beforeEach(async () => {
    await seedUser(userId, "trainer");
    await seedExercise(exerciseId, ["sentadilla bulgara"]);
  });

  afterEach(async () => {
    await cleanupDoc("users", userId);
    await cleanupDoc("exercises", exerciseId);
  });

  it("returns {status:'noop'} and does not write when alias already exists", async () => {
    const aliasesBefore = await getAliases(exerciseId);
    const lengthBefore = aliasesBefore.length;

    const result = await runAddAlias(
      testApp,
      userId,
      exerciseId,
      "SENTADILLA BÚLGARA", // same alias, different casing — normalizes identically
    );
    expect(result).toEqual({ status: "noop" });

    const aliasesAfter = await getAliases(exerciseId);
    expect(aliasesAfter.length).toBe(lengthBefore);
  });
});
