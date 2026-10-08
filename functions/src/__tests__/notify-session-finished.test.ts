/**
 * Tests de `notifyOnSessionFinished` contra un emulador de Firestore REAL.
 *
 * Los dos que más importan no son los del camino feliz:
 *
 *  - **un update posterior NO redispara**. El aviso se engancha a una
 *    TRANSICIÓN, y sobre el doc de sesión escriben varias cosas después de
 *    cerrarla — correcciones, contadores, el `feedbackCounts` de la otra CF.
 *    Sin la guarda, cada una de esas volvería a notificar.
 *  - **el barrido de colgadas no cuenta como "terminó"**. Ese barrido escribe
 *    `finishedAt` igual que un cierre real, así que un entreno abandonado el
 *    martes le avisaría al PF el domingo que el alumno "terminó su
 *    entrenamiento". Falso, y a destiempo.
 *
 * Patrón espejado de `notify-exercise-feedback.test.ts`.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Messaging, MulticastMessage } from "firebase-admin/messaging";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp(
    { projectId: "treino-dev" },
    "notify-session-finished-test",
  );
});

afterAll(async () => {
  await deleteApp(testApp);
});

import {
  notifyOnSessionFinishedHandler,
  resumenDeReportes,
} from "../notifications/notify-session-finished";

const db = () => getFirestore(testApp);

const ATHLETE = "athlete-session-finished";
const TRAINER = "trainer-session-finished";
const SESSION = "session-finished-1";

const INICIO = new Date("2026-05-19T13:00:00Z");
const FIN = new Date("2026-05-19T14:00:00Z");
/** Más de 8h después del inicio: la firma del barrido de colgadas. */
const FIN_TARDIO = new Date("2026-05-20T09:00:00Z");

function makeMockMessaging(): Messaging {
  return {
    sendEachForMulticast: jest.fn(async (msg: MulticastMessage) => ({
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
    })),
  } as unknown as Messaging;
}

const sessionRef = () =>
  db().collection("users").doc(ATHLETE).collection("sessions").doc(SESSION);

function sesion(over: Record<string, unknown> = {}) {
  return {
    uid: ATHLETE,
    routineId: "r1",
    routineName: "Piernas",
    startedAt: Timestamp.fromDate(INICIO),
    finishedAt: null,
    status: "active",
    wasFullyCompleted: false,
    ...over,
  };
}

const terminada = (fin: Date = FIN, over: Record<string, unknown> = {}) =>
  sesion({
    finishedAt: Timestamp.fromDate(fin),
    status: "finished",
    wasFullyCompleted: true,
    ...over,
  });

async function seedFeedback(id: string, kind: string, extra = {}) {
  await sessionRef()
    .collection("exerciseFeedback")
    .doc(id)
    .set({ kind, exerciseId: "e1", exerciseName: "Sentadilla", ...extra });
}

async function seedTodo() {
  await db()
    .collection("users")
    .doc(TRAINER)
    .set({ uid: TRAINER, fcmTokens: ["trainer-token"] });
  await db()
    .collection("userPublicProfiles")
    .doc(ATHLETE)
    .set({ uid: ATHLETE, displayName: "Mateo" });
  await db().collection("session_shares").doc(ATHLETE).set({ trainerId: TRAINER });
  await db()
    .collection("trainer_links")
    .doc(`link-${ATHLETE}`)
    .set({ athleteId: ATHLETE, trainerId: TRAINER, status: "active" });
  await sessionRef().set(sesion());
}

async function limpiar() {
  const subs = await sessionRef().collection("exerciseFeedback").get();
  await Promise.all(subs.docs.map((d) => d.ref.delete()));
  await Promise.all([
    sessionRef().delete(),
    db().collection("users").doc(TRAINER).delete(),
    db().collection("userPublicProfiles").doc(ATHLETE).delete(),
    db().collection("session_shares").doc(ATHLETE).delete(),
    db().collection("trainer_links").doc(`link-${ATHLETE}`).delete(),
  ]).catch(() => undefined);
  const inbox = await db()
    .collection("users")
    .doc(TRAINER)
    .collection("notifications")
    .get();
  await Promise.all(inbox.docs.map((d) => d.ref.delete()));
}

