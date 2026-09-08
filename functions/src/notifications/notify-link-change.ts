/**
 * notifyOnLinkChange — Cloud Function for TREINO.
 *
 * Fires on writes to `trainer_links/{linkId}`.
 * Sends push notifications on trainer_link status changes.
 *
 * Design:
 *   - ADR-PN-007.
 *   - Guards: after missing → skip; after.reason === 'account-deleted' → skip;
 *     before?.status === after.status → skip (no-op write).
 *   - Branches:
 *       create + pending → notify trainer, deepLink "/coach"
 *       pending → active → notify athlete (aceptada), deepLink "/coach"
 *       active → paused → notify athlete (pausada), deepLink "/coach"
 *       paused → active → notify athlete (reanudada), deepLink "/coach"
 *       terminated + reason 'declined' → notify ATHLETE (el PF rechazó)
 *       terminated + reason 'cancelled-by-athlete' → notify TRAINER
 *       * → terminated (resto) → notify BOTH, deepLink "/coach"
 *   - All user-facing strings in es-AR.
 *   - Tail effect: a `terminated` link that was NEVER accepted is DELETED after
 *     the notification goes out (purge-rejected-link.ts). It lives here, and
 *     last, so the ordering against the push is a property of the code instead
 *     of a property of how Eventarc happens to schedule two triggers.
 *
 * REQ-PN-CF-004. Fase 6 Etapa 2.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Messaging } from "firebase-admin/messaging";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";
import { enqueueMail } from "../mail/enqueue-mail";
import { resolveAthleteName, resolveTrainerName } from "../mail/format";
import { trainerEntry } from "../mail/templates";
import {
  clasificarTerminacion,
  purgeRejectedLinkHandler,
  type CausaDeTerminacion,
} from "../purge-rejected-link";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Queues the email counterpart of a link push, when the branch has one.
 *
 * Only the two branches where somebody stands to LOSE something get a mail:
 *   - `pending` → the trainer. An unseen request is a lost athlete.
 *   - `pending` → `active` → the athlete. Their request was granted.
 *
 * `paused` → `active` is a resume, not an acceptance, and gets no mail. Neither
 * do `paused` and `terminated`: nothing is waiting on the recipient.
 *
 * Scope is the link id, so a pair that terminates and links again later still
 * receives a fresh mail rather than colliding with the first one.
 *
 * @param app          - Admin SDK app.
 * @param linkId       - trainer_links document ID; the dedupe scope.
 * @param after        - Snapshot data after the write.
 * @param afterStatus  - Resolved status branch.
 * @param beforeStatus - Previous status, to tell accept apart from resume.
 */
async function enqueueLinkMail(
  app: App,
  linkId: string,
  after: LinkData,
  afterStatus: string,
  beforeStatus: string | undefined,
): Promise<void> {
  const trainerId = after.trainerId as string;
  const athleteId = after.athleteId as string;

  if (afterStatus === "pending") {
    const athleteName = await resolveAthleteName(app, athleteId);
    await enqueueMail(app, {
      toUid: trainerId,
      kind: "link-requested",
      scope: linkId,
      // El destinatario es el PF, asi que el CTA va al Coach Hub. El default
      // (la landing) es para los mails que reciben ATLETAS.
      //
      // `to: "solicitudes"`: no hay una pantalla propia en mobile (las
      // pendientes viven en un bottom sheet, #393) asi que ahi cae en
      // `/coach` a secas, pero en el Hub web SI hay `/invitaciones`.
      params: { athleteName, ctaUrl: trainerEntry({ to: "solicitudes" }) },
      // The recipient is always the trainer, who HAS a settings screen for
      // this row (kNotifTypes `nueva_solicitud`). Honour their toggle.
      prefKey: "nueva_solicitud",
    });
    return;
  }

  // Acceptance only — a resume (paused → active) is not news worth a mail.
  if (afterStatus === "active" && beforeStatus !== "paused") {
    const trainerName = await resolveTrainerName(app, trainerId);
    await enqueueMail(app, {
      toUid: athleteId,
      kind: "link-accepted",
      scope: linkId,
      params: { trainerName },
    });
  }
}

