/**
 * Integration tests for the appointments cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-544 — Future appointment cancelled, past appointment unchanged (REQ-ACCDEL-CF-009)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "appointments-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { cancelFutureAppointments } from "../../cascade/appointments";

const db = () => admin.firestore(testApp);

function futureDate(): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days ahead
  );
}

function pastDate(): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) // 7 days ago
  );
}

async function seedAppointment(
  uid: string,
  docId: string,
  opts: { isFuture: boolean; status?: string }
): Promise<void> {
  await db().collection("appointments").doc(docId).set({
    athleteId: uid,
    trainerId: "trainer-xyz",
    scheduledAt: opts.isFuture ? futureDate() : pastDate(),
    status: opts.status ?? "confirmed",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function cleanupAppointments(docIds: string[]): Promise<void> {
  const batch = db().batch();
  for (const id of docIds) {
    batch.delete(db().collection("appointments").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("SCENARIO-544: future appointment cancelled, past appointment unchanged", () => {
  const uid = "appointments-cascade-544";
  const futureId = "appt-future-544";
  const pastId = "appt-past-544";

  beforeEach(async () => {
    await seedAppointment(uid, futureId, { isFuture: true, status: "confirmed" });
    await seedAppointment(uid, pastId, { isFuture: false, status: "confirmed" });
  });
  afterEach(() => cleanupAppointments([futureId, pastId]));

  it("SCENARIO-544: future appointment status is set to 'cancelled'", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    expect(snap.data()?.status).toBe("cancelled");
  });

  it("SCENARIO-544: future appointment reason is set to 'athlete-account-deleted'", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    expect(snap.data()?.reason).toBe("athlete-account-deleted");
  });

  it("SCENARIO-544: past appointment is NOT modified", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(pastId).get();
    expect(snap.data()?.status).toBe("confirmed");
    expect(snap.data()?.reason).toBeUndefined();
  });
});

describe("appointments: no future appointments is a no-op", () => {
  const uid = "appointments-cascade-no-future";

  it("no error thrown when user has zero future appointments", async () => {
    await expect(cancelFutureAppointments(testApp, uid)).resolves.not.toThrow();
  });
});

describe("appointments: already-cancelled appointments are untouched", () => {
  const uid = "appointments-cascade-already-cancelled";
  const cancelledId = "appt-already-cancelled";

  beforeEach(() =>
    seedAppointment(uid, cancelledId, { isFuture: true, status: "cancelled" })
  );
  afterEach(() => cleanupAppointments([cancelledId]));

  it("already-cancelled future appointment is not re-processed", async () => {
    await cancelFutureAppointments(testApp, uid);

    // Still cancelled — status unchanged
    const snap = await db().collection("appointments").doc(cancelledId).get();
    expect(snap.data()?.status).toBe("cancelled");
  });
});
