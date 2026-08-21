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

import * as admin from "firebase-admin";
import { enqueueMail, dedupeKey } from "../mail/enqueue-mail";
import { sendQueuedMailHandler } from "../mail/send-queued-mail";
import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "../mail/types";
import { MailSendError, MailSender, OutboundMail } from "../mail/resend-client";
import { notifyOnLinkChangeHandler } from "../notifications/notify-link-change";
import { notifyOnAppointmentHandler } from "../notifications/notify-appointment";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "mail-outbox-test");
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

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

  function noopMessaging(): admin.messaging.Messaging {
    return {
      sendEachForMulticast: jest.fn(async () => ({
        successCount: 0,
        failureCount: 0,
        responses: [],
      })),
    } as unknown as admin.messaging.Messaging;
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
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        ...overrides,
      });
  }

  beforeEach(async () => {
    await admin
      .auth(testApp)
      .createUser({ uid, email: "consumer1@example.com" })
      .catch(() => undefined);
  });

  afterEach(async () => {
    await purge(mailId);
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
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
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
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
