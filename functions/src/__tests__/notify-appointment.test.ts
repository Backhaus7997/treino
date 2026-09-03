/**
 * Integration tests for notifyOnAppointment Cloud Function.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   SCENARIO-632 — new appointment (requested) → notify trainer
 *   SCENARIO-633 — requested → confirmed → notify athlete
 *   SCENARIO-634 — confirmed → cancelled (no cancelledBy) → notify both
 *   SCENARIO-635 — reason === 'athlete-account-deleted' → sendFcm NOT called
 *   SCENARIO-636 — before.status === after.status → sendFcm NOT called (no-op write)
 *
 * REQ-PN-CF-003. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { notifyOnAppointmentHandler } from "../notifications/notify-appointment";
import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-appointment-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

/** Id del turno de todos los fixtures. Es el `scope` del dedupe del mail. */
const APPT_ID = "appt-test";

/**
 * Instante fijo de todos los fixtures: 2026-08-26 22:00 UTC, o sea las 19:00
 * ART del miércoles 26 de agosto.
 *
 * Fijo y no `Timestamp.now()` a propósito. El mail que encola el handler rinde
 * fecha y hora a partir de este campo, y contra `now()` no se puede assertear
 * un valor esperado — que es justamente lo que dejaba pasar el bug que este
 * archivo tenía: los fixtures sembraban `scheduledAt` (el campo del bug
 * QA-API-001, que ningún cliente escribe) mientras el handler lee `startsAt`,
 * así que `formatDateAR(undefined)` devolvía `""` y el mail salía sin fecha ni
 * hora. Nadie lo asserteaba y el test quedaba verde.
 */
const APPT_STARTS_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-08-26T22:00:00Z"),
);