/**
 * Estampa `linkId` en el chat que ya existía entre el PF y el alumno.
 *
 * POR QUE HACE FALTA. `senderMayPost` (firestore.rules) deja postear si el DOC
 * DEL CHAT tiene `linkId`. El cliente lo escribe SÓLO al crear el chat, vía
 * `ChatRepository._activeLinkIdBetween`. Un par que se escribió primero como
 * chat social y se vinculó DESPUES nunca lo recibe, y el alumno vinculado a su
 * PF queda leyendo "Para escribirle, esta persona tiene que seguirte". El
 * cliente tampoco lo puede completar después: `chats/update` tiene `linkId`
 * PINEADO INMUTABLE. Por eso vive acá, donde el Admin SDK saltea las reglas.
 *
 * CUANDO SE LLAMA, Y POR QUE NO ANTES. Sólo con el link en `active` o
 * `paused`. Esa no es una preferencia: es la invariante que `chatCreateOk`
 * exige de todo chat que lleve `linkId` (el link existe, su status está en
 * ['active','paused'], y los dos miembros son trainerId y athleteId), y que el
 * cliente espeja en `_activeLinkIdBetween`. Estamparlo en `pending` le daría
 * escritura al alumno ANTES de que el PF acepte — o sea, desarmaría el gate
 * que el vínculo representa.
 *
 * EL DOC ES UNO SOLO Y SU ID ES DETERMINISTICO: `sortedUids.join('_')`, igual
 * que `ChatRepository.chatIdFor`. La unicidad por par es estructural (la
 * documenta el bloque anti-spam de firestore.rules), así que no hay query que
 * hacer — es un doc directo.
 *
 * IDEMPOTENCIA. Va en transacción y NO pisa un `linkId` existente. El trigger
 * pasa por acá en `pending→active`, en `paused→active` y en `active→paused`,
 * así que sobre el mismo chat se ejecuta varias veces. Si el par se desvinculó
 * y volvió a vincularse, el chat conserva el linkId VIEJO a propósito: decidir
 * la política de re-vinculación excede este arreglo, y pisar es la operación
 * que no se puede deshacer.
 *
 * Si el chat no existe no se crea nada: cuando el par lo abra, el cliente lo
 * va a estampar solo.
 *
 * @param app       - Admin SDK app.
 * @param linkId    - trainer_links document ID; el valor a estampar.
 * @param trainerId - uid del PF.
 * @param athleteId - uid del alumno.
 */
async function backfillChatLinkId(
  app: App,
  linkId: string,
  trainerId: string,
  athleteId: string,
): Promise<void> {
  const db = getFirestore(app);
  const chatId = [trainerId, athleteId].sort().join("_");
  const ref = db.collection("chats").doc(chatId);

  const stamped = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "no-chat";

    const existing = snap.get("linkId");
    if (typeof existing === "string" && existing.length > 0) return "already";

    tx.update(ref, { linkId });
    return "stamped";
  });

  logger.info("notifyOnLinkChange: backfill de linkId", {
    chatId,
    linkId,
    resultado: stamped,
  });
}

/**
 * Pure handler extracted for jest testability.
 *
 * @param app       - Admin SDK app.
 * @param linkId    - trainer_links document ID (event.params.linkId). Used as
 *                    the email dedupe scope.
 * @param before    - Snapshot data before the write (undefined for creates).
 * @param after     - Snapshot data after the write (undefined for deletes).
 * @param messaging - Optional messaging instance for test injection.
 */
