/**
 * Integration tests for the transactional email outbox.
 *
 * Tests run against a running Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * These cover the two properties the whole design exists for:
 *   - a re-fired trigger never produces a second email
 *   - a batched recurring series collapses to ONE email
 *
 * Plus the consumer's failure taxonomy: retriable failures stay `pending` and
 * re-throw so the platform redelivers; permanent ones land on `failed` and stop.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { Messaging } from "firebase-admin/messaging";
import { Auth, getAuth } from "firebase-admin/auth";
import { logger } from "firebase-functions";
import { verificarToken } from "../mail/baja-de-promocionales";
import { enqueueMail, dedupeKey } from "../mail/enqueue-mail";
import { sendQueuedMail, sendQueuedMailHandler } from "../mail/send-queued-mail";
import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "../mail/types";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";
import { MailSendError, MailSender, OutboundMail } from "../mail/resend-client";
import { notifyOnLinkChangeHandler } from "../notifications/notify-link-change";
import { notifyOnAppointmentHandler } from "../notifications/notify-appointment";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "mail-outbox-test");
});

afterAll(async () => {
  await deleteApp(testApp);
});

const db = () => getFirestore(testApp);

async function readQueueDoc(id: string): Promise<MailQueueDoc | undefined> {
  const snap = await db().collection(MAIL_QUEUE_COLLECTION).doc(id).get();
  return snap.data() as MailQueueDoc | undefined;
}

async function purge(...ids: string[]): Promise<void> {
  for (const id of ids) {
    await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(id)
      .delete()
      .catch(() => undefined);
  }
}

/** A sender that records what it was asked to send and always succeeds. */
function makeOkSender(): MailSender & { sent: OutboundMail[] } {
  const sent: OutboundMail[] = [];
  return {
    sent,
    async send(mail: OutboundMail) {
      sent.push(mail);
    },
  };
}

/** A sender that always fails with the given HTTP status. */
function makeFailingSender(status: number): MailSender {
  return {
    async send() {
      throw new MailSendError(`resend: HTTP ${status}`, status);
    },
  };
}

// ---------------------------------------------------------------------------
// Idempotency — the reason the outbox exists
// ---------------------------------------------------------------------------
describe("enqueueMail: at-least-once triggers cannot produce two emails", () => {
  const toUid = "athlete-outbox-1";
  const scope = "appt-outbox-1";
  const id = dedupeKey("appointment-confirmed", scope, toUid);

  afterEach(() => purge(id));

  it("creates one pending document on the first call", async () => {
    const created = await enqueueMail(testApp, {
      toUid,
      kind: "appointment-confirmed",
      scope,
      params: { trainerName: "Jose" },
    });

    expect(created).toBe(id);

    const doc = await readQueueDoc(id);
    expect(doc?.status).toBe("pending");
    expect(doc?.attempts).toBe(0);
    expect(doc?.toUid).toBe(toUid);
  });

  it("returns null and writes nothing on a redelivered event", async () => {
    await enqueueMail(testApp, {
      toUid,
      kind: "appointment-confirmed",
      scope,
      params: { trainerName: "Jose" },
    });

    const second = await enqueueMail(testApp, {
      toUid,
      kind: "appointment-confirmed",
      scope,
      params: { trainerName: "Jose" },
    });

    expect(second).toBeNull();

    const all = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .where("toUid", "==", toUid)
      .get();
    expect(all.size).toBe(1);
  });

  // The specific regression `create()` (rather than `set()`) protects against:
  // re-enqueueing an ALREADY SENT mail would flip it back to pending and the
  // consumer would send it a second time.
  it("never resurrects a document that was already sent", async () => {
    await enqueueMail(testApp, {
      toUid,
      kind: "appointment-confirmed",
      scope,
      params: { trainerName: "Jose" },
    });
    await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(id)
      .update({ status: "sent" });

    await enqueueMail(testApp, {
      toUid,
      kind: "appointment-confirmed",
      scope,
      params: { trainerName: "Jose" },
    });

    const doc = await readQueueDoc(id);
    expect(doc?.status).toBe("sent");
  });
});

