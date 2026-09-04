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
 *   firebase functions:secrets:set RESEND_API_KEY --project prod
 * Deploying without it fails fast rather than sending nothing silently.
 *
 * ⚠️ Ese comando escribe en PRODUCCIÓN (#826). `prod` y `treino-dev` son el
 * mismo y único proyecto Firebase de TREINO: adentro están los usuarios reales.
 * Sin `--project`, `.firebaserc` resuelve al mismo destino sin nombrarlo en
 * pantalla. Pisar esta key manda a 403 todo el mail transaccional de la app
 * publicada. Ver AGENTS.md § Entornos.
 */
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

/**
 * Verified sender. The domain MUST be DNS-verified in Resend; an unverified
 * domain makes every send return 403.
 */
const MAIL_FROM = defineString("MAIL_FROM", {
  // `equipo@` y no `soporte@` a proposito. El nombre del remitente es una
  // promesa sobre quien esta del otro lado, y hoy NADIE lee las respuestas:
  // `send.gettreino.com` no tiene buzon —su MX es el de rebotes de SES— y el
  // payload que se le manda a Resend todavia no lleva `reply_to`.
  //
  // `soporte@` es el peor nombre posible con esa deuda abierta: la persona que
  // no puede entrar a su cuenta le responde pidiendo ayuda y nadie la lee.
  // Cuanto mas explicita la promesa, mas caro incumplirla.
  default: "TREINO <equipo@send.gettreino.com>",
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
  // Se reasigna con la lectura fresca de abajo. Ver el bloque que explica por
  // qué el snapshot del evento no alcanza.
  // eslint-disable-next-line no-param-reassign
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

  // ── El snapshot del evento es de la CREACIÓN, y puede estar viejo ────────
  //
  // `sendQueuedMail` es `onDocumentCreated`: `event.data` congela el documento
  // tal como nació y NO refleja ninguna escritura posterior. Renderizar desde
  // ahí tiene dos consecuencias, y las dos son bugs:
  //
  // 1. `enqueueMail({ refreshPendingParams: true })` actualiza los params del
  //    mail encolado cuando llega un segundo pedido — es lo que impide mandar
  //    un link de reseteo que el segundo pedido ya invalidó. Sin releer, esa
  //    actualización no llega al mail: se escribe en Firestore y el envío
  //    sigue usando el link muerto. El arreglo del throttle sería cosmético.
  //
  // 2. El guard de re-entrada de abajo lee `status` del MISMO snapshot. Con
  //    `retry: true`, una reentrega trae otra vez el snapshot de creación, o
  //    sea `pending` — así que "already sent, skipping" no se disparaba nunca
  //    y la idempotencia dependía sólo de la clave que se le pasa a Resend.
  //
  // Releer cuesta una lectura por mail y cierra las dos.
  const fresh = await ref.get();
  if (!fresh.exists) {
    logger.warn("sendQueuedMail: el documento ya no existe, skipping", {
      mailId,
    });
    return;
  }
  data = (fresh.data() as MailQueueDoc) ?? data;

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
    // Los mails de auth llevan en `params.actionLink` un link de un solo uso
    // con su `oobCode`. Una vez enviado, ese secreto no tiene por qué seguir
    // viviendo en Firestore: la fila de la cola se conserva como registro de
    // envío, no como copia del token. Sobre un documento sin ese campo el
    // delete es un no-op, así que no hace falta ramificar por kind.
    "params.actionLink": FieldValue.delete(),
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