export async function notifyOnLinkChangeHandler(
  app: App,
  linkId: string,
  before: LinkData | undefined,
  after: LinkData | undefined,
  messaging?: Messaging,
): Promise<void> {
  // Guard: document deleted — no notification.
  if (!after) {
    logger.info("notifyOnLinkChange: after missing (delete event), skipping");
    return;
  }

  const reason = after.reason as string | undefined;
  const afterStatus = after.status as string | undefined;
  const beforeStatus = before?.status as string | undefined;
  const trainerId = after.trainerId as string | undefined;
  const athleteId = after.athleteId as string | undefined;

  // Guard: cascade delete — account deleted.
  if (reason === "account-deleted") {
    logger.info("notifyOnLinkChange: skipping cascade reason=account-deleted");
    return;
  }

  // Guard: no-op write — status unchanged.
  if (beforeStatus !== undefined && beforeStatus === afterStatus) {
    logger.info("notifyOnLinkChange: status unchanged, skipping", {
      status: afterStatus,
    });
    return;
  }

  if (!trainerId || !athleteId || !afterStatus) {
    logger.warn("notifyOnLinkChange: missing required fields", {
      trainerId,
      athleteId,
      afterStatus,
    });
    return;
  }

  const deepLink = "/coach"; // i18n: Fase 6 Etapa 2 (deepLink is not user-facing copy)
  let recipientUids: string[];
  let title: string;
  let body: string;
  let actorUid: string | undefined;
  // Sólo se setea en la rama `terminated`. `undefined` en el resto significa
  // "no hay nada que purgar", que es lo que lee el efecto de cola.
  let causaTerminacion: CausaDeTerminacion | undefined;

  if (afterStatus === "pending") {
    // New link request → notify trainer.
    recipientUids = [trainerId];
    actorUid = athleteId;
    title = "Nueva solicitud de vinculación"; // i18n: Fase 6 Etapa 2
    body = "Un atleta quiere vincularse contigo."; // i18n: Fase 6 Etapa 2
  } else if (afterStatus === "active") {
    // pending → active = accept; paused → active = resume.
    recipientUids = [athleteId];
    actorUid = trainerId;
    if (beforeStatus === "paused") {
      title = "Vinculación reanudada"; // i18n: Fase 6 Etapa 3
      body = "Tu PF reanudó el vínculo."; // i18n: Fase 6 Etapa 3
    } else {
      title = "¡Vinculación aceptada!"; // i18n: Fase 6 Etapa 2
      body = "Tu entrenador aceptó la vinculación."; // i18n: Fase 6 Etapa 2
    }
  } else if (afterStatus === "paused") {
    // active → paused → notify athlete.
    recipientUids = [athleteId];
    actorUid = trainerId;
    title = "Vinculación pausada"; // i18n: Fase 6 Etapa 3
    body = "Tu PF pausó el vínculo."; // i18n: Fase 6 Etapa 3
  } else if (afterStatus === "terminated") {
    // `terminated` es el MISMO estado para cuatro cosas, y hasta acá las cuatro
    // recibían el mismo texto: "La vinculación entre atleta y entrenador fue
    // finalizada". Para un RECHAZO eso es falso — nunca hubo vinculación. Es el
    // defecto de AGENTS.md §11.1 (un mensaje que describe mal lo que pasó), y
    // le llegaba a la persona a la que peor le cae leerlo.
    //
    // ADR-PN-007 lockeó "terminated → notify BOTH". Esto lo ANGOSTA para los
    // dos casos en los que `terminationReason` dice QUIÉN actuó, y ahí manda a
    // la CONTRAPARTE con `actorUid`, que es exactamente lo que hacen las otras
    // tres ramas. El notify-BOTH sin actor se conserva para el resto, donde el
    // modelo sigue sin saber quién terminó el vínculo (`terminate` lo pueden
    // llamar los dos).
    // UNA sola clasificación para las DOS decisiones que dependen de ella: a
    // quién se le avisa, y si el doc se borra. Antes esta rama miraba sólo
    // `terminationReason` y el purge miraba sólo `acceptedAt`, cada uno por su
    // cuenta — y divergieron: el que decidía el borrado clasificaba como basura
    // vínculos que ESTA rama, en el mismo frame, acababa de tratar como reales.
    causaTerminacion = clasificarTerminacion(after);

    if (causaTerminacion === "rechazo") {
      // El PF rechazó una solicitud. Avisarle a ÉL de su propia acción es ruido.
      const trainerName = await resolveTrainerName(app, trainerId);
      recipientUids = [athleteId];
      actorUid = trainerId;
      title = "Solicitud no aceptada"; // i18n: Fase W1
      // El destino y el texto tienen que decir lo mismo: `/coach` es la
      // discovery, o sea el lugar donde puede hacer algo. Mandarlo al perfil
      // del PF que lo rechazó sería un callejón sin salida.
      body = `${trainerName} no aceptó tu solicitud. ` +
        "Podés buscar otro entrenador."; // i18n: Fase W1
    } else if (causaTerminacion === "cancelacion") {
      // El alumno se arrepintió antes de que el PF contestara. El que necesita
      // enterarse es el PF: tiene una solicitud menos en la bandeja.
      const athleteName = await resolveAthleteName(app, athleteId);
      recipientUids = [trainerId];
      actorUid = athleteId;
      title = "Solicitud cancelada"; // i18n: Fase W1
      body = `${athleteName} canceló su solicitud de vinculación.`; // i18n: Fase W1
    } else {
      // `vinculo-real`: acá SÍ hubo vínculo y el modelo no sabe quién lo cortó
      // (`terminate` lo pueden llamar los dos). Se mantiene ADR-PN-007 tal cual.
      // Incluye el caso que costó el bug: un `acceptedAt` ausente con razón de
      // terminate real, que ES un vínculo y NO se borra.
      recipientUids = [athleteId, trainerId];
      title = "Vinculación finalizada"; // i18n: Fase 6 Etapa 2
      body = "La vinculación entre atleta y entrenador fue finalizada."; // i18n: Fase 6 Etapa 2
    }
  } else {
    logger.info("notifyOnLinkChange: unhandled status transition, skipping", {
      beforeStatus,
      afterStatus,
    });
    return;
  }

  await sendFcm(
    app,
    {
      uids: recipientUids,
      kind: "link-change",
      notification: { title, body },
      data: { deepLink },
      actorUid,
    },
    messaging,
  );

  // Best-effort: a queue failure must never take the push down with it.
  await enqueueLinkMail(app, linkId, after, afterStatus, beforeStatus)
    .catch((error: unknown) => {
      logger.warn("notifyOnLinkChange: mail enqueue failed", { linkId, error });
    });

  // Con el vínculo vigente, el chat preexistente del par tiene que poder
  // escribir. Mismo criterio best-effort que el mail: si el backfill falla, el
  // push ya salió y no se lo lleva puesto.
  if (afterStatus === "active" || afterStatus === "paused") {
    await backfillChatLinkId(app, linkId, trainerId, athleteId)
      .catch((error: unknown) => {
        logger.warn("notifyOnLinkChange: backfill de linkId falló", {
          linkId,
          error,
        });
      });
  }

  // Un rechazo (o una cancelacion del alumno) deja de persistirse: el doc se
  // borra. Ver purge-rejected-link.ts para el discriminador.
  //
  // POR QUE VIVE ACA Y NO EN UN TRIGGER PROPIO. El orden contra la notificacion
  // es el punto entero. Como SEXTO trigger sobre `trainer_links/{linkId}`,
  // "primero se notifica y despues se borra" quedaria a merced de como Eventarc
  // planifique dos invocaciones independientes — que es otra manera de decir
  // que no seria un orden. Al final de este handler, el orden es una propiedad
  // del codigo: sendFcm y enqueueLinkMail ya resolvieron.
  //
  // Hoy hay CINCO (notifyOnLinkChange, linkAggregate, syncSessionShareOnTrainerLink,
  // cleanupAssignedPlansOnUnlink, linkLoadReconcile). El comando, porque una
  // afirmacion de conteo sin el al lado no cuenta (AGENTS.md §11.1):
  //
  //   rg -n 'document: "trainer_links' functions/src --type ts -g '!__tests__'
  //
  // (Una version anterior de este comentario decia "septimo". Estaba mal, y de
  // ese numero colgaba el razonamiento de fan-out.)
  //
  // (Los dos triggers leen `after` del payload del evento, no de Firestore, asi
  // que un borrado concurrente tampoco les vaciaria el snapshot. Pero apoyar el
  // producto en ese detalle del runtime seria confiar en algo que no controlamos
  // y que no se ve leyendo este archivo.)
  //
  // El handler no lanza NUNCA — devuelve false y loguea. Es deliberado: si
  // propagara, un purge fallido volteria toda la invocacion, y un reintento
  // duplicaria el push y su fila en `users/{uid}/notifications`. Las que queden
  // sin borrar las junta el script one-shot (scripts/cleanup_rejected_links.js).
  //
  // Recibe la CAUSA, no el snapshot: la decision ya se tomo arriba, una sola
  // vez, y el purge no puede re-derivarla distinto.
  if (causaTerminacion !== undefined) {
    await purgeRejectedLinkHandler(app, linkId, causaTerminacion);
  }
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-007.
 */
export const notifyOnLinkChange = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await notifyOnLinkChangeHandler(ensureApp(), event.params.linkId, before, after);
  },
);
