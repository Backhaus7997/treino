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
 *
 * ─── Y el otro lado: que el guard NO se pueda FORJAR ────────────────────────
 *
 * Un guard es control de flujo, así que la pregunta no termina en "¿el
 * productor y el consumidor coinciden?". Sigue en "¿alguien MÁS puede emitir
 * esa señal?". El primer intento de #846 movió el motivo adentro del
 * `cancellationLog`, y ahí la respuesta era SÍ: las reglas no iteran listas.
 *
 * El último bloque de este archivo es esa probe. Su mitad de reglas —que la
 * escritura forjada es ALLOW para el cliente— vive en
 * `appointments-shape-rules.test.ts`; acá se mide lo que el handler HACE con
 * el par de snapshots que esa escritura produce.
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

    // El productor: la clave de primer nivel, que es lo que el guard mira y lo
    // único que un cliente no puede escribir (#846).
    expect(data.reason).toBe(ATHLETE_ACCOUNT_DELETED_REASON);

    // El rastro de auditoría acompaña, pero NO es la señal.
    const log = data.cancellationLog as Array<Record<string, unknown>>;
    expect(log).toHaveLength(1);
    expect(log[0].reason).toBe(ATHLETE_ACCOUNT_DELETED_REASON);
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
    // El guard mira la ESCRITURA (`before.reason` → `after.reason`), no el
    // estado final. El motivo queda guardado en el documento para siempre; el
    // write que lo puso ocurre una vez. Sin esa mitad, este turno quedaría
    // mudo para siempre.
    await cancelFutureAppointments(testApp, athleteId);
    const id = apptIds[0];
    const cancelled = (await db().collection("appointments").doc(id).get()).data();

    const reconfirmed = { ...cancelled, status: "confirmed" };

    const mock = makeMockMessaging();
    await notifyOnAppointmentHandler(testApp, id, cancelled, reconfirmed, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
  });
});

/**
 * #846 — LA PROBE DE FORJA. Es el caso que tumbó el fix anterior.
 *
 * Contexto medido: `firestore.rules` NO puede validar el contenido de una
 * entrada del `cancellationLog` —lo dice textual sobre el Path 1: *«ese sigue
 * siendo forjable porque las reglas no iteran listas»*—. O sea que un miembro
 * del turno puede cancelar por el camino LEGÍTIMO y meter el motivo que
 * quiera adentro de la entrada que agrega.
 *
 * Mientras el guard leyó ese log, esa cancelación quedaba MUDA: cero push y
 * cero mail. Un atleta silenciaba al PF; un PF silenciaba al atleta.
 *
 * La mitad de reglas —que esa escritura es ALLOW para el cliente— está medida
 * en `appointments-shape-rules.test.ts`. Acá se mide la consecuencia: el
 * handler REAL, con el par de snapshots que esa escritura produce, tiene que
 * notificar igual.
 */
describe("#846: el guard no se puede forjar desde el cliente", () => {
  beforeEach(async () => {
    await cleanup();
    await seed();
  });
  afterEach(cleanup);

  it("una cancelación con el motivo del cascade FORJADO en el log sí notifica", async () => {
    const id = apptIds[0];
    const ref = db().collection("appointments").doc(id);
    const before = (await ref.get()).data() as admin.firestore.DocumentData;

    // Exactamente el update parcial que manda `AppointmentRepository.cancel()`,
    // con el motivo del cascade metido en la entrada del log. Un cliente puede
    // escribir esto: la forma es válida y las reglas no miran adentro.
    await ref.update({
      status: "cancelled",
      cancelledBy: athleteId,
      cancelledAt: admin.firestore.Timestamp.now(),
      cancellationLog: admin.firestore.FieldValue.arrayUnion({
        byUid: athleteId,
        atMs: Date.now(),
        reason: ATHLETE_ACCOUNT_DELETED_REASON,
      }),
    });

    const after = (await ref.get()).data() as admin.firestore.DocumentData;
    // La clave que el guard mira NO está: ningún cliente la puede escribir.
    expect(after.reason).toBeUndefined();

    const mock = makeMockMessaging();
    await notifyOnAppointmentHandler(testApp, id, before, after, mock);

    // El daño que esto custodia: el PF no se entera de que le cancelaron.
    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
  });

  it("y el cascade LEGÍTIMO sigue sin notificar — la otra mitad de la pinza", async () => {
    const before = new Map<string, admin.firestore.DocumentData>();
    for (const id of apptIds) {
      before.set(id, (await db().collection("appointments").doc(id).get())
        .data() as admin.firestore.DocumentData);
    }

    await cancelFutureAppointments(testApp, athleteId);

    const mock = makeMockMessaging();
    for (const id of apptIds) {
      const after = (await db().collection("appointments").doc(id).get()).data();
      await notifyOnAppointmentHandler(
        testApp,
        id,
        before.get(id),
        after as admin.firestore.DocumentData,
        mock,
      );
    }

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
    expect(await mailQueuedFor([athleteId, trainerId])).toBe(0);
  });
});
