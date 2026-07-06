/**
 * Integration tests for the rankingAggregate Cloud Functions.
 *
 * Tests run against the Firebase Local Emulator (Firestore).
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered (design `sdd/rankings-integrity/design` AD-1, AD-2, AD-7):
 *   first-finish recompute        — one qualifying session -> metrics written
 *   second-session recompute      — two qualifying sessions -> volumes sum
 *   idempotent re-fire            — identical data -> identical output
 *   forged-value overwrite        — stored forged value is overwritten by recompute
 *   no-op if profile absent       — resolves without throwing, writes nothing
 *   opt-out gating                — rankingOptIn:false -> metrics written as 0/null
 *   Trigger A wiring              — rankingAggregateOnSession exported/invocable
 *   Trigger B loop-prevention     — single-write termination on optIn false->true
 *   no-session opt-in             — just-opted-in athlete with 0 sessions -> 0/null
 *
 * REQ traceability: `gym-rankings: Metric Authority`, `gym-rankings: Opt-In
 * Enable`, `gym-rankings: Session Finish`. AD-1 (two-trigger topology, loop
 * termination via transition-equality guard).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "ranking-aggregate-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists (RED)
import {
  recomputeMetrics,
  shouldRecomputeOnOptInTransition,
  rankingAggregateOnSession,
  rankingAggregateOnOptIn,
} from "../ranking-aggregate";

const db = () => admin.firestore(testApp);

const COL_USERS = "users";
const COL_PROFILES = "userPublicProfiles";

type SetLogSeed = {
  exerciseId: string;
  weightKg: number;
};

async function seedProfile(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  await db().collection(COL_PROFILES).doc(uid).set({ uid, ...data });
}

async function seedSession(
  uid: string,
  sessionId: string,
  opts: {
    startedAt: Date;
    status?: string;
    wasFullyCompleted?: boolean;
    totalVolumeKg?: number;
    setLogs?: SetLogSeed[];
  },
): Promise<void> {
  const sessionRef = db()
    .collection(COL_USERS)
    .doc(uid)
    .collection("sessions")
    .doc(sessionId);
  await sessionRef.set({
    id: sessionId,
    uid,
    startedAt: admin.firestore.Timestamp.fromDate(opts.startedAt),
    status: opts.status ?? "finished",
    wasFullyCompleted: opts.wasFullyCompleted ?? true,
    totalVolumeKg: opts.totalVolumeKg ?? 0,
  });

  const logs = opts.setLogs ?? [];
  for (let i = 0; i < logs.length; i++) {
    await sessionRef.collection("setLogs").doc(`log-${i}`).set({
      id: `log-${i}`,
      exerciseId: logs[i].exerciseId,
      exerciseName: logs[i].exerciseId,
      setNumber: i + 1,
      reps: 5,
      weightKg: logs[i].weightKg,
      completedAt: admin.firestore.Timestamp.fromDate(opts.startedAt),
    });
  }
}

async function getProfile(
  uid: string,
): Promise<admin.firestore.DocumentData | undefined> {
  const snap = await db().collection(COL_PROFILES).doc(uid).get();
  return snap.exists ? snap.data() : undefined;
}

async function cleanup(uid: string): Promise<void> {
  await db()
    .recursiveDelete(db().collection(COL_USERS).doc(uid))
    .catch(() => undefined);
  await db()
    .collection(COL_PROFILES)
    .doc(uid)
    .delete()
    .catch(() => undefined);
}

// ---------------------------------------------------------------------------
// first-finish recompute
// ---------------------------------------------------------------------------
describe("recomputeMetrics: first-finish recompute", () => {
  const uid = "athlete-ra-first-finish";

  afterEach(() => cleanup(uid));

  it("writes lifetimeVolumeKg and bestSquatKg from a single qualifying session", async () => {
    await seedProfile(uid, { rankingOptIn: true });
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 120 }],
    });

    await recomputeMetrics(testApp, uid);

    const profile = await getProfile(uid);
    expect(profile?.lifetimeVolumeKg).toBe(600);
    expect(profile?.bestSquatKg).toBe(120);
  });
});

// ---------------------------------------------------------------------------
// second-session recompute
// ---------------------------------------------------------------------------
describe("recomputeMetrics: second-session recompute", () => {
  const uid = "athlete-ra-second-session";

  afterEach(() => cleanup(uid));

  it("sums totalVolumeKg across two qualifying sessions", async () => {
    await seedProfile(uid, { rankingOptIn: true });
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 100 }],
    });
    await seedSession(uid, "s2", {
      startedAt: new Date("2026-02-01T08:00:00Z"),
      totalVolumeKg: 400,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 110 }],
    });

    await recomputeMetrics(testApp, uid);

    const profile = await getProfile(uid);
    expect(profile?.lifetimeVolumeKg).toBe(1000);
    expect(profile?.bestSquatKg).toBe(110);
  });
});

// ---------------------------------------------------------------------------
// idempotent re-fire
// ---------------------------------------------------------------------------
describe("recomputeMetrics: idempotent re-fire", () => {
  const uid = "athlete-ra-idempotent";

  afterEach(() => cleanup(uid));

  it("yields identical output when called twice with identical underlying data", async () => {
    await seedProfile(uid, { rankingOptIn: true });
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 120 }],
    });

    await recomputeMetrics(testApp, uid);
    const first = await getProfile(uid);
    await recomputeMetrics(testApp, uid);
    const second = await getProfile(uid);

    expect(second?.lifetimeVolumeKg).toBe(first?.lifetimeVolumeKg);
    expect(second?.bestSquatKg).toBe(first?.bestSquatKg);
    expect(second?.lifetimeVolumeKg).toBe(600);
    expect(second?.bestSquatKg).toBe(120);
  });
});

// ---------------------------------------------------------------------------
// forged-value overwrite — the core security assertion of the whole change
// ---------------------------------------------------------------------------
describe("recomputeMetrics: forged-value overwrite", () => {
  const uid = "athlete-ra-forged";

  afterEach(() => cleanup(uid));

  it("overwrites a forged stored bestSquatKg with the value derived from real sessions", async () => {
    // Simulates a pre-rules-hardening forged write.
    await seedProfile(uid, { rankingOptIn: true, bestSquatKg: 999 });
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 110 }],
    });

    await recomputeMetrics(testApp, uid);

    const profile = await getProfile(uid);
    expect(profile?.bestSquatKg).toBe(110);
    expect(profile?.bestSquatKg).not.toBe(999);
  });
});

// ---------------------------------------------------------------------------
// no-op if profile absent
// ---------------------------------------------------------------------------
describe("recomputeMetrics: no-op if profile absent", () => {
  const uid = "athlete-ra-no-profile";

  afterEach(() => cleanup(uid));

  it("resolves without throwing and writes nothing when userPublicProfiles doc is absent", async () => {
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 110 }],
    });

    await expect(recomputeMetrics(testApp, uid)).resolves.not.toThrow();

    const profile = await getProfile(uid);
    expect(profile).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// opt-out gating
// ---------------------------------------------------------------------------
describe("recomputeMetrics: opt-out gating", () => {
  const uid = "athlete-ra-opt-out";

  afterEach(() => cleanup(uid));

  it("writes metrics as 0/null when rankingOptIn is false, even with real qualifying sessions", async () => {
    await seedProfile(uid, { rankingOptIn: false });
    await seedSession(uid, "s1", {
      startedAt: new Date("2026-01-10T08:00:00Z"),
      totalVolumeKg: 600,
      setLogs: [{ exerciseId: "squat-barra", weightKg: 110 }],
    });

    await recomputeMetrics(testApp, uid);

    const profile = await getProfile(uid);
    expect(profile?.lifetimeVolumeKg).toBe(0);
    expect(profile?.bestSquatKg ?? null).toBeNull();
    expect(profile?.bestBenchKg ?? null).toBeNull();
    expect(profile?.bestDeadliftKg ?? null).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Trigger A wiring
// ---------------------------------------------------------------------------
describe("rankingAggregateOnSession: exported and invocable", () => {
  it("exports rankingAggregateOnSession as a function", () => {
    expect(rankingAggregateOnSession).toBeDefined();
    expect(typeof rankingAggregateOnSession).toBe("function");
  });
});

// ---------------------------------------------------------------------------
// Trigger B loop-prevention / single-write termination — AD-1, the
// load-bearing test: the transition-equality guard MUST short-circuit any
// re-fire caused by recomputeMetrics's own merge write.
// ---------------------------------------------------------------------------
describe("shouldRecomputeOnOptInTransition: AD-1 transition guard", () => {
  it("returns true on a false -> true transition (the enable event)", () => {
    expect(
      shouldRecomputeOnOptInTransition(
        { rankingOptIn: false },
        { rankingOptIn: true },
      ),
    ).toBe(true);
  });

  it("returns true on an absent -> true transition (first-ever opt-in write)", () => {
    expect(
      shouldRecomputeOnOptInTransition(undefined, { rankingOptIn: true }),
    ).toBe(true);
  });

  it("returns false on re-fire (before/after both true) — loop-termination", () => {
    // The re-fire caused by recomputeMetrics's own merge write: before and
    // after both have rankingOptIn:true, so the guard short-circuits.
    expect(
      shouldRecomputeOnOptInTransition(
        { rankingOptIn: true },
        { rankingOptIn: true },
      ),
    ).toBe(false);
  });

  it("returns false on a true -> false transition (disable)", () => {
    expect(
      shouldRecomputeOnOptInTransition(
        { rankingOptIn: true },
        { rankingOptIn: false },
      ),
    ).toBe(false);
  });

  it("returns false when after is undefined (delete)", () => {
    expect(
      shouldRecomputeOnOptInTransition({ rankingOptIn: true }, undefined),
    ).toBe(false);
  });

  it("exports rankingAggregateOnOptIn as a function", () => {
    expect(rankingAggregateOnOptIn).toBeDefined();
    expect(typeof rankingAggregateOnOptIn).toBe("function");
  });
});

// ---------------------------------------------------------------------------
// no-session opt-in — a just-opted-in athlete with zero qualifying sessions
// ends up with lifetimeVolumeKg:0 / best*Kg:null, never stale or forged.
// ---------------------------------------------------------------------------
describe("recomputeMetrics: no-session opt-in", () => {
  const uid = "athlete-ra-no-session-optin";

  afterEach(() => cleanup(uid));

  it("writes lifetimeVolumeKg:0 and best*Kg:null for an opted-in athlete with zero qualifying sessions", async () => {
    await seedProfile(uid, { rankingOptIn: true });

    await recomputeMetrics(testApp, uid);

    const profile = await getProfile(uid);
    expect(profile?.lifetimeVolumeKg).toBe(0);
    expect(profile?.bestSquatKg ?? null).toBeNull();
    expect(profile?.bestBenchKg ?? null).toBeNull();
    expect(profile?.bestDeadliftKg ?? null).toBeNull();
  });
});
