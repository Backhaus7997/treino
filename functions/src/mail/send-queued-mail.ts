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
 *   - Los correos promocionales llevan en el pie un link de baja, calculado
 *     ACÁ al enviar (nunca persistido) y con falla cerrada si falta la clave.
 *     Ver `decidirBaja` y `baja-de-promocionales.ts`.
 *
 * TODO(mail-sweeper): a `pending` document whose retries are exhausted is only
 * visible in logs. Add a scheduled sweep that reports stuck documents once
 * volume justifies it.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "./types";
import { renderMail } from "./templates";
import { MailSendError, MailSender, createResendSender } from "./resend-client";
import {
  BAJA_PROMOCIONALES_KEY,
  prefTieneBaja,
  urlDeBaja,
} from "./baja-de-promocionales";

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
  // `treino@gettreino.com` es un BUZON REAL (Google Workspace): quien responde
  // un mail de la app le escribe a alguien que lo lee. Antes salia de
  // `equipo@send.gettreino.com`, un subdominio sin buzon —su MX es el de
  // rebotes de SES— y cada respuesta se perdia.
  //
  // Requiere `gettreino.com` verificado en Resend (DKIM en
  // `resend._domainkey.gettreino.com`); sin eso todo envio devuelve 403.
  //
  // Ojo: `functions/.env.treino-dev` define su propio MAIL_FROM y GANA sobre
  // este default. Cambiar solo uno no cambia lo que sale en produccion.
  default: "TREINO <treino@gettreino.com>",
});

/** Past this many attempts a document is declared permanently failed. */
const MAX_ATTEMPTS = 5;

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Resolves the recipient address.
 *
 * @returns the address, or `null` when the user is gone or has none — both
 *          permanent conditions, never worth a retry.
 */
async function resolveAddress(
  app: App,
  uid: string,
): Promise<string | null> {
  try {
    const user = await getAuth(app).getUser(uid);
    return user.email ?? null;
  } catch (error: unknown) {
    logger.warn("sendQueuedMail: cannot resolve address", { uid, error });
    return null;
  }
}

/**
 * Checks the email channel in `users/{uid}.notificationPrefs`.
 *
 * Only consulted when the queue document carries a `prefKey` (gates the whole
 * mail) or a `bloqueComercial` (gates only the commercial block; see
 * `decidirBaja`). Transactional mail omits both and is never gated here.
 *
 * @returns true when the mail may be sent.
 */
