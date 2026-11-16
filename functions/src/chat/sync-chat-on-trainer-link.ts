/**
 * syncChatOnTrainerLink — Cloud Function for TREINO (#1697).
 *
 * Al terminar el vínculo PF-alumno el chat del par se CIERRA (nadie escribe, el
 * historial sigue legible); un re-vínculo lo REABRE; `paused` lo deja abierto
 * (un hold, QA H8). El cierre es `chats/{id}.closedAt`, que escribe SÓLO esta
 * función; ausente = abierto. Las reglas lo leen, así que se despliegan ANTES.
 *
 * `onDocumentWritten` (create: nace ya vivo, sólo Admin SDK; update; delete).
 * "Vivo" = `active|paused`; `athlete-terminated` es un `terminationReason`, no un status.
 *
 *   vivo → no vivo   reconcilia: cierra si no queda otro vivo. Incluye la
 *                    cascada de borrado de cuenta (`reason: 'account-deleted'`
 *                    y `'trainer-account-deleted'`).
 *   no vivo → vivo   reconcilia: reabre (el re-vínculo).
 *   vivo → vivo      nada (active↔paused, barrido de entitlements): sale sin leer.
 *   no vivo → no     nada. pending → terminated (rechazo/cancelación) NO cierra:
 *   vivo             los chats de consulta previos al vínculo sobreviven.
 *
 * RECONCILIA, NO ESPEJA: el evento sólo decide si hay algo que mirar; lo que se
 * escribe sale del estado ACTUAL del par, releído en la transacción. (1) Las
 * reglas permiten varios vínculos por par: que termine uno no cierra si otro
 * sigue vivo (misma trampa que sync-session-share.ts). (2) Los triggers son
 * at-least-once y sin orden: un `pending → active` reentregado tras terminar el
 * vínculo, con un «abrir» a ciegas, reabriría un chat que debía estar cerrado.
 *
 * Sin chat para el par no hace nada (no lo crea). Id: `[trainerId, athleteId].sort().join("_")`.
 *
 * Una query por status (`==`), la forma exacta de notify-session-finished.ts (~206),
 * y no `status in [...]`: el emulador no valida índices, así que acá no se puede
 * probar que el `in` no pida uno nuevo. `retry: true`: sin reintento, un fallo
 * transitorio deja el chat abierto para siempre (el bug de #1697); es idempotente.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** Status que mantienen el chat abierto. Espeja `chatCreateOk` (rules ~2962). */
export const LIVE_LINK_STATUSES = ["active", "paused"] as const;

type LinkData = Record<string, unknown>;

/** Qué hizo el handler; lo devuelve para que los tests no dependan de los logs. */
export type SyncChatResult = "skipped" | "invalid" | "no-chat" | "closed" | "reopened" | "unchanged";

const isLive = (link: LinkData | undefined): boolean =>
  link !== undefined &&
  (LIVE_LINK_STATUSES as readonly string[]).includes(link.status as string);

/** Pure handler extracted for jest testability (`linkId` es sólo para los logs). */
export async function syncChatOnTrainerLinkHandler(
  app: App,
  linkId: string,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<SyncChatResult> {
  if (isLive(before) === isLive(after)) return "skipped";

  // trainerId/athleteId están pineados inmutables en `trainer_links/update`.
  const source = after ?? before;
  const trainerId = source?.trainerId as string | undefined;
  const athleteId = source?.athleteId as string | undefined;
  if (!trainerId || !athleteId) {
    logger.warn("syncChatOnTrainerLink: falta trainerId o athleteId", { linkId });
    return "invalid";
  }

  const db = getFirestore(app);
  const chatId = [trainerId, athleteId].sort().join("_");
  const chatRef = db.collection("chats").doc(chatId);
  const pairLinks = db
    .collection("trainer_links")
    .where("athleteId", "==", athleteId)
    .where("trainerId", "==", trainerId);

  const result = await db.runTransaction(async (tx): Promise<SyncChatResult> => {
    // Todas las lecturas antes de la primera escritura.
    const [chatSnap, liveSnaps] = await Promise.all([
      tx.get(chatRef),
      Promise.all(
        LIVE_LINK_STATUSES.map((s) => tx.get(pairLinks.where("status", "==", s).limit(1))),
      ),
    ]);
    if (!chatSnap.exists) return "no-chat";

    const hasLive = liveSnaps.some((snap) => !snap.empty);
    const isClosed = chatSnap.get("closedAt") != null;
    if (hasLive && isClosed) {
      tx.update(chatRef, { closedAt: FieldValue.delete() });
      return "reopened";
    }
    if (!hasLive && !isClosed) {
      tx.update(chatRef, { closedAt: FieldValue.serverTimestamp() });
      return "closed";
    }
    return "unchanged";
  });

  logger.info("syncChatOnTrainerLink", { linkId, chatId, resultado: result });
  return result;
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const syncChatOnTrainerLink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1", retry: true },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await syncChatOnTrainerLinkHandler(ensureApp(), event.params.linkId, before, after);
  },
);