const enviado = (mock: Messaging) =>
  (mock.sendEachForMulticast as jest.Mock).mock.calls[0]?.[0] as
    | MulticastMessage
    | undefined;

// ─── El texto del resumen ────────────────────────────────────────────────────

describe("resumenDeReportes", () => {
  it("sin reportes devuelve null, para que el cuerpo quede sólo con la rutina", () => {
    expect(resumenDeReportes(0, 0)).toBeNull();
  });

  it("singular y plural, en los dos ejes", () => {
    expect(resumenDeReportes(1, 0)).toBe("1 molestia");
    expect(resumenDeReportes(2, 0)).toBe("2 molestias");
    expect(resumenDeReportes(0, 1)).toBe("1 nota");
    expect(resumenDeReportes(0, 3)).toBe("3 notas");
  });

  it("la molestia va PRIMERO — es lo que el PF tiene que ver antes", () => {
    expect(resumenDeReportes(1, 3)).toBe("1 molestia, 3 notas");
  });
});

// ─── El handler ──────────────────────────────────────────────────────────────

describe("notifyOnSessionFinishedHandler", () => {
  beforeEach(async () => {
    await limpiar().catch(() => undefined);
    await seedTodo();
  });

  afterEach(async () => {
    await limpiar().catch(() => undefined);
  });

  it("la transición notifica al PF vinculado, con el conteo en el cuerpo", async () => {
    await seedFeedback("f1", "discomfort");
    await seedFeedback("f2", "comment");
    await seedFeedback("f3", "comment");
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    const msg = enviado(mock);
    expect(msg?.tokens).toEqual(["trainer-token"]);
    expect(msg?.notification?.title).toBe("Mateo terminó su entrenamiento");
    expect(msg?.notification?.body).toBe("Piernas · 1 molestia, 2 notas");
    expect(msg?.data?.deepLink).toBe(
      `/coach/athlete/${ATHLETE}/session/${SESSION}`,
    );
  });

  it("sin reportes, el cuerpo es sólo la rutina", async () => {
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    expect(enviado(mock)?.notification?.body).toBe("Piernas");
  });

  // ⚠️ EL CONTROL NEGATIVO QUE MÁS IMPORTA. Sobre el doc de sesión escriben
  // varias cosas DESPUÉS de cerrarla, incluida la otra CF con `feedbackCounts`.
  it("un update POSTERIOR no vuelve a notificar", async () => {
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      terminada(), // ya venía terminada
      terminada(FIN, { feedbackCounts: { comment: 1 } }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // ⚠️ EL ZOMBI. El barrido escribe `finishedAt` igual que un cierre real.
  it("no notifica cuando el barrido la MARCÓ como cerrada por él", async () => {
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(FIN, { wasFullyCompleted: false, closedBySweep: true }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // ⚠️ EL CASO QUE LA PRIMERA VERSIÓN DEJABA PASAR, y el que motivó la marca.
  // Cuando la sesión más nueva sigue viva, el barrido cierra las DUPLICADAS sin
  // mirarles la edad (`aCerrar = snap.docs.skip(1)`). Una colgada de minutos —el
  // reloj y el teléfono abriendo una cada uno— se cerraba dentro de las 8h y la
  // heurística de tiempo la dejaba pasar: el PF recibía "terminó su
  // entrenamiento" por un entreno que nunca existió.
  it("una duplicada barrida A LOS MINUTOS tampoco notifica", async () => {
    const mock = makeMockMessaging();
    const aLosDiezMinutos = new Date(INICIO.getTime() + 10 * 60 * 1000);

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(aLosDiezMinutos, {
        wasFullyCompleted: false,
        closedBySweep: true,
      }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // FALLBACK: las sesiones que ya están en la base, cerradas por un cliente
  // anterior a la marca, nunca la van a tener. Para ésas queda el tiempo.
  it("sin marca pero excediendo las 8h (cliente viejo) tampoco notifica", async () => {
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(FIN_TARDIO, { wasFullyCompleted: false }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // CONTROL del anterior: un abandono DELIBERADO también tiene
  // `wasFullyCompleted: false`, y ése SÍ se avisa — es justo el caso donde el
  // alumno dejó una nota y se fue. Sin este test, la guarda del zombi podría
  // estar cortando por `wasFullyCompleted` y se vería igual.
  it("CONTROL — un abandono deliberado (dentro de las 8h) SÍ notifica", async () => {
    await seedFeedback("f1", "comment");
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(FIN, { wasFullyCompleted: false }),
      mock,
    );

    expect(enviado(mock)?.notification?.body).toBe("Piernas · 1 nota");
  });

  it("sin PF vinculado sale limpio y no despacha", async () => {
    await db().collection("session_shares").doc(ATHLETE).delete();
    const mock = makeMockMessaging();

    await expect(
      notifyOnSessionFinishedHandler(
        testApp,
        ATHLETE,
        SESSION,
        sesion(),
        terminada(),
        mock,
      ),
    ).resolves.toBeUndefined();
    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // La trampa del #628: el grant es client-writable y no prueba vínculo.
  it("grant sin trainer_links vivo NO notifica", async () => {
    await db().collection("trainer_links").doc(`link-${ATHLETE}`).delete();
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("el vínculo INACTIVO tampoco alcanza", async () => {
    await db()
      .collection("trainer_links")
      .doc(`link-${ATHLETE}`)
      .set({ athleteId: ATHLETE, trainerId: TRAINER, status: "ended" });
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // DATO DE SALUD. El cuerpo puede decir CUÁNTAS; nunca qué dijo ni dónde le
  // duele. Y esto queda persistido en el inbox del PF, que el borrado de cuenta
  // NO barre (QA-CMP-008).
  it("no filtra el texto ni la foto del reporte", async () => {
    await seedFeedback("f1", "discomfort", {
      text: "me tira el hombro izquierdo",
      photoUrl: "https://firebasestorage.example/token-al-portador",
    });
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    const crudo = JSON.stringify(enviado(mock));
    expect(crudo).not.toContain("hombro");
    expect(crudo).not.toContain("token-al-portador");
    // …pero SÍ dice que hubo una, que es el punto del aviso.
    expect(enviado(mock)?.notification?.body).toBe("Piernas · 1 molestia");
  });

  it("lleva prefKey: el PF puede apagar esta fila", async () => {
    const mock = makeMockMessaging();
    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    const inbox = await db()
      .collection("users")
      .doc(TRAINER)
      .collection("notifications")
      .get();
    expect(inbox.docs).toHaveLength(1);
    expect(inbox.docs[0].data().kind).toBe("session-finished");
  });

  it("el PF que apagó el push NO recibe banner", async () => {
    await db()
      .collection("users")
      .doc(TRAINER)
      .set(
        {
          uid: TRAINER,
          fcmTokens: ["trainer-token"],
          notificationPrefs: { sesion_terminada: { push: false } },
        },
        { merge: true },
      );
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // CONTROL del anterior: sin la fila en `notificationPrefs` el default es
  // MANDAR. Un gate que corta siempre se ve igual que uno que respeta la
  // preferencia.
  it("CONTROL — sin la fila de preferencias, SÍ manda", async () => {
    const mock = makeMockMessaging();

    await notifyOnSessionFinishedHandler(
      testApp,
      ATHLETE,
      SESSION,
      sesion(),
      terminada(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
  });
});
