/**
 * Integration tests for the appointments cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-544 — Future appointment cancelled, past appointment unchanged (REQ-ACCDEL-CF-009)
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "appointments-cascade-test");
});

afterAll(async () => {
  await deleteApp(testApp);
});

// Import the module under test — will fail until implementation exists
import { cancelFutureAppointments } from "../../cascade/appointments";

const db = () => getFirestore(testApp);

function futureDate(): Timestamp {
  return Timestamp.fromDate(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days ahead
  );
}

function pastDate(): Timestamp {
  return Timestamp.fromDate(
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
    createdAt: FieldValue.serverTimestamp(),
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
  // `reason` de primer nivel se queda, y ahora es deliberado: es la señal
  // CF→CF que lee el guard de `notify-appointment.ts`, y es la única clave del
  // documento que un cliente NO puede escribir —`firestore.rules` la pinea en
  // los dos caminos de update y la exige `null` en el `create`—.
  //
  // El bug de #846 no era la clave: era que estaba FUERA de `hasOnly()`, así
  // que congelaba el turno (`hasOnly()` corre sobre el documento MERGEADO). Eso
  // se cerró en las reglas, sin migración.
  //
  // ⚠️ El primer intento movía el motivo adentro del `cancellationLog`. Se
  // revirtió: las reglas no iteran listas, o sea que ese motivo lo forja
  // cualquier miembro del turno y el guard deja de ser un guard. La prueba de
  // punta a punta está en `appointments-notify-contract.test.ts`.
  it("#846: escribe `reason` de primer nivel — la señal que sólo emite el backend", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    expect(snap.data()?.reason).toBe("athlete-account-deleted");
  });

  it("#846: y deja el motivo también en el cancellationLog, que es el rastro", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    const log = snap.data()?.cancellationLog as Array<Record<string, unknown>>;
    expect(log).toHaveLength(1);
    expect(log[0].reason).toBe("athlete-account-deleted");
    expect(log[0].byUid).toBe(uid);
    expect(typeof log[0].atMs).toBe("number");
  });

  it("#846: no escribe ninguna clave fuera de la allowlist de las reglas", async () => {
    await cancelFutureAppointments(testApp, uid);

    const snap = await db().collection("appointments").doc(futureId).get();
    // Las 15 de `hasOnly()`, `reason` incluida desde #846.
    const permitidas = [
      "id", "trainerId", "athleteId", "athleteDisplayName", "startsAt",
      "durationMin", "status", "cancelledAt", "cancelledBy",
      "cancellationLog", "noteBefore", "noteAfter", "recurringId",
      "paymentId", "reason",
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
    expect(snap.data()?.reason).toBeUndefined();
    expect(snap.data()?.cancellationLog).toBeUndefined();
  });
});

// ─── El marco de `startsAt` ──────────────────────────────────────────────────
//
// `startsAt` se guarda como hora de pared argentina etiquetada UTC (ADR-7): el
// instante real MENOS 3 h. La cascada lo comparaba contra `Timestamp.now()`, y
// un turno que empieza en 1 h (guardado «hace 2 h») figuraba como ya pasado: los
// turnos de las próximas ~3 h quedaban `confirmed` con la cuenta borrada.
//
// Estos turnos se siembran COMO LOS GUARDA LA APP. Sembrarlos con el instante
// real (como `futureDate()` de arriba, a 7 días) mide otra cosa y escondía el
// desfase: a 7 días los dos marcos coinciden.
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const storedLikeTheApp = (realOffsetMs: number): Timestamp =>
  Timestamp.fromMillis(Date.now() + realOffsetMs - 3 * HOUR);

describe("appointments: el marco de startsAt (wall-clock ART, ADR-7)", () => {
  const uid = "appointments-cascade-frame";
  const casos: Array<[string, number, string]> = [
    ["empieza en 10 min", 10 * MIN, "cancelled"],
    ["empieza en 1 h", HOUR, "cancelled"],
    ["empieza en 2 h 50 min", 170 * MIN, "cancelled"],
    ["empezó hace 10 min", -10 * MIN, "confirmed"],
    ["empezó hace 1 h", -HOUR, "confirmed"],
  ];
  const ids = casos.map((_, i) => `appt-frame-${i}`);

  afterEach(() => cleanupAppointments(ids));

  it("premisa: guardado como lo guarda la app, un turno en 1 h queda ANTES de now() en instante real", () => {
    // Si esto deja de valer, los casos de abajo ya no distinguen un marco del otro.
    expect(storedLikeTheApp(HOUR).toMillis()).toBeLessThan(Date.now());
  });

  it.each(casos.map((c, i) => [...c, ids[i]] as [string, number, string, string]))(
    "el turno que %s",
    async (_nombre, offset, esperado, id) => {
      await db().collection("appointments").doc(id).set({
        athleteId: uid,
        trainerId: "trainer-xyz",
        startsAt: storedLikeTheApp(offset),
        status: "confirmed",
      });

      const res = await cancelFutureAppointments(testApp, uid);

      const d = (await db().collection("appointments").doc(id).get()).data()!;
      expect(d.status).toBe(esperado);
      expect(res.count).toBe(esperado === "cancelled" ? 1 : 0);
      if (esperado === "cancelled") {
        expect(d.reason).toBe("athlete-account-deleted");
        expect(d.cancelledBy).toBe(uid);
      } else {
        expect(d.reason).toBeUndefined(); // lo que ya empezó no se toca
      }
    }
  );
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
