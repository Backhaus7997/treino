/**
 * Integration tests for generateDuePaymentsHandler Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-VENC-02 — mensual active link → creates correct pending doc with
 *                       deterministic id, periodKey, and last-day dueAt
 *   SCENARIO-VENC-04 — semanal active link → creates correct pending doc with
 *                       YYYY-Www periodKey and Sunday 23:59:59 ART dueAt
 *   SCENARIO-VENC-05 — idempotent re-run on same period → created:0, no dup
 *   SCENARIO-VENC-07 — skip when a PAID doc already covers the period
 *   SCENARIO-VENC-06 — skip when a LEGACY auto-id pending doc covers the period
 *   SCENARIO-VENC-03 — skip porSesion and suelto cadences
 *   SKIP-MISSING-BILLING — skip gracefully when athlete_billing doc absent
 *   REQ-VENC-03 — non-active trainer_link is ignored
 */

import * as admin from "firebase-admin";
import {
  generateDuePaymentsHandler,
  ARG_UTC_OFFSET_MS,
} from "../payments/generate-due-payments";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "generate-due-payments-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

async function seedLink(
  trainerId: string,
  athleteId: string,
  status = "active",
): Promise<void> {
  await db()
    .collection("trainer_links")
    .doc(`${trainerId}_${athleteId}`)
    .set({ trainerId, athleteId, status });
}

async function seedBilling(
  trainerId: string,
  athleteId: string,
  cadence: string,
  amountArs = 10000,
): Promise<void> {
  await db()
    .collection("athlete_billing")
    .doc(`${trainerId}_${athleteId}`)
    .set({ trainerId, athleteId, cadence, amountArs });
}