// ---------------------------------------------------------------------------
// Series collapse — the batched-recurring case
// ---------------------------------------------------------------------------
describe("enqueueMail: a batched series collapses to one email", () => {
  const toUid = "athlete-outbox-series";
  const recurringId = "recurring-outbox-1";
  const id = dedupeKey("appointment-series-created", recurringId, toUid);

  afterEach(() => purge(id));

  // createRecurringByTrainer commits a whole Mon/Wed/Fri quarter in one
  // WriteBatch — ~36 documents, so notifyOnAppointment fires ~36 times.
  it("writes ONE document for 36 occurrences of the same recurringId", async () => {
    const results = await Promise.all(
      Array.from({ length: 36 }, () =>
        enqueueMail(testApp, {
          toUid,
          kind: "appointment-series-created",
          scope: recurringId,
          params: { trainerName: "Jose" },
        }),
      ),
    );

    // Exactly one call won the create; the other 35 saw ALREADY_EXISTS.
    expect(results.filter((r) => r !== null)).toHaveLength(1);

    const all = await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .where("toUid", "==", toUid)
      .get();
    expect(all.size).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// The recipient belongs in the key
// ---------------------------------------------------------------------------
describe("dedupeKey: two recipients of one event both get their mail", () => {
  const trainerId = "trainer-outbox-2";
  const athleteId = "athlete-outbox-2";
  const scope = "appt-outbox-2";
  const trainerDoc = dedupeKey("appointment-cancelled", scope, trainerId);
  const athleteDoc = dedupeKey("appointment-cancelled", scope, athleteId);

  afterEach(() => purge(trainerDoc, athleteDoc));

  // A cancellation with no `cancelledBy` notifies BOTH parties. Without the uid
  // in the key the two mails would collide and one person would hear nothing.
  it("produces distinct documents for the same appointment", async () => {
    await enqueueMail(testApp, {
      toUid: trainerId,
      kind: "appointment-cancelled",
      scope,
      params: {},
    });
    await enqueueMail(testApp, {
      toUid: athleteId,
      kind: "appointment-cancelled",
      scope,
      params: {},
    });

    expect(trainerDoc).not.toBe(athleteDoc);
    expect((await readQueueDoc(trainerDoc))?.toUid).toBe(trainerId);
    expect((await readQueueDoc(athleteDoc))?.toUid).toBe(athleteId);
  });
});

// ---------------------------------------------------------------------------
// prefKey wiring — only where the recipient can actually see the toggle
// ---------------------------------------------------------------------------
describe("producers: prefKey is set only for recipients who have a screen", () => {
  const trainerId = "trainer-prefkey";
  const athleteId = "athlete-prefkey";

  function noopMessaging(): Messaging {
    return {
      sendEachForMulticast: jest.fn(async () => ({
        successCount: 0,
        failureCount: 0,
        responses: [],
      })),
    } as unknown as Messaging;
  }

  // The trainer's Coach Hub settings expose the `nueva_solicitud` row, so their
  // toggle has to be honoured rather than bypassed as transactional.
  it("link-requested carries prefKey nueva_solicitud", async () => {
    const linkId = "link-prefkey-1";
    const id = dedupeKey("link-requested", linkId, trainerId);

    await notifyOnLinkChangeHandler(
      testApp,
      linkId,
      undefined,
      { trainerId, athleteId, status: "pending" },
      noopMessaging(),
    );

    expect((await readQueueDoc(id))?.prefKey).toBe("nueva_solicitud");
    await purge(id);
  });

  // The same cancellation reaches both parties, but only the trainer has a
  // settings screen. Gating the athlete on a preference they cannot see would
  // be an opt-out with no way back in.
  it("appointment-cancelled sets prefKey for the trainer and NOT the athlete",
    async () => {
      const apptId = "appt-prefkey-1";
      const trainerDoc = dedupeKey("appointment-cancelled", apptId, trainerId);
      const athleteDoc = dedupeKey("appointment-cancelled", apptId, athleteId);

      await notifyOnAppointmentHandler(
        testApp,
        apptId,
        { trainerId, athleteId, status: "confirmed" },
        // No cancelledBy → both parties are notified (legacy shape).
        { trainerId, athleteId, status: "cancelled" },
        noopMessaging(),
      );

      expect((await readQueueDoc(trainerDoc))?.prefKey).toBe("sesion_cancelada");
      expect((await readQueueDoc(athleteDoc))?.prefKey).toBeUndefined();

      await purge(trainerDoc, athleteDoc);
    });

  // Losing a payment deadline is not something a trainer preference should be
  // able to silence for an athlete who has no preferences screen at all.
  it("appointment-confirmed stays transactional (no prefKey)", async () => {
    const apptId = "appt-prefkey-2";
    const id = dedupeKey("appointment-confirmed", apptId, athleteId);

    await notifyOnAppointmentHandler(
      testApp,
      apptId,
      undefined,
      { trainerId, athleteId, status: "confirmed" },
      noopMessaging(),
    );

    const doc = await readQueueDoc(id);
    expect(doc).toBeDefined();
    expect(doc?.prefKey).toBeUndefined();
    await purge(id);
  });
});

// ---------------------------------------------------------------------------
// Consumer behaviour
// ---------------------------------------------------------------------------
describe("sendQueuedMailHandler", () => {
  const mailId = "consumer-test-1";
  const uid = "athlete-consumer-1";

  async function seedQueueDoc(
    overrides: Partial<MailQueueDoc> = {},
  ): Promise<void> {
    await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(mailId)
      .set({
        toUid: uid,
        kind: "appointment-confirmed",
        params: { trainerName: "Jose" },
        status: "pending",
        attempts: 0,
        createdAt: FieldValue.serverTimestamp(),
        ...overrides,
      });
  }

  beforeEach(async () => {
    await getAuth(testApp)
      .createUser({ uid, email: "consumer1@example.com" })
      .catch(() => undefined);
  });

  afterEach(async () => {
    await purge(mailId);
    await getAuth(testApp).deleteUser(uid).catch(() => undefined);
  });

  it("sends and marks the document sent", async () => {
    await seedQueueDoc();
    const sender = makeOkSender();
    const data = await readQueueDoc(mailId);

    await sendQueuedMailHandler(testApp, mailId, data, sender);

    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0].to).toBe("consumer1@example.com");
    // The queue doc id doubles as Resend's Idempotency-Key.
    expect(sender.sent[0].idempotencyKey).toBe(mailId);

    const doc = await readQueueDoc(mailId);
    expect(doc?.status).toBe("sent");
    expect(doc?.attempts).toBe(1);
  });

  // Covers the window where the Resend call landed but the status write did not.
  // ── El snapshot del evento no es la verdad ──────────────────────────────
  //
  //  es , así que  congela el
  // documento tal como nació. Si algo lo actualiza entre la creación y el
  // envío, renderizar desde ese snapshot manda contenido viejo.
  //
  // No es teórico:  existe para
  // pisarle el link de reseteo al mail encolado cuando un segundo pedido
  // invalida el anterior. Sin releer, esa actualización se escribe en
  // Firestore y el mail sale igual con el link muerto — el arreglo del
  // throttle quedaba en cosmético y los tests que miran SÓLO el documento no
  // lo veían.
  it("renderiza los params ACTUALES, no los de la creación", async () => {
    await seedQueueDoc({ params: { trainerName: "Jose" } });
    // Lo que el trigger le pasaría al handler: el snapshot de la creación.
    const snapshotDeLaCreacion = await readQueueDoc(mailId);

    // Alguien actualiza el doc antes de que salga el mail.
    await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(mailId)
      .update({ params: { trainerName: "Coti" } });

    const sender = makeOkSender();
    await sendQueuedMailHandler(testApp, mailId, snapshotDeLaCreacion, sender);

    expect(sender.sent).toHaveLength(1);
    const cuerpo = sender.sent[0].html + sender.sent[0].text;
    expect(cuerpo).toContain("Coti");
    expect(cuerpo).not.toContain("Jose");
  });

  it("no manda nada si el documento fue borrado antes del envío", async () => {
    await seedQueueDoc();
    const snapshotDeLaCreacion = await readQueueDoc(mailId);
    await db().collection(MAIL_QUEUE_COLLECTION).doc(mailId).delete();

    const sender = makeOkSender();
    await sendQueuedMailHandler(testApp, mailId, snapshotDeLaCreacion, sender);

    expect(sender.sent).toHaveLength(0);
  });

  it("does not re-send a document already marked sent", async () => {
    await seedQueueDoc({ status: "sent" });
    const sender = makeOkSender();

    await sendQueuedMailHandler(
      testApp,
      mailId,
      await readQueueDoc(mailId),
      sender,
    );

    expect(sender.sent).toHaveLength(0);
  });

  it("keeps a 429 pending and re-throws so the platform redelivers", async () => {
    await seedQueueDoc();

    await expect(
      sendQueuedMailHandler(
        testApp,
        mailId,
        await readQueueDoc(mailId),
        makeFailingSender(429),
      ),
    ).rejects.toThrow(MailSendError);

    const doc = await readQueueDoc(mailId);
    expect(doc?.status).toBe("pending");
    expect(doc?.attempts).toBe(1);
  });

  // A 422 means Resend rejected the payload; it will reject it identically
  // forever, so retrying only burns quota.
  it("marks a 422 failed and does NOT re-throw", async () => {
    await seedQueueDoc();

    await expect(
      sendQueuedMailHandler(
        testApp,
        mailId,
        await readQueueDoc(mailId),
        makeFailingSender(422),
      ),
    ).resolves.toBeUndefined();

    const doc = await readQueueDoc(mailId);
    expect(doc?.status).toBe("failed");
  });

  it("stops once attempts are exhausted", async () => {
    await seedQueueDoc({ attempts: 5 });
    const sender = makeOkSender();

    await sendQueuedMailHandler(
      testApp,
      mailId,
      await readQueueDoc(mailId),
      sender,
    );

    expect(sender.sent).toHaveLength(0);
    expect((await readQueueDoc(mailId))?.status).toBe("failed");
  });

  it("fails permanently when the recipient has no address", async () => {
    await getAuth(testApp).deleteUser(uid).catch(() => undefined);
    await seedQueueDoc();
    const sender = makeOkSender();

    await sendQueuedMailHandler(
      testApp,
      mailId,
      await readQueueDoc(mailId),
      sender,
    );

    expect(sender.sent).toHaveLength(0);
    const doc = await readQueueDoc(mailId);
    expect(doc?.status).toBe("failed");
    expect(doc?.lastError).toContain("no email address");
  });

  it("honours an email channel the user turned off", async () => {
    await db()
      .collection("users")
      .doc(uid)
      .set({ notificationPrefs: { pago_recibido: { email: false } } });
    await seedQueueDoc({ prefKey: "pago_recibido" });
    const sender = makeOkSender();

    await sendQueuedMailHandler(
      testApp,
      mailId,
      await readQueueDoc(mailId),
      sender,
    );

    expect(sender.sent).toHaveLength(0);
    await db().collection("users").doc(uid).delete();
  });

  it("sends transactional mail regardless of preferences (no prefKey)", async () => {
    await db()
      .collection("users")
      .doc(uid)
      .set({ notificationPrefs: { pago_recibido: { email: false } } });
    await seedQueueDoc();
    const sender = makeOkSender();

    await sendQueuedMailHandler(
      testApp,
      mailId,
      await readQueueDoc(mailId),
      sender,
    );

    expect(sender.sent).toHaveLength(1);
    await db().collection("users").doc(uid).delete();
  });
});

// ---------------------------------------------------------------------------
// El pie de baja de los correos promocionales
//
// Decreto 1558/01, Anexo I, art. 27, párr. 3. El link se calcula AL ENVIAR, con
// la clave que el handler recibe (como recibe el `sender`), y no se persiste.
// ---------------------------------------------------------------------------
describe("sendQueuedMailHandler: pie de baja de los correos promocionales", () => {
  const mailId = "baja-pie-test-1";
  const uid = "athlete-baja-pie-1";
  const BAJA_KEY = "clave-de-prueba-de-baja";
  const PREF = ATHLETE_PROSPECT_PREF_KEY;
  const SIN_PIE = ["correos-promocionales", "#t=", "Ley 25.326", "Decreto 1558", "BACKHAUSTIN"];

  /** El mail comercial por excelencia: lleva `prefKey` y se frena entero. */
  const comercial: Partial<MailQueueDoc> = {
    kind: "athlete-coverage-lost",
    params: {},
    prefKey: PREF,
  };

  /** El operativo con un bloque de venta adentro: se frena el BLOQUE. */
  const conBloque: Partial<MailQueueDoc> = {
    kind: "limit-reached",
    params: { limit: 2, blockedCount: 3, ctaUrl: "https://app.gettreino.com/?to=facturacion" },
    bloqueComercial: PREF,
  };

  const URL_DE_BAJA = /https:\/\/gettreino\.com\/es\/correos-promocionales\/baja#t=([A-Za-z0-9_.-]+)/;

  async function seed(overrides: Partial<MailQueueDoc> = {}): Promise<void> {
    await db()
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(mailId)
      .set({
        toUid: uid,
        kind: "appointment-confirmed",
        params: { trainerName: "Jose" },
        status: "pending",
        attempts: 0,
        createdAt: FieldValue.serverTimestamp(),
        ...overrides,
      });
  }

  async function setPrefs(prefs: Record<string, unknown>): Promise<void> {
    await db().collection("users").doc(uid).set({ notificationPrefs: prefs });
  }

  /** Corre el handler sobre lo que hay en la cola AHORA, como lo haría el trigger. */
  async function enviar(sender: MailSender, bajaKey?: string): Promise<void> {
    await sendQueuedMailHandler(testApp, mailId, await readQueueDoc(mailId), sender, bajaKey);
  }

  beforeEach(async () => {
    await getAuth(testApp)
      .createUser({ uid, email: "baja-pie@example.com" })
      .catch(() => undefined);
  });

  afterEach(async () => {
    jest.restoreAllMocks();
    await purge(mailId);
    await db().collection("users").doc(uid).delete().catch(() => undefined);
    await getAuth(testApp).deleteUser(uid).catch(() => undefined);
  });

  describe("mail con `prefKey` de la allowlist (comercial)", () => {
    it("lleva el link de baja, firmado para ESE uid y esa preferencia", async () => {
      await seed(comercial);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      const { html, text } = sender.sent[0];
      const url = text.match(URL_DE_BAJA);
      expect(url).not.toBeNull();
      // El mismo link en las dos partes del mail.
      expect(html).toContain(`<a href="${url![0]}"`);
      // Y el token dice quién es y qué apaga: el uid sale del DOCUMENTO.
      expect(verificarToken(url![1], BAJA_KEY)).toEqual({ uid, prefKey: PREF });
      expect(text).toContain("Ley 25.326");
      expect(text).toContain("Responsable: BACKHAUSTIN S.A.S.");
    });

    it("el token NO sirve con otra clave", async () => {
      await seed(comercial);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      const token = sender.sent[0].text.match(URL_DE_BAJA)![1];
      expect(verificarToken(token, "otra-clave")).toBeNull();
    });

    it("NO persiste el link en el documento de la cola", async () => {
      await seed(comercial);

      await enviar(makeOkSender(), BAJA_KEY);

      const doc = await readQueueDoc(mailId);
      expect(doc?.status).toBe("sent");
      // El link es un HMAC: se recalcula en cada envío, y guardarlo dejaría una
      // credencial por cada mail comercial en la cola.
      const crudo = JSON.stringify(doc);
      for (const huella of ["correos-promocionales", "#t=", "v1."]) {
        expect(crudo).not.toContain(huella);
      }
      expect(Object.keys(doc ?? {}).sort()).toEqual(
        ["attempts", "createdAt", "kind", "params", "prefKey", "sentAt", "status", "toUid"],
      );
    });

    it("con la preferencia apagada NO sale, y no hace falta clave", async () => {
      await setPrefs({ [PREF]: { email: false } });
      await seed(comercial);
      const sender = makeOkSender();

      await enviar(sender);

      expect(sender.sent).toHaveLength(0);
      expect((await readQueueDoc(mailId))?.lastError).toBe("email channel off");
    });

    it("con la preferencia prendida o ausente sale CON pie", async () => {
      await setPrefs({ [PREF]: { email: true } });
      await seed(comercial);
      const prendida = makeOkSender();
      await enviar(prendida, BAJA_KEY);

      await purge(mailId);
      await db().collection("users").doc(uid).delete();
      await seed(comercial);
      const ausente = makeOkSender();
      await enviar(ausente, BAJA_KEY);

      for (const sender of [prendida, ausente]) {
        expect(sender.sent).toHaveLength(1);
        expect(sender.sent[0].text).toMatch(URL_DE_BAJA);
      }
    });

    it("FALLA CERRADO sin clave: no sale, `failed`, y grita en el log", async () => {
      const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
      await seed(comercial);
      const sender = makeOkSender();

      // Sin pasar la clave (el default) y pasándola vacía: lo mismo.
      await enviar(sender);
      await purge(mailId);
      await seed(comercial);
      await enviar(sender, "");

      expect(sender.sent).toHaveLength(0);
      const doc = await readQueueDoc(mailId);
      expect(doc?.status).toBe("failed");
      expect(doc?.lastError).toBe("sin clave de baja");
      expect(doc?.attempts).toBe(1);
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("sin clave de baja"),
        expect.objectContaining({ mailId }),
      );
    });

    it("un uid que no entra en el token también falla cerrado, sin tirar", async () => {
      // No pasa con los uids de Auth (máximo 128); la dirección se simula.
      jest.spyOn(logger, "error").mockImplementation(() => undefined);
      jest
        .spyOn(Auth.prototype, "getUser")
        .mockResolvedValue({ email: "uid-largo@example.com" } as never);
      await seed({ ...comercial, toUid: "u".repeat(151) });
      const sender = makeOkSender();

      await expect(enviar(sender, BAJA_KEY)).resolves.toBeUndefined();

      expect(sender.sent).toHaveLength(0);
      const doc = await readQueueDoc(mailId);
      expect(doc?.status).toBe("failed");
      expect(doc?.lastError).toBe("link de baja no representable");
    });

    it("el mail que falla cerrado NO se reintenta", async () => {
      jest.spyOn(logger, "error").mockImplementation(() => undefined);
      await seed(comercial);

      // No tira: tirar haría que la plataforma lo reentregue durante una semana.
      await expect(enviar(makeOkSender(), "")).resolves.toBeUndefined();
    });
  });

  describe("mail SIN link de baja", () => {
    const algunoSinPie = async (
      overrides: Partial<MailQueueDoc>,
      sender: ReturnType<typeof makeOkSender>,
      key = BAJA_KEY,
    ) => {
      await seed(overrides);
      await enviar(sender, key);
      expect(sender.sent).toHaveLength(1);
      const cuerpo = `${sender.sent[0].html}\n${sender.sent[0].text}`;
      for (const huella of SIN_PIE) expect(cuerpo).not.toContain(huella);
    };

    it("otro `prefKey` (no es comercial)", async () => {
      await algunoSinPie(
        { kind: "link-requested", params: { athleteName: "Marta" }, prefKey: "nueva_solicitud" },
        makeOkSender(),
      );
    });

    it("sin `prefKey` (transaccional)", async () => {
      await algunoSinPie({}, makeOkSender());
    });

    it("y no necesita clave: sale igual con la clave vacía", async () => {
      await algunoSinPie({}, makeOkSender(), "");
    });

    it("destinatario `toAddress` literal, aunque lleve el `prefKey` comercial", async () => {
      // Un buzón de equipo no tiene cuenta ni preferencias a las que apuntar una baja.
      await seed({ ...comercial, toUid: "no-existe", toAddress: "equipo@example.com" });
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].to).toBe("equipo@example.com");
      for (const huella of SIN_PIE) {
        expect(`${sender.sent[0].html}\n${sender.sent[0].text}`).not.toContain(huella);
      }
    });
  });

  describe("`bloqueComercial`: se frena el bloque, no el mail", () => {
    const BLOQUE = "Si querés seguir sumando, hay planes más grandes.";

    it("preferencia APAGADA: el mail sale SIN el bloque de venta y SIN pie", async () => {
      await setPrefs({ [PREF]: { email: false } });
      await seed(conBloque);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      // Sale: lo operativo le llega a quien se opuso a lo comercial.
      expect(sender.sent).toHaveLength(1);
      const { html, text } = sender.sent[0];
      expect(text).toContain("3 alumnos quedaron en solo lectura");
      expect(text).not.toContain(BLOQUE);
      expect(html).not.toContain("VER LOS PLANES");
      expect(text).not.toContain("https://app.gettreino.com/?to=facturacion");
      for (const huella of SIN_PIE) {
        expect(html).not.toContain(huella);
        expect(text).not.toContain(huella);
      }
      expect((await readQueueDoc(mailId))?.status).toBe("sent");
    });

    it("preferencia APAGADA no necesita la clave: no hay pie que firmar", async () => {
      await setPrefs({ [PREF]: { email: false } });
      await seed(conBloque);
      const sender = makeOkSender();

      await enviar(sender, "");

      expect(sender.sent).toHaveLength(1);
    });

    it("preferencia PRENDIDA: el mail completo, CON bloque y CON pie", async () => {
      await setPrefs({ [PREF]: { email: true } });
      await seed(conBloque);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      const { html, text } = sender.sent[0];
      expect(text).toContain(BLOQUE);
      expect(html).toContain("VER LOS PLANES");
      const url = text.match(URL_DE_BAJA);
      expect(url).not.toBeNull();
      expect(verificarToken(url![1], BAJA_KEY)).toEqual({ uid, prefKey: PREF });
    });

    it("preferencia AUSENTE (sin documento de usuario): también el completo", async () => {
      await seed(conBloque);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].text).toContain(BLOQUE);
      expect(sender.sent[0].text).toMatch(URL_DE_BAJA);
    });

    it("sólo `false` explícito frena (igual que `prefKey`)", async () => {
      // `push: false` es OTRO canal; `email` sin tocar sigue contando como prendido.
      await setPrefs({ [PREF]: { push: false } });
      await seed(conBloque);
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent[0].text).toContain(BLOQUE);
      expect(sender.sent[0].text).toMatch(URL_DE_BAJA);
    });

    it("se evalúa AL ENVIAR, no al encolar: gana la oposición que llegó en el medio", async () => {
      await setPrefs({ [PREF]: { email: true } });
      await seed(conBloque);
      const alEncolar = await readQueueDoc(mailId);
      // La persona se da de baja entre que se encoló y que sale.
      await setPrefs({ [PREF]: { email: false } });
      const sender = makeOkSender();

      await sendQueuedMailHandler(testApp, mailId, alEncolar, sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].text).not.toContain(BLOQUE);
      expect(sender.sent[0].text).not.toMatch(URL_DE_BAJA);
    });

    it("preferencia PRENDIDA y clave vacía: sale SIN bloque y SIN pie, y suena la alarma", async () => {
      // El aviso operativo le tiene que llegar igual, y no puede salir contenido
      // comercial sin mecanismo de baja. El fail-closed (`failed`) es sólo para
      // los mails enteramente comerciales (`prefKey`), de arriba.
      const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
      await seed(conBloque);

      // Sin pasar la clave (el default) y pasándola vacía: lo mismo.
      for (const clave of [undefined, ""]) {
        await purge(mailId);
        await seed(conBloque);
        const sender = makeOkSender();

        await enviar(sender, clave);

        expect(sender.sent).toHaveLength(1);
        const { html, text } = sender.sent[0];
        expect(text).toContain("3 alumnos quedaron en solo lectura");
        expect(text).not.toContain(BLOQUE);
        expect(html).not.toContain("VER LOS PLANES");
        expect(text).not.toContain("https://app.gettreino.com/?to=facturacion");
        expect(html).not.toContain("https://app.gettreino.com/?to=facturacion");
        for (const huella of SIN_PIE) {
          expect(html).not.toContain(huella);
          expect(text).not.toContain(huella);
        }
        const doc = await readQueueDoc(mailId);
        expect(doc?.status).toBe("sent");
        expect(doc?.lastError).toBeUndefined();
      }
      // Para el monitoreo: un mail comercial degradado no puede ser silencioso.
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("sin clave de baja"),
        expect.objectContaining({ mailId, kind: "limit-reached" }),
      );
    });

    it("uid que no entra en el token: sale SIN bloque y SIN pie, no `failed`", async () => {
      // 151 caracteres no caben en la gramática del token (tope 150 bytes). No
      // pasa con los uids de Auth (el Admin SDK ni deja crear uno de más de 128),
      // así que la dirección se simula; el mail operativo no puede perderse por eso.
      const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
      jest
        .spyOn(Auth.prototype, "getUser")
        .mockResolvedValue({ email: "uid-largo@example.com" } as never);
      await seed({ ...conBloque, toUid: "u".repeat(151) });
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].to).toBe("uid-largo@example.com");
      expect(sender.sent[0].text).toContain("3 alumnos quedaron en solo lectura");
      expect(sender.sent[0].text).not.toContain(BLOQUE);
      expect(sender.sent[0].html).not.toContain("VER LOS PLANES");
      expect(sender.sent[0].text).not.toMatch(URL_DE_BAJA);
      expect((await readQueueDoc(mailId))?.status).toBe("sent");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("link de baja no representable"),
        expect.objectContaining({ mailId }),
      );
    });

    it("NO persiste el link tampoco acá", async () => {
      await seed(conBloque);

      await enviar(makeOkSender(), BAJA_KEY);

      const crudo = JSON.stringify(await readQueueDoc(mailId));
      for (const huella of ["correos-promocionales", "#t=", "v1."]) {
        expect(crudo).not.toContain(huella);
      }
    });

    it("un `bloqueComercial` fuera de la allowlist no puede llevar link: sale sin bloque", async () => {
      // El tipo lo impide al encolar; esto cubre un documento que llegó por otro
      // camino. Un link para esa preferencia contestaría `invalido`: un link muerto.
      await seed({ ...conBloque, bloqueComercial: "nueva_solicitud" as never });
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].text).not.toContain(BLOQUE);
      expect(sender.sent[0].text).not.toMatch(URL_DE_BAJA);
    });

    it("destinatario `toAddress` literal: sin cuenta no hay baja posible, sale sin bloque", async () => {
      await seed({ ...conBloque, toUid: "no-existe", toAddress: "equipo@example.com" });
      const sender = makeOkSender();

      await enviar(sender, BAJA_KEY);

      expect(sender.sent).toHaveLength(1);
      expect(sender.sent[0].to).toBe("equipo@example.com");
      expect(sender.sent[0].text).not.toContain(BLOQUE);
      expect(sender.sent[0].text).not.toMatch(URL_DE_BAJA);
    });
  });

  describe("el trigger", () => {
    it("declara el secreto de la baja: sin él `value()` sale vacío y todo mail comercial falla", () => {
      const keys = (sendQueuedMail.__endpoint.secretEnvironmentVariables ?? []).map(
        (s) => s.key,
      );

      expect(keys).toEqual(expect.arrayContaining(["RESEND_API_KEY", "BAJA_PROMOCIONALES_KEY"]));
    });
  });
});

