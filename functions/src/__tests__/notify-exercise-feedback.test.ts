/**
 * Integration tests for notifyOnExerciseFeedback Cloud Function (#628).
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * SCENARIOs covered:
 *   - kind: 'discomfort' con grant vivo Y `trainer_links` activo → manda el push
 *   - kind: 'comment' → NO manda nada (el caso central del feature: un
 *     comentario común no debe vibrarle el teléfono al PF)
 *   - sin doc session_shares → no manda y no tira (mismo estado que "todavía
 *     no tiene PF vinculado", no una falla)
 *   - session_shares apunta a OTRO PF → el push llega solo a ese trainerId
 *   - el payload de FCM NO contiene `text` ni `photoUrl` del reporte (dato
 *     de salud, ver header de notify-exercise-feedback.ts)
 *   - GRANT FORJADO: `session_shares` apunta a un uid con el que NO hay
 *     `trainer_links` activo → NO despacha. Es el bloqueante de seguridad,
 *     abajo tiene su propio describe con el porqué.
 *   - EL MAIL al PF (`kind: "discomfort-reported"`): se encola con el push,
 *     dedupea por SESIÓN (cinco ejercicios → un mail), no lleva `prefKey` y no
 *     guarda dato de salud en el doc de la cola. Su propio describe al final.
 *
 * ⚠️ Toda guarda que corta el push tiene que cortar el MAIL también, y el mail
 * es el canal que más dura: no se borra apagando el teléfono. Por eso los casos
 * de `comment` y de grant forjado assertean los dos canales, no solo el push.
 *
 * ⚠️ TODO escenario que ESPERA un despacho tiene que sembrar `trainer_links`
 * además de `session_shares`. El grant solo ya no alcanza — es exactamente el
 * agujero que este archivo pinea. Si agregás un caso feliz y se te olvida el
 * link, va a dar rojo, y el rojo tiene razón.
 *
 * #628.
 */

import * as admin from "firebase-admin";
import { notifyOnExerciseFeedbackHandler } from "../notifications/notify-exercise-feedback";
import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "../mail/types";
import { trainerEntry } from "../mail/templates";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-exercise-feedback-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

/** Minimal mock messaging that tracks sendEachForMulticast calls. */
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

async function seedUserPublicProfile(uid: string, displayName: string): Promise<void> {
  await db().collection("userPublicProfiles").doc(uid).set({ uid, displayName });
}

async function seedSessionShare(athleteUid: string, trainerId: string): Promise<void> {
  await db().collection("session_shares").doc(athleteUid).set({ trainerId });
}

/** Id determinista para el vínculo — en prod es autogenerado, pero acá lo que
 *  importa es poder borrarlo en el cleanup sin queryear. El handler lo busca
 *  POR CONTENIDO (athleteId + trainerId + status), nunca por id, así que
 *  fijarlo no debilita el test. */
function linkId(athleteUid: string, trainerId: string): string {
  return `link-${athleteUid}-${trainerId}`;
}

/** Siembra un `trainer_links` — el doc que el handler exige ADEMÁS del grant. */
async function seedTrainerLink(
  athleteUid: string,
  trainerId: string,
  status = "active",
): Promise<void> {
  await db()
    .collection("trainer_links")
    .doc(linkId(athleteUid, trainerId))
    .set({ athleteId: athleteUid, trainerId, status });
}

async function cleanupLinks(athleteUid: string, ...trainerIds: string[]): Promise<void> {
  await Promise.all(
    trainerIds.map((t) =>
      db()
        .collection("trainer_links")
        .doc(linkId(athleteUid, t))
        .delete()
        .catch(() => undefined),
    ),
  );
}

/**
 * Docs del outbox dirigidos a un uid.
 *
 * El mail es la contraparte del push, así que toda guarda que corta el push
 * tiene que cortarlo también. Se consulta por `toUid` y no por el id derivado
 * para que un caso que espera CERO mails no dependa de adivinar bien la clave.
 */
