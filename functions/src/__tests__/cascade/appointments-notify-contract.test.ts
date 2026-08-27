/**
 * Contrato productor→consumidor del cascade de turnos.
 *
 * ─── Por qué existe este archivo ───────────────────────────────────────────
 *
 * `cascade/appointments.ts` escribe un motivo y `notifications/notify-appointment.ts`
 * lo lee de GUARD para no notificar la cancelación (ADR-PN-006 / REQ-PN-CF-003).
 * Son dos módulos, dos suites, y hasta acá CERO tests que los cruzaran.
 *
 * `notify-appointment.test.ts` (SCENARIO-635) le pasa el motivo A MANO al
 * handler: testea al consumidor contra un payload sintético, o sea contra la
 * creencia del test sobre lo que el productor escribe. Cuando #846 cambió esa
 * escritura —de la clave suelta `reason` a una entrada del `cancellationLog`—
 * el guard quedó muerto y las 172 pruebas siguieron en verde, porque ninguna
 * hacía correr al productor de verdad. `ApptData = Record<string, unknown>`
 * hace que `tsc` tampoco chiste.
 *
 * Este test corre el cascade REAL contra el emulador, toma el snapshot de
 * ANTES y el de DESPUÉS —exactamente lo que `onDocumentWritten` le entrega al
 * trigger— y se los da al handler REAL. Si el productor deja de escribir lo
 * que el consumidor mira, esto se pone rojo. Es el test que faltaba.
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

import {
  ATHLETE_ACCOUNT_DELETED_REASON,
  cancelFutureAppointments,
} from "../../cascade/appointments";
import { notifyOnAppointmentHandler } from "../../notifications/notify-appointment";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "appointments-notify-contract-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

const athleteId = "athlete-cascade-notify-846";
const trainerId = "trainer-cascade-notify-846";
const apptIds = ["appt-cascade-notify-846-a", "appt-cascade-notify-846-b"];

function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(async (msg: admin.messaging.MulticastMessage) => ({
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as admin.messaging.Messaging;
}

function futureDate(): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  );
}

async function seed(): Promise<void> {
  // Los dos con token: si el guard falla, el mock recibe tokens de VERDAD y la
  // cuenta de destinatarios queda visible en el fallo.
  await db().collection("users").doc(trainerId).set({
    uid: trainerId,
    fcmTokens: ["trainer-token-846"],
  });
  await db().collection("users").doc(athleteId).set({
    uid: athleteId,
    fcmTokens: ["athlete-token-846"],
  });
  for (const id of apptIds) {
    await db().collection("appointments").doc(id).set({
      id,
      athleteId,
      trainerId,
      athleteDisplayName: "Atleta 846",
      startsAt: futureDate(),
      durationMin: 60,
      status: "confirmed",
    });
  }
}

async function cleanup(): Promise<void> {
  const batch = db().batch();
  batch.delete(db().collection("users").doc(trainerId));
  batch.delete(db().collection("users").doc(athleteId));
  for (const id of apptIds) {
    batch.delete(db().collection("appointments").doc(id));
  }
  await batch.commit().catch(() => undefined);

  const queued = await db()
    .collection("mail_queue")
    .where("toUid", "in", [athleteId, trainerId])
    .get()
    .catch(() => null);
  if (queued && !queued.empty) {
    const b = db().batch();
    for (const doc of queued.docs) b.delete(doc.ref);
    await b.commit().catch(() => undefined);
  }
}

async function mailQueuedFor(uids: string[]): Promise<number> {
  const snap = await db().collection("mail_queue").where("toUid", "in", uids).get();
  return snap.size;
}

describe("#846 (secuela): el cascade REAL no dispara la notificación de cancelación", () => {
  beforeEach(async () => {
    await cleanup();
    await seed();
  });
  afterEach(cleanup);

  it("el write del cascade no llama a sendFcm ni encola mail", async () => {
    // El snapshot de ANTES, como lo entrega `event.data.before.data()`.
    const before = new Map<string, admin.firestore.DocumentData>();
    for (const id of apptIds) {
      const snap = await db().collection("appointments").doc(id).get();
      before.set(id, snap.data() as admin.firestore.DocumentData);
    }

    const { count } = await cancelFutureAppointments(testApp, athleteId);
    expect(count).toBe(apptIds.length);

    const mock = makeMockMessaging();
    for (const id of apptIds) {
      const snap = await db().collection("appointments").doc(id).get();
      // Y el de DESPUÉS. Esto es literalmente el par que recibe el trigger.
      await notifyOnAppointmentHandler(
        testApp,
        id,
        before.get(id),
        snap.data() as admin.firestore.DocumentData,
        mock,
      );
    }

    // El daño que esto custodia: un atleta con N turnos futuros generaba N push
    // al PF y N a la cuenta recién borrada.
    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
    expect(await mailQueuedFor([athleteId, trainerId])).toBe(0);
  });

  it("el cascade escribe el motivo donde el guard lo busca", async () => {
    await cancelFutureAppointments(testApp, athleteId);

    const snap = await db().collection("appointments").doc(apptIds[0]).get();
    const data = snap.data() ?? {};
    const log = data.cancellationLog as Array<Record<string, unknown>>;

    // El productor: la entrada nueva del log, con el motivo del contrato.
    expect(log).toHaveLength(1);
    expect(log[0].reason).toBe(ATHLETE_ACCOUNT_DELETED_REASON);
    // Y NO la clave suelta que congelaba el turno (#846).
    expect(data.reason).toBeUndefined();
  });

  it("con `cancelledBy` el fallback ya no le escribiría al atleta borrado", async () => {
    await cancelFutureAppointments(testApp, athleteId);

    const snap = await db().collection("appointments").doc(apptIds[0]).get();
    // Segundo cierre: si el guard fallara, `notify-appointment` elige
    // destinatario con este campo. Sin él cae en `[athleteId, trainerId]`.
    expect(snap.data()?.cancelledBy).toBe(athleteId);
  });
});

describe("#846 (secuela): el guard NO silencia cancelaciones ajenas", () => {
  beforeEach(async () => {
    await cleanup();
    await seed();
  });
  afterEach(cleanup);

  it("un turno que el cascade ya tocó y DESPUÉS cambia de estado sí notifica", async () => {
    // Mirar sólo la última entrada del log dejaría este turno mudo para
    // siempre: el motivo del cascade queda escrito ahí, el write no.
    await cancelFutureAppointments(testApp, athleteId);
    const id = apptIds[0];
    const cancelled = (await db().collection("appointments").doc(id).get()).data();

    const reconfirmed = { ...cancelled, status: "confirmed" };

    const mock = makeMockMessaging();
    await notifyOnAppointmentHandler(testApp, id, cancelled, reconfirmed, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
  });
});