// ---------------------------------------------------------------------------
// `bloqueComercial` en la cola
// ---------------------------------------------------------------------------
describe("enqueueMail: bloqueComercial", () => {
  const toUid = "pf-bloque-comercial-1";
  const scope = "bloque-comercial-1";
  const id = dedupeKey("limit-reached", scope, toUid);

  afterEach(() => purge(id));

  it("lo persiste cuando el productor lo marca", async () => {
    await enqueueMail(testApp, {
      toUid,
      kind: "limit-reached",
      scope,
      params: { limit: 2 },
      bloqueComercial: ATHLETE_PROSPECT_PREF_KEY,
    });

    const doc = await readQueueDoc(id);
    expect(doc?.bloqueComercial).toBe("novedades_plan");
    // Y NO es un `prefKey`: ése frena el mail entero.
    expect(doc?.prefKey).toBeUndefined();
  });

  it("no escribe el campo cuando no se marca", async () => {
    await enqueueMail(testApp, {
      toUid,
      kind: "limit-reached",
      scope,
      params: { limit: 2 },
    });

    expect(Object.keys((await readQueueDoc(id)) ?? {})).not.toContain("bloqueComercial");
  });

  it("el literal del documento y la constante de los productores no se separan", () => {
    // Compila sólo si son el MISMO literal. Si alguien cambia uno y no el otro,
    // el error es de TypeScript, antes de que exista un link que conteste
    // `invalido` en un mail real.
    const marca: NonNullable<MailQueueDoc["bloqueComercial"]> = ATHLETE_PROSPECT_PREF_KEY;

    expect(marca).toBe("novedades_plan");
  });
});