async function queuedMailFor(uid: string): Promise<MailQueueDoc[]> {
  const snap = await db()
    .collection(MAIL_QUEUE_COLLECTION)
    .where("toUid", "==", uid)
    .get();
  return snap.docs.map((d) => d.data() as MailQueueDoc);
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    // El outbox NO se limpia solo, y `enqueueMail` usa `create()`: un doc que
    // sobrevive a la corrida anterior hace que el enqueue de esta devuelva
    // null, y un caso que espera mail terminaría leyendo el doc VIEJO — verde
    // sobre una rama que no corrió.
    const queued = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .where("toUid", "==", uid)
      .get()
      .catch(() => null);
    if (queued) {
      await Promise.all(queued.docs.map((d) => d.ref.delete()));
    }
    // El inbox es una SUBCOLECCIÓN: borrar `users/{uid}` no se la lleva. Sin
    // esto, el historial se acumula entre tests y el de privacidad de abajo
    // podría estar mirando el de la corrida anterior.
    const inbox = await db()
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .get()
      .catch(() => null);
    if (inbox) {
      await Promise.all(inbox.docs.map((d) => d.ref.delete()));
    }
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await db().collection("userPublicProfiles").doc(uid).delete().catch(() => undefined);
    await db().collection("session_shares").doc(uid).delete().catch(() => undefined);
  }
}

function makeFeedback(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    exerciseId: "ex-1",
    exerciseName: "Sentadilla",
    setNumber: 2,
    kind: "discomfort",
    text: "Me tiró la rodilla derecha en la última serie",
    photoUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/sessionFeedback%2Fsecret?alt=media&token=abc123",
    photoPath: "sessionFeedback/athlete-1/session-1/feedback-1.jpg",
    createdAt: admin.firestore.Timestamp.now(),
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// kind: 'discomfort' con grant vivo → manda el push
// ---------------------------------------------------------------------------
describe("kind: discomfort with a live session_shares grant → sends the push", () => {
  const athleteUid = "athlete-discomfort";
  const trainerId = "trainer-discomfort";
  const sessionId = "session-discomfort";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, trainerId);
    await seedTrainerLink(athleteUid, trainerId);
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("calls sendFcm targeting the linked trainer", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toEqual(["trainer-token"]);
    expect(callArg.data?.kind).toBe("discomfort");
  });

  it("names the athlete and the exercise in the body", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.notification?.body).toContain("Ana Atleta");
    expect(callArg.notification?.body).toContain("Sentadilla");
  });
});

