/**
 * enqueueMail — outbox writer for TREINO transactional email.
 *
 * WHY AN OUTBOX AND NOT A DIRECT SEND
 *
 * Cloud Functions events are delivered AT-LEAST-ONCE: a trigger can fire more
 * than once for the same write. `sendFcm` has no idempotency guard, which is
 * tolerable for push (a duplicate notification is noise the user forgets) but
 * not for email — a duplicate mail earns spam complaints, and sender
 * reputation is the one thing that cannot be bought back quickly.
 *
 * So the trigger does not call Resend. It writes a queue document whose ID is
 * DETERMINISTIC, derived from the source event. A re-fired trigger targets the
 * same ID, `create()` rejects it, and nothing is sent twice.
 *
 * THE SAME PROPERTY COLLAPSES BATCHES
 *
 * `AppointmentRepository.createRecurringByTrainer` writes a whole series in one
 * WriteBatch — a Mon/Wed/Fri booking over three months is ~36 documents, each
 * firing `notifyOnAppointment`. Keyed per appointment that is 36 emails to one
 * athlete. Keyed on `recurringId` all 36 triggers resolve to ONE queue doc, and
 * the athlete gets a single "your PT booked you 36 sessions" mail.
 * `cancelFutureSeries` (batched, up to 500 ops) collapses the same way.
 *
 * No counters, no time windows, no anti-spam bookkeeping: the guard that
 * protects against duplicate triggers is the guard that groups the series.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";
import { MAIL_QUEUE_COLLECTION, MailKind, MailParams } from "./types";

/** Firestore gRPC status code for a `create()` on an existing document. */
const ALREADY_EXISTS = 6;

/** Characters Firestore accepts in a document ID, conservatively. */
const UNSAFE_ID_CHARS = /[^A-Za-z0-9_-]/g;

/** Strips path separators and other unsafe characters out of an ID fragment. */
function safe(fragment: string): string {
  return fragment.replace(UNSAFE_ID_CHARS, "-");
}

/**
 * Builds the deterministic queue document ID.
 *
 * `scope` is whatever the mail should be deduped BY — an appointment id for a
 * one-off booking, a `recurringId` for a whole series, a payment id plus the
 * notification date for the weekly overdue reminder.
 *
 * The recipient is part of the key. A cancellation can notify BOTH parties;
 * without the uid the two mails would collide on one document and only one
 * person would ever hear about it. Including it costs nothing and does not
 * weaken series collapsing, since every occurrence of a series shares one
 * recipient anyway.
 */
export function dedupeKey(kind: MailKind, scope: string, toUid: string): string {
  return `${safe(scope)}__${kind}__${safe(toUid)}`;
}

/** Everything `enqueueMail` needs to persist one pending mail. */
export interface EnqueueMailInput {
  /** Recipient uid. The address is resolved from Auth at send time. */
  toUid: string;
  kind: MailKind;
  /** What this mail is deduped by. See `dedupeKey`. */
  scope: string;
  params: MailParams;
  /**
   * Optional `users/{uid}.notificationPrefs` key. Omit for transactional mail
   * that is not subject to opt-out.
   */
  prefKey?: string;
  /**
   * Cuando el dedupe rechaza este mail, ACTUALIZA los params del que ya está
   * encolado en vez de descartarlo — siempre que siga en `pending`.
   *
   * Opt-in, y tiene que seguir siéndolo. Para el 99% de los mails descartar es
   * lo correcto: una serie de 36 turnos colapsa a UN mail justamente porque
   * las 36 ocurrencias se descartan, y refrescar ahí sería reescribir el mismo
   * contenido 36 veces sin ganar nada.
   *
   * Existe por los mails que llevan un CÓDIGO DE UN SOLO USO. `generate…Link`
   * del Admin SDK invalida el código anterior del mismo usuario, así que un
   * segundo pedido dentro de la ventana de throttle MATA el link que ya está
   * encolado. Sin esto, el mail sale con un código muerto y el usuario ve
   * "expired or the link has already been used" sobre un mail recién llegado.
   *
   * Medido en producción el 2026-09-04, dos pedidos a un segundo:
   *
   *   14:44:06.088  enqueueMail: queued                    ← link A encolado
   *   14:44:06.532  enqueueMail: already queued, skipping  ← link B lo mató
   */
  refreshPendingParams?: boolean;
}

