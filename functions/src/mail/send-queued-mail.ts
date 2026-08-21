/**
 * sendQueuedMail — outbox consumer for TREINO transactional email.
 *
 * Fires on creates in `mail_queue/{mailId}` and performs the actual Resend
 * call. Nothing else in the codebase talks to Resend; producers only ever call
 * `enqueueMail`.
 *
 * Design:
 *   - The recipient address is resolved from Firebase Auth HERE, not at
 *     enqueue time, so a user who changed their email between the two still
 *     gets the mail at the current address.
 *   - Retriable failures (429, 5xx, network) re-throw so the platform redelivers
 *     the event; `retry: true` is what makes that redelivery happen. Permanent
 *     failures (4xx, unknown user, no address) are recorded as `failed` and
 *     never retried — the outcome would be identical every time.
 *   - `attempts` is capped. Firebase retries an event for up to 7 days; without
 *     a cap one malformed document would hammer Resend for a week.
 *   - Re-entry is safe: a document already `sent` short-circuits. That covers
 *     the window where the Resend call succeeded but the status write did not.
 *
 * TODO(mail-sweeper): a `pending` document whose retries are exhausted is only
 * visible in logs. Add a scheduled sweep that reports stuck documents once
 * volume justifies it.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";

import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "./types";
import { renderMail } from "./templates";
import { MailSendError, MailSender, createResendSender } from "./resend-client";

/**
 * Resend API key. Create it with:
 *   firebase functions:secrets:set RESEND_API_KEY
 * Deploying without it fails fast rather than sending nothing silently.
 */
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

/**
 * Verified sender. The domain MUST be DNS-verified in Resend; an unverified
 * domain makes every send return 403.
 */
const MAIL_FROM = defineString("MAIL_FROM", {
  default: "TREINO <hola@treino.app>",
});

/** Past this many attempts a document is declared permanently failed. */
const MAX_ATTEMPTS = 5;

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Resolves the recipient address.
 *
 * @returns the address, or `null` when the user is gone or has none — both
 *          permanent conditions, never worth a retry.
 */
async function resolveAddress(
  app: admin.app.App,
  uid: string,
): Promise<string | null> {
  try {
    const user = await admin.auth(app).getUser(uid);
    return user.email ?? null;
  } catch (error: unknown) {
    logger.warn("sendQueuedMail: cannot resolve address", { uid, error });
    return null;
  }
}

/**
 * Checks the email channel in `users/{uid}.notificationPrefs`.
 *
 * Only consulted when the queue document carries a `prefKey`. Transactional
 * mail omits it and is never gated here.
 *
 * @returns true when the mail may be sent.
 */
async function emailChannelAllowed(
  app: admin.app.App,
  uid: string,
  prefKey: string,
): Promise<boolean> {
  const snap = await admin.firestore(app).collection("users").doc(uid).get();
  const prefs = snap.data()?.notificationPrefs as
    | Record<string, Record<string, boolean> | undefined>
    | undefined;

  const value = prefs?.[prefKey]?.email;
  // Absent preference means the user never touched the toggle. Defaults live
  // in the Flutter layer (NotifPrefs._defaultFor); the server errs towards
  // sending, since every producer that passes a prefKey opted into it.
  return value !== false;
}

/**
 * Pure handler extracted for jest testability, mirroring the notify-* CFs.
 *
 * @param app    - Admin SDK app.
 * @param mailId - Queue document ID; doubles as the Resend idempotency key.
 * @param data   - Queue document contents.
 * @param sender - Injected sender. Tests pass a mock; production builds one
 *                 from the RESEND_API_KEY secret.
 */
export async function sendQueuedMailHandler(
  app: admin.app.App,
  mailId: string,
  data: MailQueueDoc | undefined,
  sender: MailSender,
): Promise<void> {
  if (!data) {
    logger.warn("sendQueuedMail: empty document, skipping", { mailId });
    return;
  }

  const ref = admin
    .firestore(app)
    .collection(MAIL_QUEUE_COLLECTION)
    .doc(mailId);

  // Re-entry guard: a redelivered event whose send already landed.
  if (data.status === "sent") {
    logger.info("sendQueuedMail: already sent, skipping", { mailId });
    return;
  }

  const attempts = (data.attempts ?? 0) + 1;

  if (attempts > MAX_ATTEMPTS) {
    logger.error("sendQueuedMail: attempts exhausted", { mailId, attempts });
    await ref.update({
      status: "failed",
      lastError: `attempts exhausted (${MAX_ATTEMPTS})`,
    });
    return;
  }

  // Opt-out check, when this mail is subject to one.
  if (data.prefKey) {
    const allowed = await emailChannelAllowed(app, data.toUid, data.prefKey);
    if (!allowed) {
      logger.info("sendQueuedMail: email channel off, skipping", {
        mailId,
        prefKey: data.prefKey,
      });
      await ref.update({ status: "failed", lastError: "email channel off" });
      return;
    }
  }

  const to = await resolveAddress(app, data.toUid);
  if (!to) {
    await ref.update({
      status: "failed",
      attempts,
      lastError: "no email address for uid",
    });
    return;
  }

  const rendered = renderMail(data.kind, data.params ?? {});

  try {
    await sender.send({
      to,
      subject: rendered.subject,
      html: rendered.html,
      text: rendered.text,
      idempotencyKey: mailId,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    const retriable = error instanceof MailSendError && error.isRetriable;

    await ref.update({
      status: retriable ? "pending" : "failed",
      attempts,
      lastError: message,
    });

    if (retriable) {
      // Re-throw so the platform redelivers the event (retry: true).
      logger.warn("sendQueuedMail: retriable failure", { mailId, message });
      throw error;
    }

    logger.error("sendQueuedMail: permanent failure", { mailId, message });
    return;
  }

  await ref.update({
    status: "sent",
    attempts,
    sentAt: FieldValue.serverTimestamp(),
    lastError: FieldValue.delete(),
  });

  logger.info("sendQueuedMail: sent", { mailId, kind: data.kind });
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1, matching every other TREINO CF.
 */
export const sendQueuedMail = onDocumentCreated(
  {
    document: `${MAIL_QUEUE_COLLECTION}/{mailId}`,
    region: "southamerica-east1",
    secrets: [RESEND_API_KEY],
    retry: true,
  },
  async (event) => {
    const data = event.data?.data() as MailQueueDoc | undefined;
    const sender = createResendSender(RESEND_API_KEY.value(), MAIL_FROM.value());
    await sendQueuedMailHandler(getApp(), event.params.mailId, data, sender);
  },
);