function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(async (msg: admin.messaging.MulticastMessage) => ({
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as admin.messaging.Messaging;
}

async function seedUser(uid: string, fcmTokens: string[]): Promise<void> {
  await db().collection("users").doc(uid).set({ uid, fcmTokens });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    await db().collection("users").doc(uid).delete().catch(() => undefined);

    // El mail encolado tiene id determinístico (`dedupeKey`) y `enqueueMail`
    // trata un id que ya existe como dedupe legítimo: loguea y devuelve null,
    // sin escribir. Si no se borra acá, la corrida siguiente leería el
    // documento de la anterior y una regresión en los params pasaría verde.
    const queued = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .where("toUid", "==", uid)
      .get()
      .catch(() => null);
    if (queued) {
      await Promise.all(queued.docs.map((d) => d.ref.delete()));
    }
  }
}

// ---------------------------------------------------------------------------
// SCENARIO-632 — new appointment (status: 'requested') → notify trainer
// ---------------------------------------------------------------------------
describe("SCENARIO-632: new appointment status=requested → notify trainer", () => {
  const trainerId = "trainer-appt-632";
  const athleteId = "athlete-appt-632";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-632"]);
    await seedUser(athleteId, ["athlete-token-632"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[trainerId] and deepLink=/coach?tab=agenda", async () => {
    const mock = makeMockMessaging();
    const afterData = {
      trainerId,
      athleteId,
      status: "requested",
      startsAt: APPT_STARTS_AT,
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, undefined, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-632");
    expect(callArg.tokens).not.toContain("athlete-token-632");
    // QA-NOT-002: el trainer va a SU agenda (ruta role-aware), no al host de
    // atleta /coach/agenda que le mostraba "Necesitás un vínculo con un PF".
    expect(callArg.data?.deepLink).toBe("/coach?tab=agenda");
    expect(callArg.data?.kind).toBe("appointment");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-633 — requested → confirmed → notify athlete
// ---------------------------------------------------------------------------
describe("SCENARIO-633: requested→confirmed → notify athlete", () => {
  const trainerId = "trainer-appt-633";
  const athleteId = "athlete-appt-633";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-633"]);
    await seedUser(athleteId, ["athlete-token-633"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with uids=[athleteId] and deepLink=/coach?tab=agenda", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "confirmed",
      startsAt: APPT_STARTS_AT,
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("athlete-token-633");
    expect(callArg.tokens).not.toContain("trainer-token-633");
    expect(callArg.data?.deepLink).toBe("/coach?tab=agenda");
  });

  // QA-API-001 — guard de regresión sobre el NOMBRE del campo de fecha.
  //
  // La rama `confirmed` no sólo manda push: encola un mail cuyos params llevan
  // la fecha y la hora del turno, leídas de `after.startsAt`. Ese campo entra
  // al formateador con un `as never`, así que si se renombra el campo el
  // compilador no dice nada, `toDate(undefined)` devuelve null y
  // `formatDateAR` devuelve `""`: el mail sale sin fecha ni hora, sin error y
  // sin log. Es exactamente la forma del bug QA-API-001, que vivió en
  // producción porque el único test que tocaba esta rama asserteaba el push y
  // nada del mail.
  it("encola el mail con dateLabel y timeLabel derivados de startsAt", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "confirmed",
      startsAt: APPT_STARTS_AT,
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, beforeData, afterData, mock);

    const snap = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey("appointment-confirmed", APPT_ID, athleteId))
      .get();
    expect(snap.exists).toBe(true);

    const params = snap.data()?.params as Record<string, string>;
    // 22:00 UTC en America/Argentina/Buenos_Aires. Fija dos cosas de una: que
    // el campo se leyó, y que el label sale en ART y no en la UTC en la que
    // corre la function.
    expect(params.timeLabel).toBe("19:00");
    // Un `toBeDefined()` acá pasaría con `""`, que es justo lo que devolvía el
    // bug. La aserción tiene que mirar el contenido.
    expect(params.dateLabel).toMatch(/26 de agosto/);
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-634 — confirmed → cancelled (cancelledBy absent) → notify both
// ---------------------------------------------------------------------------
describe("SCENARIO-634: confirmed→cancelled, no cancelledBy → notify both parties", () => {
  const trainerId = "trainer-appt-634";
  const athleteId = "athlete-appt-634";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-634"]);
    await seedUser(athleteId, ["athlete-token-634"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("calls sendFcm with both uids when cancelledBy absent", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "confirmed" };
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      startsAt: APPT_STARTS_AT,
      // no cancelledBy field
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock.calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toContain("trainer-token-634");
    expect(callArg.tokens).toContain("athlete-token-634");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-635 — after.reason === 'athlete-account-deleted' → skip
// ---------------------------------------------------------------------------
describe("SCENARIO-635: reason=athlete-account-deleted → sendFcm NOT called", () => {
  const trainerId = "trainer-appt-635";
  const athleteId = "athlete-appt-635";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-635"]);
    await seedUser(athleteId, ["athlete-token-635"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when reason is athlete-account-deleted", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      reason: "athlete-account-deleted",
      startsAt: APPT_STARTS_AT,
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("resolves without error", async () => {
    const mock = makeMockMessaging();
    const afterData = {
      trainerId,
      athleteId,
      status: "cancelled",
      reason: "athlete-account-deleted",
    };
    await expect(
      notifyOnAppointmentHandler(testApp, APPT_ID, undefined, afterData, mock),
    ).resolves.not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-636 — before.status === after.status → skip (no-op write)
// ---------------------------------------------------------------------------
describe("SCENARIO-636: before.status === after.status → skip (no-op write)", () => {
  const trainerId = "trainer-appt-636";
  const athleteId = "athlete-appt-636";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token-636"]);
    await seedUser(athleteId, ["athlete-token-636"]);
  });

  afterEach(() => cleanup(trainerId, athleteId));

  it("does not call sendFcm when status is unchanged", async () => {
    const mock = makeMockMessaging();
    const beforeData = { trainerId, athleteId, status: "requested" };
    const afterData = {
      trainerId,
      athleteId,
      status: "requested",
      startsAt: APPT_STARTS_AT,
    };

    await notifyOnAppointmentHandler(testApp, APPT_ID, beforeData, afterData, mock);

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// No-op: after data is missing (delete event)
// ---------------------------------------------------------------------------
describe("no-op: after document missing (delete event)", () => {
  it("resolves cleanly without calling sendFcm", async () => {
    const mock = makeMockMessaging();
    await expect(
      notifyOnAppointmentHandler(testApp, APPT_ID, undefined, undefined, mock),
    ).resolves.not.toThrow();
    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});