/**
 * Pisa los `params` del mail encolado, SÓLO si sigue en `pending`.
 *
 * Va en transacción y no en un `update` pelado: entre leer el estado y
 * escribir, el worker del outbox puede marcarlo `sent`. Sin la transacción se
 * reescribiría un mail ya enviado, que es la puerta que `create()` cierra a
 * propósito (ver el docstring de [enqueueMail]).
 *
 * No cambia `status`, ni `attempts`, ni `createdAt`. El mail sigue siendo el
 * mismo — lo único que cambia es que lleva el código vivo en vez del muerto.
 *
 * Nunca tira: un refresh fallido deja las cosas como estaban, que es
 * exactamente el comportamiento anterior a esta función.
 *
 * QUEDA UNA CARRERA, y es más angosta que la que cierra: si el worker YA leyó
 * el doc y está mandando el mail cuando esto corre, el usuario recibe el link
 * viejo igual. No se puede cerrar desde acá —haría falta que el worker tomara
 * el doc con un lock— y el resultado en ese caso no es peor que hoy.
 */
async function refreshIfPending(
  app: admin.app.App,
  id: string,
  params: MailParams,
  kind: MailKind,
  toUid: string,
): Promise<void> {
  const ref = admin.firestore(app).collection(MAIL_QUEUE_COLLECTION).doc(id);
  try {
    const refreshed = await admin.firestore(app).runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      if (snap.get("status") !== "pending") return false;
      tx.update(ref, { params });
      return true;
    });

    if (refreshed) {
      logger.info("enqueueMail: refreshed pending params", { id, kind, toUid });
    } else {
      // Ya se mandó (o se borró). El link nuevo no llega a ningún lado y el
      // usuario tiene en la casilla uno que ya no sirve — pero reescribir un
      // mail enviado lo mandaría dos veces, que es peor.
      logger.warn("enqueueMail: no se pudo refrescar, ya no estaba pending", {
        id,
        kind,
      });
    }
  } catch (error: unknown) {
    logger.warn("enqueueMail: refresh failed", { id, kind, error });
  }
}

/**
 * Writes one pending mail to the outbox, or does nothing if an identical mail
 * was already queued.
 *
 * Uses `create()` rather than `set()` deliberately. `set()` would overwrite a
 * document already marked `sent`, flipping it back to `pending` and causing the
 * consumer to send it a SECOND time — the exact failure this module exists to
 * prevent.
 *
 * Never throws: a queue write failing must not roll back the push notification
 * that shares the trigger, mirroring how sendFcm isolates history persistence
 * from FCM dispatch.
 *
 * @param app   - Admin SDK app (injected for testability).
 * @param input - Recipient, kind, dedupe scope, and template params.
 * @returns the queue doc ID when a document was created, `null` when the mail
 *          was already queued or the write failed.
 */
export async function enqueueMail(
  app: admin.app.App,
  input: EnqueueMailInput,
): Promise<string | null> {
  const { toUid, kind, scope, params, prefKey, refreshPendingParams } = input;
  const id = dedupeKey(kind, scope, toUid);

  const doc: Record<string, unknown> = {
    toUid,
    kind,
    params,
    status: "pending",
    attempts: 0,
    createdAt: FieldValue.serverTimestamp(),
  };
  if (prefKey) doc.prefKey = prefKey;

  try {
    await admin
      .firestore(app)
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(id)
      .create(doc);

    logger.info("enqueueMail: queued", { id, kind, toUid });
    return id;
  } catch (error: unknown) {
    const code = (error as { code?: number }).code;

    if (code === ALREADY_EXISTS) {
      // Expected on a re-fired trigger and on every occurrence of a batched
      // series after the first. Not a failure — this is the mechanism working.
      if (refreshPendingParams) {
        await refreshIfPending(app, id, params, kind, toUid);
      }
      logger.info("enqueueMail: already queued, skipping", { id, kind });
      return null;
    }

    logger.warn("enqueueMail: failed to queue", { id, kind, error });
    return null;
  }
}