// ---------------------------------------------------------------------------
// kind: 'comment' → NO manda nada — EL caso central del feature.
// ---------------------------------------------------------------------------
describe("kind: comment → does NOT notify (the feature's whole point)", () => {
  const athleteUid = "athlete-comment";
  const trainerId = "trainer-comment";
  const sessionId = "session-comment";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, trainerId);
    // El vínculo va sembrado A PROPÓSITO aunque este caso no despache: sin él,
    // el test pasaría por la guarda de seguridad y no por el guard de `kind`,
    // que es lo único que acá se quiere pinear. Verde por el motivo correcto.
    await seedTrainerLink(athleteUid, trainerId);
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("does not call sendEachForMulticast for a plain comment", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback({ kind: "comment", text: "Se sintió liviano hoy" }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  // La distinción comment/discomfort tiene que valer para los DOS canales. Un
  // mail por cada comentario de sesión es peor que el push que este feature ya
  // decidió no mandar: el push se descarta, el mail queda en la bandeja y
  // entrena al PF a filtrar al remitente. El día que llegue el de molestia
  // —el que sí importa— no lo va a ver.
  it("tampoco encola mail para un comentario común", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback({ kind: "comment", text: "Se sintió liviano hoy" }),
      makeMockMessaging(),
    );

    expect(await queuedMailFor(trainerId)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Sin doc session_shares → no manda y no tira.
// ---------------------------------------------------------------------------
describe("no session_shares doc → no notification, no throw", () => {
  const athleteUid = "athlete-no-grant";
  const sessionId = "session-no-grant";

  beforeEach(async () => {
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    // Deliberadamente sin seedSessionShare: el alumno no tiene PF vinculado.
  });

  afterEach(async () => {
    await cleanup(athleteUid);
  });

  it("resolves without throwing and never dispatches", async () => {
    const mock = makeMockMessaging();

    await expect(
      notifyOnExerciseFeedbackHandler(testApp, athleteUid, sessionId, makeFeedback(), mock),
    ).resolves.toBeUndefined();

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// session_shares apunta a OTRO PF → solo le llega a ese.
// ---------------------------------------------------------------------------
describe("session_shares points to a specific trainer → only that trainer is notified", () => {
  const athleteUid = "athlete-other-trainer";
  const linkedTrainerId = "trainer-linked";
  const otherTrainerId = "trainer-not-linked";
  const sessionId = "session-other-trainer";

  beforeEach(async () => {
    await seedUser(linkedTrainerId, ["linked-token"]);
    await seedUser(otherTrainerId, ["other-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, linkedTrainerId);
    // Los DOS vínculos activos: así el test sigue midiendo a quién apunta el
    // GRANT, y no a quién le queda un link. Si solo sembrara el del linked, el
    // verde podría venir de la guarda nueva en vez de la selección de
    // destinatario, y este caso dejaría de decir lo que dice su nombre.
    await seedTrainerLink(athleteUid, linkedTrainerId);
    await seedTrainerLink(athleteUid, otherTrainerId);
  });

  afterEach(async () => {
    await cleanup(athleteUid, linkedTrainerId, otherTrainerId);
    await cleanupLinks(athleteUid, linkedTrainerId, otherTrainerId);
  });

  it("sends only to the trainerId named in session_shares", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toEqual(["linked-token"]);
    expect(callArg.tokens).not.toContain("other-token");
  });
});

// ---------------------------------------------------------------------------
// El payload de FCM no contiene `text` ni `photoUrl` del reporte.
// ---------------------------------------------------------------------------
describe("FCM payload excludes the report's free text and photoUrl (health data)", () => {
  const athleteUid = "athlete-privacy";
  const trainerId = "trainer-privacy";
  const sessionId = "session-privacy";
  const secretText = "Me tiró la rodilla derecha en la última serie";
  const secretPhotoUrl =
    "https://firebasestorage.googleapis.com/v0/b/x/o/sessionFeedback%2Fsecret?alt=media&token=abc123";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, trainerId);
    await seedTrainerLink(athleteUid, trainerId);
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("never leaks text or photoUrl into notification body or data", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback({ text: secretText, photoUrl: secretPhotoUrl }),
      mock,
    );

    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;

    const serialized = JSON.stringify(callArg);
    expect(serialized).not.toContain(secretText);
    expect(serialized).not.toContain(secretPhotoUrl);
    expect(serialized).not.toContain("token=abc123");
  });

  it("tampoco los deja en el HISTORIAL del PF, que sobrevive al borrado", async () => {
    // El payload de FCM se va con la notificación; el historial NO. `sendFcm`
    // escribe title/body en `users/{trainerId}/notifications`, un inbox de
    // terceros que el cascade de borrado de cuenta no barre (QA-CMP-008,
    // docs/security.md §2.2.1) y que tampoco se limpia cuando el alumno
    // revoca el grant. Es el lugar donde un dato de salud se queda para
    // siempre, así que se testea aparte del payload.
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback({ text: secretText, photoUrl: secretPhotoUrl }),
      makeMockMessaging(),
    );

    const inbox = await db()
      .collection("users")
      .doc(trainerId)
      .collection("notifications")
      .get();
    expect(inbox.empty).toBe(false);

    const serialized = JSON.stringify(inbox.docs.map((d) => d.data()));
    expect(serialized).not.toContain(secretText);
    expect(serialized).not.toContain(secretPhotoUrl);
    expect(serialized).not.toContain("token=abc123");
  });
});

// ---------------------------------------------------------------------------
// EL BLOQUEANTE: un grant SIN `trainer_links` activo no despacha.
//
// `session_shares/{athleteId}` es client-writable y firestore.rules (~1796) lo
// valida con `trainerId is string` y NADA MÁS: sin chequeo de rol, sin chequeo
// de vínculo. O sea que cualquier alumno autenticado apunta SU grant al uid que
// quiera —`userPublicProfiles` es world-readable, los uids se enumeran— y hasta
// el commit anterior este trigger le mandaba a esa víctima un push con texto
// que el atacante controla (`exerciseName` es client-side; firestore.rules
// ~1885 le limita el LARGO, nunca lo cruza contra un ejercicio real) más una
// fila permanente en su inbox de `users/{uid}/notifications`.
//
// Nada lo reparaba solo: `sync-session-share.ts` corre `onDocumentWritten`
// sobre `trainer_links/{linkId}`, así que un atacante SIN vínculos no dispara
// ese trigger jamás y el grant forjado se queda ahí para siempre.
//
// Estos casos son la red. Si alguno se pone verde por el motivo equivocado —o
// se borra— el agujero vuelve sin que nadie se entere.
// ---------------------------------------------------------------------------
describe("forged session_shares grant (no active trainer_link) → does NOT dispatch", () => {
  const attackerUid = "athlete-forger";
  const victimUid = "victim-not-a-trainer";
  const sessionId = "session-forged";

  beforeEach(async () => {
    // La víctima tiene token: si el despacho saliera, saldría de verdad. El
    // test no puede pasar por no haber a quién notificar.
    await seedUser(victimUid, ["victim-token"]);
    await seedUserPublicProfile(attackerUid, "Ana Atleta");
    // El grant forjado, tal cual lo escribiría el atacante desde el cliente.
    await seedSessionShare(attackerUid, victimUid);
    // Y NINGÚN trainer_links: el atacante no está vinculado con nadie.
  });

  afterEach(async () => {
    await cleanup(attackerUid, victimUid);
  });

  it("never calls sendEachForMulticast for a grant nobody ever linked", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("no le deja tampoco una fila en el inbox, que es la mitad que NO se borra", async () => {
    // El push se pierde si el teléfono está apagado; la fila de
    // `users/{uid}/notifications` NO. Es la parte del ataque que persiste, y el
    // cascade de borrado de cuenta no la barre (QA-CMP-008, docs/security.md
    // §2.2.1). Por eso se assertea aparte del despacho: cortar el envío sin
    // cortar la escritura habría dejado vivo el spam duradero.
    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    const inbox = await db()
      .collection("users")
      .doc(victimUid)
      .collection("notifications")
      .get();
    expect(inbox.empty).toBe(true);
  });

  // Tercer canal del mismo ataque, y el que MÁS dura: un mail a la casilla de
  // la víctima no se borra apagando el teléfono ni cerrando la cuenta, y le
  // llega desde nuestro dominio verificado. Si la guarda cubriera el push y no
  // el outbox, el vector seguiría abierto por el peor lado.
  it("tampoco le encola un mail a la víctima", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    expect(await queuedMailFor(victimUid)).toHaveLength(0);
  });

  it("tampoco despacha con texto controlado por el atacante en exerciseName", async () => {
    // `exerciseName` va VERBATIM al cuerpo del push y firestore.rules ~1885
    // solo le mira el largo. Era el payload del ataque: elegís a quién le
    // llega Y qué dice. Se pinea explícito para que quede escrito que el
    // vector completo está cerrado, no solo el destinatario.
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback({ exerciseName: "URGENTE: entrá a treino-premios.example" }),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Grant VENCIDO: hubo vínculo, ya no está activo. Mismo desenlace, otra causa.
// ---------------------------------------------------------------------------
describe("stale grant (trainer_link exists but is no longer active) → does NOT dispatch", () => {
  const athleteUid = "athlete-stale";
  const trainerId = "trainer-stale";
  const sessionId = "session-stale";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    // El share sobrevivió al vínculo: `sync-session-share.ts` lo borra cuando
    // el link deja de estar `active` (~:222), pero ese delete no tiene reintento
    // —no hay un solo `retry: true` en el módulo—, así que un borrado perdido
    // deja el grant huérfano de forma permanente y silenciosa. Ese es el
    // estado que se siembra acá.
    await seedSessionShare(athleteUid, trainerId);
    await seedTrainerLink(athleteUid, trainerId, "terminated");
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("resolves without throwing and never dispatches", async () => {
    // Sin tirar: un grant vencido no es un error, es estado. Un throw acá
    // haría reintentar a Cloud Functions una y otra vez sobre algo que nunca
    // va a mejorar solo.
    const mock = makeMockMessaging();

    await expect(
      notifyOnExerciseFeedbackHandler(testApp, athleteUid, sessionId, makeFeedback(), mock),
    ).resolves.toBeUndefined();

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// La contraparte positiva: vínculo `active` de verdad → el push SÍ sale.
// Sin esto, la guarda podría estar cortando TODO y la suite seguiría verde.
// ---------------------------------------------------------------------------
describe("legitimate active trainer_link → still dispatches", () => {
  const athleteUid = "athlete-legit";
  const trainerId = "trainer-legit";
  const sessionId = "session-legit";

  beforeEach(async () => {
    await seedUser(trainerId, ["legit-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, trainerId);
    await seedTrainerLink(athleteUid, trainerId, "active");
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("dispatches to the linked trainer when the link is genuinely active", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).toHaveBeenCalledTimes(1);
    const callArg = (mock.sendEachForMulticast as jest.Mock).mock
      .calls[0][0] as admin.messaging.MulticastMessage;
    expect(callArg.tokens).toEqual(["legit-token"]);
  });

  it("no confunde el vínculo de OTRO alumno con el propio", async () => {
    // La query filtra por athleteId Y trainerId. Si algún día alguien la afloja
    // a un solo filtro, un vínculo cualquiera del mismo PF alcanzaría para
    // habilitar el despacho de un alumno que no es suyo. Acá el único link del
    // par correcto se borra y queda uno del PF con OTRO alumno.
    await cleanupLinks(athleteUid, trainerId);
    await seedTrainerLink("otro-alumno-legit", trainerId, "active");

    const mock = makeMockMessaging();
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
    await cleanupLinks("otro-alumno-legit", trainerId);
  });
});

// ---------------------------------------------------------------------------
// El MISMO ataque, pero desde una cuenta que sí tiene PF. Este caso lo
// encontró la verificación por mutación: aflojar el filtro de `trainerId` de
// la query dejaba los otros cinco tests en VERDE, o sea que la cláusula estaba
// sin pinear. Y es el escenario MÁS probable de los dos: un atacante real es
// un usuario real de la app, con su vínculo legítimo puesto. El de arriba
// —cuenta sin ningún vínculo— es el caso de laboratorio.
//
// Sin el filtro por trainerId, la query encontraba el vínculo LEGÍTIMO con su
// propio PF y lo tomaba como permiso para despachar al uid que dijera el
// grant. El vínculo tiene que ser con EL DESTINATARIO, no con cualquiera.
// ---------------------------------------------------------------------------
describe("athlete WITH a real link, grant forged at a third party → does NOT dispatch", () => {
  const attackerUid = "athlete-has-real-pf";
  const realTrainerId = "trainer-real-pf";
  const victimUid = "victim-third-party";
  const sessionId = "session-forged-with-link";

  beforeEach(async () => {
    await seedUser(realTrainerId, ["real-pf-token"]);
    await seedUser(victimUid, ["victim-token"]);
    await seedUserPublicProfile(attackerUid, "Ana Atleta");
    // Vínculo legítimo y activo con su PF de verdad.
    await seedTrainerLink(attackerUid, realTrainerId, "active");
    // Pero el grant apunta a la víctima, no al PF.
    await seedSessionShare(attackerUid, victimUid);
  });

  afterEach(async () => {
    await cleanup(attackerUid, realTrainerId, victimUid);
    await cleanupLinks(attackerUid, realTrainerId, victimUid);
  });

  it("no dispatches at all — un vínculo con OTRO no habilita al destinatario", async () => {
    const mock = makeMockMessaging();

    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback(),
      mock,
    );

    expect(mock.sendEachForMulticast as jest.Mock).not.toHaveBeenCalled();
  });

  it("y el PF legítimo tampoco recibe nada — no se 'corrige' el destinatario", async () => {
    // Redirigir el push al PF real sería un arreglo tentador y equivocado: el
    // grant es el que elige destinatario, y si miente no hay a quién notificar.
    // Inventarle un destinatario al reporte lo mandaría a alguien que el alumno
    // no eligió, y esto es dato de salud.
    await notifyOnExerciseFeedbackHandler(
      testApp,
      attackerUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    for (const uid of [victimUid, realTrainerId]) {
      const inbox = await db()
        .collection("users")
        .doc(uid)
        .collection("notifications")
        .get();
      expect(inbox.empty).toBe(true);
    }
  });
});

// ---------------------------------------------------------------------------
// EL MAIL AL PF — la contraparte de este push.
//
// De los eventos que tienen push y no tenían mail, este es el único con
// consecuencia FÍSICA: el alumno avisa que algo le duele mientras entrena. El
// push se pierde en la pantalla de bloqueo de un teléfono que nadie mira; el
// mail no.
//
// Lo que se pinea acá es el par de decisiones que definieron el feature —
// dedupe por SESIÓN y transaccional sin `prefKey`— más el invariante de
// privacidad, que en mail pesa más que en push: el mail queda en la bandeja
// para siempre y además pasa por Resend, que es un tercero.
// ---------------------------------------------------------------------------
describe("mail al PF: se encola junto con el push", () => {
  const athleteUid = "athlete-mail";
  const trainerId = "trainer-mail";
  const sessionId = "session-mail";
  const otherSessionId = "session-mail-2";

  beforeEach(async () => {
    await seedUser(trainerId, ["trainer-token"]);
    await seedUserPublicProfile(athleteUid, "Ana Atleta");
    await seedSessionShare(athleteUid, trainerId);
    await seedTrainerLink(athleteUid, trainerId);
  });

  afterEach(async () => {
    await cleanup(athleteUid, trainerId);
    await cleanupLinks(athleteUid, trainerId);
  });

  it("encola un mail dirigido al PF, con la clave derivada de (alumno, sesión)", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    const snap = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey("discomfort-reported", `${athleteUid}_${sessionId}`, trainerId))
      .get();

    expect(snap.exists).toBe(true);
    const doc = snap.data() as MailQueueDoc;
    expect(doc.toUid).toBe(trainerId);
    expect(doc.kind).toBe("discomfort-reported");
    expect(doc.status).toBe("pending");
    expect(doc.params.athleteName).toBe("Ana Atleta");
  });

  // El CTA del template cae por defecto en la entrada del ATLETA. Acá el
  // destinatario es el profe: sin este parámetro el mail lo deja mirando la
  // pantalla equivocada. Mismo patrón que `link-requested`.
  it("manda el CTA a la entrada del PF, no a la del atleta", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    const [doc] = await queuedMailFor(trainerId);
    // No la entrada bare: manda directo al perfil del atleta que reporto la
    // molestia, con `to=alumno` y su uid.
    expect(doc.params.ctaUrl).toBe(
      trainerEntry({ to: "alumno", athleteId: athleteUid }),
    );
  });

  // Decisión 1: transaccional. No existe un ajuste razonable que diga "no me
  // avises cuando a mi alumno le duele algo", y ofrecerlo en `kNotifTypes`
  // sería darle al PF una forma silenciosa de fallarle a su cliente. Si alguien
  // le agrega un `prefKey`, tiene que agregar la fila en el Coach Hub en el
  // mismo commit — si no, el opt-out existe y el usuario no lo puede ver.
  it("no lleva prefKey: es transaccional, como payment-overdue", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback(),
      makeMockMessaging(),
    );

    const [doc] = await queuedMailFor(trainerId);
    expect(doc.prefKey).toBeUndefined();
  });

  // El doc de la cola es Firestore, y de ahí lo lee `sendQueuedMail` para
  // renderizar. Guardar el dato de salud acá lo filtraría igual aunque el
  // template no lo imprima — y encima lo dejaría en una colección con otro
  // ciclo de vida. Se corta en el productor, no solo en la plantilla.
  it("el doc de la cola no guarda el texto, la foto ni el ejercicio", async () => {
    const secretText = "Me tiró la rodilla derecha en la última serie";
    const secretPhotoUrl =
      "https://firebasestorage.googleapis.com/v0/b/x/o/sessionFeedback%2Fsecret?alt=media&token=abc123";

    await notifyOnExerciseFeedbackHandler(
      testApp,
      athleteUid,
      sessionId,
      makeFeedback({ text: secretText, photoUrl: secretPhotoUrl }),
      makeMockMessaging(),
    );

    const serialized = JSON.stringify(await queuedMailFor(trainerId));
    expect(serialized).not.toContain(secretText);
    expect(serialized).not.toContain(secretPhotoUrl);
    expect(serialized).not.toContain("token=abc123");
    expect(serialized).not.toContain("Sentadilla");
  });

  // Decisión 2, y la mitad cara: cinco ejercicios con molestia en la MISMA
  // sesión son UN evento ("esta sesión le dolió"), no cinco. Cinco mails a la
  // misma persona por la misma sesión entrenan al PF a filtrar el remitente, y
  // el que se pierde después es el que importa. El detalle está a un toque, en
  // la app, detrás del read gateado.
  it("cinco ejercicios de la misma sesión producen UN solo mail", async () => {
    for (let i = 0; i < 5; i++) {
      await notifyOnExerciseFeedbackHandler(
        testApp,
        athleteUid,
        sessionId,
        makeFeedback({ exerciseId: `ex-${i}`, exerciseName: `Ejercicio ${i}` }),
        makeMockMessaging(),
      );
    }

    expect(await queuedMailFor(trainerId)).toHaveLength(1);
  });

  // La otra mitad: colapsar por sesión NO puede volverse "un mail y listo". La
  // sesión del martes es un evento nuevo y merece su propio aviso.
  it("otra sesión del mismo alumno sí produce un mail nuevo", async () => {
    await notifyOnExerciseFeedbackHandler(
      testApp, athleteUid, sessionId, makeFeedback(), makeMockMessaging(),
    );
    await notifyOnExerciseFeedbackHandler(
      testApp, athleteUid, otherSessionId, makeFeedback(), makeMockMessaging(),
    );

    expect(await queuedMailFor(trainerId)).toHaveLength(2);
  });

  // Los eventos de Cloud Functions son at-least-once. El mismo reporte
  // redisparado tiene que resolver al MISMO doc — es la razón de ser del
  // outbox, y se verifica en el camino real, no solo en `mail-outbox.test.ts`.
  it("un trigger redisparado no produce un segundo mail", async () => {
    for (let i = 0; i < 3; i++) {
      await notifyOnExerciseFeedbackHandler(
        testApp, athleteUid, sessionId, makeFeedback(), makeMockMessaging(),
      );
    }

    expect(await queuedMailFor(trainerId)).toHaveLength(1);
  });
});
