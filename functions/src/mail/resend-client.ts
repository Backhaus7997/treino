/**
 * Minimal Resend HTTP client for TREINO.
 *
 * Design:
 *   - Plain `fetch` against the Resend REST API instead of the `resend` npm
 *     package. `functions/package.json` deliberately carries only
 *     firebase-admin + firebase-functions, and this is a single POST; adding a
 *     dependency (and its version churn) for one endpoint is not worth it.
 *     Node 20 — the configured runtime — ships global fetch.
 *   - `MailSender` is an interface so `send-queued-mail` can take a mock,
 *     mirroring the optional `messaging` injection in sendFcm (ADR-PN-004).
 *     No test ever needs a network call or a real API key.
 *   - Sends an `Idempotency-Key` header. The outbox already dedupes at the
 *     Firestore layer; this is the second line of defence for the narrow
 *     window where a send succeeds but the status write does not, and the
 *     consumer retries. Duplicate email is what burns sender reputation, so
 *     it is worth guarding twice.
 */

import { logger } from "firebase-functions";

const RESEND_ENDPOINT = "https://api.resend.com/emails";

/** A single outbound message, already rendered. */
export interface OutboundMail {
  to: string;
  subject: string;
  html: string;
  text: string;
  /** Forwarded as Resend's Idempotency-Key. Use the queue doc id. */
  idempotencyKey: string;
}

/** Injectable send port. Implemented by `createResendSender`, mocked in tests. */
export interface MailSender {
  send(mail: OutboundMail): Promise<void>;
}

/** Thrown on a non-2xx Resend response so the consumer can record `lastError`. */
export class MailSendError extends Error {
  constructor(
    message: string,
    /** HTTP status, or 0 when the request never completed. */
    readonly status: number,
  ) {
    super(message);
    this.name = "MailSendError";
  }

  /**
   * 429 and 5xx are worth another attempt; 4xx (bad address, rejected
   * payload) will fail identically forever and should go straight to `failed`.
   */
  get isRetriable(): boolean {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }
}

/**
 * Builds a MailSender bound to an API key and a verified sender address.
 *
 * @param apiKey - Resend API key. Injected from the RESEND_API_KEY secret.
 * @param from   - Verified sender, e.g. "TREINO <hola@treino.app>". The domain
 *                 MUST be DNS-verified in Resend or every send returns 403.
 */
export function createResendSender(apiKey: string, from: string): MailSender {
  return {
    async send(mail: OutboundMail): Promise<void> {
      let response: Response;

      try {
        response = await fetch(RESEND_ENDPOINT, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": mail.idempotencyKey,
          },
          body: JSON.stringify({
            from,
            to: [mail.to],
            subject: mail.subject,
            html: mail.html,
            text: mail.text,
          }),
        });
      } catch (error) {
        // Network-level failure: never reached Resend, always worth a retry.
        const message = error instanceof Error ? error.message : String(error);
        throw new MailSendError(`resend: request failed — ${message}`, 0);
      }

      if (!response.ok) {
        const body = await response.text().catch(() => "<unreadable body>");
        throw new MailSendError(
          `resend: HTTP ${response.status} — ${body}`,
          response.status,
        );
      }

      logger.info("resend: sent", { idempotencyKey: mail.idempotencyKey });
    },
  };
}