async function seedPayment(
  docId: string,
  trainerId: string,
  athleteId: string,
  periodKey: string,
  status: string,
): Promise<void> {
  await db().collection("payments").doc(docId).set({
    id: docId,
    trainerId,
    athleteId,
    periodKey,
    status,
    amountArs: 10000,
    concept: "test",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function cleanupDocs(
  ...refs: Array<admin.firestore.DocumentReference>
): Promise<void> {
  for (const ref of refs) {
    await ref.delete().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// SCENARIO-VENC-02 — mensual creates correct pending doc
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-02: mensual active link → creates correct pending doc", () => {
  const trainerId = "trainer-venc-02";
  const athleteId = "athlete-venc-02";
  // Fix now to 2026-07-03 UTC (a day mid-July 2026, ISO week 27)
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0)); // July = month index 6

  const expectedPeriodKey = "2026-07";
  const expectedDocId = `${trainerId}_${athleteId}_${expectedPeriodKey}`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(expectedDocId),
    );
  });

  it("creates a pending payment with correct id, periodKey, status, and last-day dueAt", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "mensual");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(1);
    expect(result.skipped).toBe(0);
    expect(result.scanned).toBe(1);

    const snap = await db().collection("payments").doc(expectedDocId).get();
    expect(snap.exists).toBe(true);

    const data = snap.data()!;
    expect(data.id).toBe(expectedDocId);
    expect(data.trainerId).toBe(trainerId);
    expect(data.athleteId).toBe(athleteId);
    expect(data.periodKey).toBe(expectedPeriodKey);
    expect(data.status).toBe("pending");
    expect(data.concept).toBe("Mensual Julio 2026");

    // dueAt: last day of July 2026 = July 31 23:59:59 ART, expressed as a UTC
    // instant (= Aug 1 02:59:59 UTC). Period boundaries are ART-anchored;
    // + ARG_UTC_OFFSET_MS re-expresses the ART wall-clock end of month in UTC.
    const expectedDueAt = new Date(
      Date.UTC(2026, 7, 0, 23, 59, 59) + ARG_UTC_OFFSET_MS,
    );
    const dueAt = (data.dueAt as admin.firestore.Timestamp).toDate();
    expect(dueAt.getTime()).toBe(expectedDueAt.getTime());
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-04 — semanal creates correct pending doc
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-04: semanal active link → creates correct pending doc", () => {
  const trainerId = "trainer-venc-04";
  const athleteId = "athlete-venc-04";
  // 2026-07-03 is a Friday in ISO week 2026-W27
  // ISO week 27 runs Mon 2026-06-29 to Sun 2026-07-05
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));

  const expectedPeriodKey = "2026-W27";
  const expectedDocId = `${trainerId}_${athleteId}_${expectedPeriodKey}`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(expectedDocId),
    );
  });

  it("creates a pending payment with YYYY-Www periodKey and Sunday 23:59:59 ART dueAt", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "semanal");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(1);

    const snap = await db().collection("payments").doc(expectedDocId).get();
    expect(snap.exists).toBe(true);

    const data = snap.data()!;
    expect(data.periodKey).toBe(expectedPeriodKey);
    expect(data.status).toBe("pending");
    expect(data.concept).toBe("Semana 27");

    // dueAt: Sunday 2026-07-05 23:59:59 ART (= 2026-07-06 02:59:59 UTC), end of
    // ISO week 27. Period boundaries are ART-anchored (Argentina is UTC-3).
    const expectedDueAt = new Date(
      Date.UTC(2026, 6, 5, 23, 59, 59) + ARG_UTC_OFFSET_MS,
    );
    const dueAt = (data.dueAt as admin.firestore.Timestamp).toDate();
    expect(dueAt.getTime()).toBe(expectedDueAt.getTime());
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-05 — idempotent re-run creates no duplicate
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-05: idempotent re-run → created:0", () => {
  const trainerId = "trainer-venc-05";
  const athleteId = "athlete-venc-05";
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));
  const periodKey = "2026-07";
  const docId = `${trainerId}_${athleteId}_${periodKey}`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(docId),
    );
  });

  it("runs twice — second run reports created:0, skipped:1", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "mensual");

    // First run
    await generateDuePaymentsHandler(testApp, now);

    // Second run — must be idempotent
    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.skipped).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-07 — skip when PAID doc covers the period
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-07: paid doc exists → CF skips creation", () => {
  const trainerId = "trainer-venc-07";
  const athleteId = "athlete-venc-07";
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));
  const periodKey = "2026-07";
  const existingDocId = `${trainerId}_${athleteId}_${periodKey}_paid`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(existingDocId),
    );
  });

  it("finds paid doc via field query and skips — created:0, skipped:1", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "mensual");
    // Seed a PAID doc with a legacy auto-id style id (not the deterministic one)
    await seedPayment(existingDocId, trainerId, athleteId, periodKey, "paid");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.skipped).toBe(1);

    // Deterministic doc must NOT have been created
    const det = await db()
      .collection("payments")
      .doc(`${trainerId}_${athleteId}_${periodKey}`)
      .get();
    expect(det.exists).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-06 — skip when LEGACY auto-id pending doc covers the period
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-06: legacy auto-id pending doc → CF skips creation", () => {
  const trainerId = "trainer-venc-06";
  const athleteId = "athlete-venc-06";
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));
  const periodKey = "2026-07";
  const legacyDocId = "legacy-auto-id-venc-06";

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(legacyDocId),
      db().collection("payments").doc(`${trainerId}_${athleteId}_${periodKey}`),
    );
  });

  it("finds legacy pending doc via field query and skips — created:0, skipped:1", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "mensual");
    // Legacy doc: auto-id, but has matching trainerId/athleteId/periodKey
    await seedPayment(legacyDocId, trainerId, athleteId, periodKey, "pending");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.skipped).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-03 — porSesion and suelto cadences are skipped
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-03: porSesion and suelto cadences → skipped", () => {
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));

  afterEach(async () => {
    await db()
      .collection("trainer_links")
      .where("trainerId", "in", [
        "trainer-venc-03a",
        "trainer-venc-03b",
      ])
      .get()
      .then((snap) =>
        Promise.all(snap.docs.map((d) => d.ref.delete())),
      );
    await db()
      .collection("athlete_billing")
      .where("trainerId", "in", [
        "trainer-venc-03a",
        "trainer-venc-03b",
      ])
      .get()
      .then((snap) =>
        Promise.all(snap.docs.map((d) => d.ref.delete())),
      );
  });

  it("creates 0 docs for porSesion and suelto cadences", async () => {
    await seedLink("trainer-venc-03a", "athlete-venc-03a");
    await seedBilling("trainer-venc-03a", "athlete-venc-03a", "porSesion");

    await seedLink("trainer-venc-03b", "athlete-venc-03b");
    await seedBilling("trainer-venc-03b", "athlete-venc-03b", "suelto");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.skipped).toBe(2);
    expect(result.scanned).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// SKIP-MISSING-BILLING — absent athlete_billing → graceful skip
// ---------------------------------------------------------------------------

describe("SKIP-MISSING-BILLING: absent athlete_billing → graceful skip", () => {
  const trainerId = "trainer-venc-nob";
  const athleteId = "athlete-venc-nob";
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
    );
  });

  it("resolves with scanned:1, created:0, skipped:1 when billing doc is absent", async () => {
    await seedLink(trainerId, athleteId);
    // No billing doc seeded

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.skipped).toBe(1);
    expect(result.scanned).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// REQ-VENC-03 — non-active trainer_link is ignored
// ---------------------------------------------------------------------------

describe("REQ-VENC-03: non-active trainer_link → ignored", () => {
  const now = new Date(Date.UTC(2026, 6, 3, 3, 0, 0));

  afterEach(async () => {
    for (const status of ["pending", "terminated", "paused"]) {
      await cleanupDocs(
        db()
          .collection("trainer_links")
          .doc(`trainer-venc-ina-${status}_athlete-venc-ina-${status}`),
        db()
          .collection("athlete_billing")
          .doc(`trainer-venc-ina-${status}_athlete-venc-ina-${status}`),
      );
    }
  });

  it("creates 0 docs and scanned:0 for pending/terminated/paused links", async () => {
    for (const status of ["pending", "terminated", "paused"]) {
      const tid = `trainer-venc-ina-${status}`;
      const aid = `athlete-venc-ina-${status}`;
      await seedLink(tid, aid, status);
      await seedBilling(tid, aid, "mensual");
    }

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(0);
    expect(result.scanned).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-VENC-ART — UTC/ART month boundary → key into the ART month
//
// Regression for the double-billing bug: at 22:00 ART on the last day of a
// month the UTC day is already the 1st of next month. The CF must key the
// payment to the ART month (the client "marcar pagado", the 2nd writer, does
// the same) or the two sides pick different periodKeys and bill twice.
// ---------------------------------------------------------------------------

describe("SCENARIO-VENC-ART: 22:00 ART on month-end → ART-month periodKey", () => {
  const trainerId = "trainer-venc-art";
  const athleteId = "athlete-venc-art";
  // Jan 31 2026 22:00 ART == Feb 1 2026 01:00 UTC. Raw UTC would give "2026-02".
  const now = new Date(Date.UTC(2026, 1, 1, 1, 0, 0));

  const expectedPeriodKey = "2026-01";
  const expectedDocId = `${trainerId}_${athleteId}_${expectedPeriodKey}`;

  afterEach(async () => {
    await cleanupDocs(
      db().collection("trainer_links").doc(`${trainerId}_${athleteId}`),
      db().collection("athlete_billing").doc(`${trainerId}_${athleteId}`),
      db().collection("payments").doc(expectedDocId),
    );
  });

  it("keys into January (ART), not UTC-next February, with January concept + dueAt", async () => {
    await seedLink(trainerId, athleteId);
    await seedBilling(trainerId, athleteId, "mensual");

    const result = await generateDuePaymentsHandler(testApp, now);

    expect(result.created).toBe(1);

    const snap = await db().collection("payments").doc(expectedDocId).get();
    expect(snap.exists).toBe(true);

    const data = snap.data()!;
    expect(data.periodKey).toBe(expectedPeriodKey);
    expect(data.concept).toBe("Mensual Enero 2026");

    // dueAt: Jan 31 23:59:59 ART (= Feb 1 02:59:59 UTC).
    const expectedDueAt = new Date(
      Date.UTC(2026, 1, 0, 23, 59, 59) + ARG_UTC_OFFSET_MS,
    );
    const dueAt = (data.dueAt as admin.firestore.Timestamp).toDate();
    expect(dueAt.getTime()).toBe(expectedDueAt.getTime());
  });
});