async function emailChannelAllowed(
  app: App,
  uid: string,
  prefKey: string,
): Promise<boolean> {
  const snap = await getFirestore(app).collection("users").doc(uid).get();
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
 * Lo que decide cómo se frena un mail, ya resuelto: `prefKey` y `bloqueComercial`
 * son excluyentes (ver `MailOptOut`), así que a lo sumo uno viene lleno.
 */
interface OposicionDelMail {
  toUid: string;
  prefKey?: string;
  bloqueComercial?: string;
}

/** Qué le falta o le sobra a un mail por la baja de los correos promocionales. */
interface DecisionDeBaja {
  /**
   * La preferencia con la que se firma el link de baja del pie, o `undefined`
   * si este mail no lleva pie.
   */
  prefKeyDelLink?: string;
  /**
   * El mail necesita el mecanismo de baja y NO hay forma de dárselo: es el motivo
   * por el que falla cerrado. Hoy, un mail entero comercial (`prefKey`) a una
   * dirección literal, que no tiene cuenta a la que apuntar la baja.
   */
  sinBajaPosible?: string;
  /**
   * `true`: el link existe sólo por un bloque comercial dentro de un mail
   * operativo (`bloqueComercial`), no porque el mail entero sea comercial
   * (`prefKey`). Decide qué pasa si el link no se puede armar: ver el handler.
   */
  soloElBloque?: boolean;
  /** `false`: la plantilla omite su bloque de venta. */
  comercial: boolean;
}

/**
 * Decide, AL ENVIAR, si el mail lleva el pie de baja y si lleva su bloque
 * comercial. Se evalúa acá y no al encolar: si la persona se opone entre que se
 * encoló y que salió, gana la oposición.
 *
 * - **`prefKey` de la allowlist** (el mail ES comercial; el gate de arriba ya
 *   dejó pasar a quien no se opuso): pie de baja.
 * - **`bloqueComercial`** (un mail operativo con un bloque comercial adentro):
 *   preferencia apagada → sin bloque y SIN pie, porque ya no hay nada comercial;
 *   prendida o ausente → el mail completo CON pie, porque tiene contenido de
 *   publicidad y la norma pide el mecanismo en toda comunicación así. (Si el
 *   link no se puede armar, el handler lo degrada a «sin bloque y sin pie».)
 * - **Cualquier otro**: no es comercial, no se toca.
 *
 * Un destinatario `toAddress` literal no tiene cuenta, ni preferencias, ni a
 * dónde apuntar una baja: nunca lleva pie. Sin mecanismo de baja no se manda
 * publicidad, y qué pasa depende de qué es el mail:
 * - con `bloqueComercial` sale sin el bloque;
 * - con un `prefKey` de la allowlist es ENTERAMENTE comercial y no tiene
 *   versión sin publicidad: falla cerrado, igual que sin clave.
 * Hoy ningún productor manda ninguno de los dos a una dirección literal; es la
 * salida segura si alguno lo hiciera.
 *
 * Un `bloqueComercial` fuera de la allowlist tampoco puede llevar link (la
 * callable lo rechazaría: sería un link muerto), así que se trata igual: sin
 * bloque. El tipo ya lo impide al encolar; esto cubre el documento que llegó por
 * otro camino.
 */
async function decidirBaja(
  app: App,
  { toUid, prefKey, bloqueComercial }: OposicionDelMail,
  literal: boolean,
): Promise<DecisionDeBaja> {
  if (literal) {
    if (prefTieneBaja(prefKey)) {
      return { sinBajaPosible: "sin cuenta para la baja", comercial: true };
    }
    return { comercial: !bloqueComercial };
  }

  if (prefTieneBaja(prefKey)) {
    return { prefKeyDelLink: prefKey, comercial: true };
  }

  if (bloqueComercial) {
    const prendida =
      prefTieneBaja(bloqueComercial) &&
      (await emailChannelAllowed(app, toUid, bloqueComercial));
    return prendida ?
      { prefKeyDelLink: bloqueComercial, soloElBloque: true, comercial: true } :
      { comercial: false };
  }

  return { comercial: true };
}

/**
 * Pure handler extracted for jest testability, mirroring the notify-* CFs.
 *
 * @param app     - Admin SDK app.
 * @param mailId  - Queue document ID; doubles as the Resend idempotency key.
 * @param data    - Queue document contents.
 * @param sender  - Injected sender. Tests pass a mock; production builds one
 *                  from the RESEND_API_KEY secret.
 * @param bajaKey - Clave del HMAC del link de baja (BAJA_PROMOCIONALES_KEY).
 *                  Se inyecta como el `sender`. El default es VACÍO a propósito:
 *                  quien se olvide de pasarla no manda un correo promocional sin
 *                  el mecanismo de baja: falla cerrado, o sale sin su bloque
 *                  comercial si el mail sólo lo llevaba adentro.
 */
export async function sendQueuedMailHandler(
  app: App,
  mailId: string,
  // Se reasigna con la lectura fresca de abajo. Ver el bloque que explica por
  // qué el snapshot del evento no alcanza.
  // eslint-disable-next-line no-param-reassign
  data: MailQueueDoc | undefined,
  sender: MailSender,
  bajaKey = "",
): Promise<void> {
  if (!data) {
    logger.warn("sendQueuedMail: empty document, skipping", { mailId });
    return;
  }

  const ref = getFirestore(app)
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

  // Un `toAddress` es una direccion literal: no hay uid que resolver ni
  // `notificationPrefs` que consultar. Se saltea las dos cosas a proposito —
  // un buzon de equipo no tiene preferencias, y pedirle las suyas a un uid que
  // no existe haria fallar un mail que sí tiene destino.
  const literal = typeof data.toAddress === "string" && data.toAddress !== "";

  // `prefKey` y `bloqueComercial` son excluyentes en el tipo, pero este es un
  // documento de Firestore: puede traer los dos. Entonces GANA `bloqueComercial`.
  // El gate de `prefKey` frena el mail ENTERO, y se comería justo el aviso
  // operativo que `bloqueComercial` existe para dejar pasar. Se lee con un tipo
  // plano: el del documento ya no admite el caso, y TypeScript lo daría por
  // imposible.
  const crudo = data as { prefKey?: string; bloqueComercial?: string };
  if (crudo.prefKey && crudo.bloqueComercial) {
    logger.warn("sendQueuedMail: prefKey y bloqueComercial juntos; gana bloqueComercial", {
      mailId,
      kind: data.kind,
      prefKey: crudo.prefKey,
    });
  }
  const oposicion: OposicionDelMail = {
    toUid: data.toUid,
    prefKey: crudo.bloqueComercial ? undefined : crudo.prefKey,
    bloqueComercial: crudo.bloqueComercial,
  };

  // Opt-out check, when this mail is subject to one.
  if (oposicion.prefKey && !literal) {
    const allowed = await emailChannelAllowed(app, data.toUid, oposicion.prefKey);
    if (!allowed) {
      logger.info("sendQueuedMail: email channel off, skipping", {
        mailId,
        prefKey: oposicion.prefKey,
      });
      await ref.update({ status: "failed", lastError: "email channel off" });
      return;
    }
  }

  const to = literal ? data.toAddress! : await resolveAddress(app, data.toUid);
  if (!to) {
    await ref.update({
      status: "failed",
      attempts,
      lastError: "no email address for uid",
    });
    return;
  }

  // ── El pie de baja de los correos promocionales ──────────────────────────
  //
  // El link se calcula ACÁ, al enviar, y NO se persiste en `mail_queue`: es un
  // HMAC, se recalcula igual en cada reintento, y guardarlo dejaría en la cola
  // una credencial por cada mail comercial.
  const baja = await decidirBaja(app, oposicion, literal);

  let bajaDePromocionales: string | undefined;
  let comercial = baja.comercial;
  if (baja.prefKeyDelLink || baja.sinBajaPosible) {
    // Sin clave, con un uid que no entra en la gramática del token (no pasa con
    // los de Auth, que miden hasta 128), o con un destinatario sin cuenta a
    // quien apuntarle la baja, NO hay link que poner. Qué se hace entonces
    // depende de qué es el mail, y en todos los casos suena la alarma:
    //
    // - **Mail entero comercial (`prefKey`)**: FALLA CERRADO. Un correo
    //   promocional sin el mecanismo de baja es exactamente lo que el Decreto
    //   1558/01 prohíbe, y mandarlo "igual, sin el link" es la salida que nadie
    //   va a notar. El mail perdido no se reencola (`sendQueuedMail` sólo
    //   escucha creaciones); es comercial, y su productor lo vuelve a mandar en
    //   el próximo disparo, pasado el enfriamiento.
    // - **Mail operativo con bloque de venta (`bloqueComercial`)**: DEGRADA. Sale
    //   SIN el bloque y SIN pie, como si la preferencia estuviera apagada. El
    //   aviso operativo («N alumnos quedaron en solo lectura») le tiene que
    //   llegar igual, y no sale contenido comercial sin mecanismo de baja.
    //
    // Con `defineSecret` el deploy ya falla si el secreto no existe: esto es un
    // cinturón, no el freno principal. Y NUNCA se deja salir la excepción: la
    // plataforma reintentaría una semana un mail que falla idéntico cada vez.
    let motivo: string | undefined = baja.sinBajaPosible;
    let causa: string | undefined;
    if (!motivo && baja.prefKeyDelLink) {
      if (!bajaKey) {
        motivo = "sin clave de baja";
      } else {
        try {
          bajaDePromocionales = urlDeBaja(data.toUid, baja.prefKeyDelLink, bajaKey);
        } catch (error: unknown) {
          motivo = "link de baja no representable";
          causa = String(error);
        }
      }
    }

    if (motivo) {
      if (baja.soloElBloque) {
        logger.error(`sendQueuedMail: ${motivo}, el mail sale sin su bloque comercial`, {
          mailId,
          kind: data.kind,
          ...(causa ? { error: causa } : {}),
        });
        comercial = false;
      } else {
        logger.error(`sendQueuedMail: ${motivo}, el mail comercial no sale`, {
          mailId,
          kind: data.kind,
          ...(causa ? { error: causa } : {}),
        });
        await ref.update({ status: "failed", attempts, lastError: motivo });
        return;
      }
    }
  }

  const rendered = renderMail(data.kind, data.params ?? {}, {
    bajaDePromocionales,
    comercial,
  });

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
    secrets: [RESEND_API_KEY, BAJA_PROMOCIONALES_KEY],
    retry: true,
  },
  async (event) => {
    const data = event.data?.data() as MailQueueDoc | undefined;
    const sender = createResendSender(RESEND_API_KEY.value(), MAIL_FROM.value());
    await sendQueuedMailHandler(
      ensureApp(),
      event.params.mailId,
      data,
      sender,
      BAJA_PROMOCIONALES_KEY.value(),
    );
  },
);
