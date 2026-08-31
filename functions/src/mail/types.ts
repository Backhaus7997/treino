/**
 * Shared types for the TREINO transactional email outbox.
 *
 * Design:
 *   - The outbox stores WHAT happened (kind + params), never rendered HTML.
 *     Templates are applied at send time by `send-queued-mail`, so a copy fix
 *     never requires re-enqueueing and a queue doc stays far below the 1MB
 *     Firestore limit (a branded HTML email is easily 50-100KB).
 *   - The recipient is stored as a uid, not an address. The address is
 *     resolved from Firebase Auth at SEND time so a user who changes their
 *     email between enqueue and send still receives the mail.
 *
 * See `enqueue-mail.ts` for the idempotency contract.
 */

/** Stable discriminator: selects the template and drives the dedupe key. */
export type MailKind =
  // Auth. Reemplazan las plantillas default de Firebase Auth: el link sigue
  // siendo el que genera el Admin SDK (apunta al action handler que Firebase
  // hostea), lo unico que cambia es quien manda el mail y como se ve.
  | "password-reset"
  // Se manda EN LUGAR de `password-reset` cuando la cuenta no tiene proveedor
  // de contraseña. No lleva `actionLink`: no hay contraseña que restablecer.
  | "federated-signin-hint"
  | "email-verification"
  | "appointment-confirmed"
  | "appointment-series-created"
  | "appointment-cancelled"
  | "appointment-series-cancelled"
  | "link-requested"
  | "link-accepted"
  | "payment-overdue";

/**
 * Per-kind template parameters.
 *
 * Kept as a flat string/number map (not a discriminated union) because the
 * values round-trip through Firestore, which has no notion of TS unions. The
 * template layer validates what it needs and degrades gracefully on a missing
 * key rather than throwing mid-send.
 */
export type MailParams = Record<string, string | number>;

/** Lifecycle of a queued mail. Terminal states are `sent` and `failed`. */
export type MailStatus = "pending" | "sent" | "failed";

/** Shape of a `mail_queue/{dedupeKey}` document. */
export interface MailQueueDoc {
  /** Recipient uid. The address is resolved from Auth at send time. */
  toUid: string;
  /** Selects the template. */
  kind: MailKind;
  /** Template parameters. */
  params: MailParams;
  /**
   * Optional `notificationPrefs` key. When present, the consumer skips the
   * send if the user turned the email channel off for that key. Transactional
   * mail (payment overdue, session confirmed) leaves this undefined — it is
   * service-critical and not subject to opt-out.
   */
  prefKey?: string;
  status: MailStatus;
  /** Incremented on every send attempt, successful or not. */
  attempts: number;
  createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
  sentAt?: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
  /** Last failure message, kept for triage. Cleared on success. */
  lastError?: string;
}

/** Collection name — single source of truth, referenced by rules and tests. */
export const MAIL_QUEUE_COLLECTION = "mail_queue";
