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
    // QA-API-001: real docs key the appointment time as `startsAt` (see
    // Appointment model + appointment_repository). The suite previously seeded
    // `scheduledAt`, matching the buggy query and masking the defect.
    startsAt: opts.isFuture ? futureDate() : pastDate(),
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

  // ─── #846 ──────────────────────────────────────────────────────────────
  //
  // Esto asserteaba `snap.data()?.reason === 'athlete-account-deleted'`, o sea
  // custodiaba EXACTAMENTE la escritura que congelaba el turno. `reason` no
  // existe en `Appointment.toJson()` ni en las 14 claves de `hasOnly()` de
  // `firestore.rules`; el Admin SDK saltea las reglas, pero `hasOnly()` corre
  // sobre el documento MERGEADO, así que cualquier update parcial POSTERIOR
  // del cliente arrastraba la clave y la allowlist lo rechazaba. Medido: el PF
  // anotando ese turno → DENY, el atleta cancelándolo → DENY, y
  // `allow delete: if false`.
  //
  // El motivo ahora va DENTRO del `cancellationLog`, que sí está en la
  // allowlist y ya tiene el campo en el modelo (`CancellationEntry.reason`).
  // Los dos casos de abajo son la pinza: el motivo sigue quedando registrado,
  // y la clave de primer nivel NO vuelve.
  it("#846: el motivo queda en el cancellationLog, no en una clave suelta", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    const log = snap.data()?.cancellationLog as Array<Record<string, unknown>>;
    expect(log).toHaveLength(1);
    expect(log[0].reason).toBe("athlete-account-deleted");
    expect(log[0].byUid).toBe(uid);
    expect(typeof log[0].atMs).toBe("number");
  });

  it("#846: NO escribe una clave `reason` de primer nivel — la que congela el turno", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    expect(snap.data()?.reason).toBeUndefined();
    // Y ninguna otra clave fuera de las 14 de la allowlist de las reglas.
    const permitidas = [
      "id", "trainerId", "athleteId", "athleteDisplayName", "startsAt",
      "durationMin", "status", "cancelledAt", "cancelledBy",
      "cancellationLog", "noteBefore", "noteAfter", "recurringId",
      "paymentId",
      // el seed de este archivo trae `createdAt`, que es del test, no de la CF
      "createdAt",
    ];
    for (const k of Object.keys(snap.data() ?? {})) {
      expect(permitidas).toContain(k);
    }
  });

  it("SCENARIO-544: past appointment is NOT modified", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(pastId).get();
    expect(snap.data()?.status).toBe("confirmed");
    expect(snap.data()?.cancellationLog).toBeUndefined();
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
