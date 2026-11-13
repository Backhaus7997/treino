/**
 * syncTrainerAthletePair — Cloud Function for TREINO (#1806).
 *
 * Mantiene `trainer_athlete_pairs/{trainerId}_{athleteId}`: el doc
 * DETERMINÍSTICO por par que las reglas pueden leer con un `get()` para
 * preguntar «¿este PF tiene un vínculo vivo con este alumno?». `trainer_links`
 * usa ids autogenerados y las reglas no hacen queries; este doc es la
 * conclusión de esa query, escrita por el Admin SDK. Los clientes sólo lo LEEN
 * (los dos miembros); nadie más lo escribe.
 *
 *   { trainerId, athleteId, live, status, updatedAt }
 *
 *   status  el MEJOR status entre TODOS los vínculos del par, en este orden:
 *           active > paused > pending > terminated.
 *   live    status in [active, paused]. Espeja `LIVE_LINK_STATUSES` del chat
 *           (#1697) y el `status in ['active','paused']` de reviews/chats en
 *           las reglas: pausar es un hold, no un fin.
 *
 * El id NO va ordenado (a diferencia del chat): PF primero, porque la regla lo
 * arma con `$(request.auth.uid)_$(athleteId)` y sabe quién es cada uno.
 *
 * RECONCILIA, NO ESPEJA (el patrón de sync-chat-on-trainer-link.ts): el evento
 * sólo decide si hay algo que mirar; lo que se escribe sale de releer TODOS los
 * vínculos del par adentro de una transacción. (1) Las reglas permiten varios
 * vínculos por par: que termine uno viejo no apaga el par si otro sigue vivo.
 * (2) Los triggers son at-least-once y sin orden: un `pending → active`
 * reentregado después de terminar no puede volver a prender el par.
 *
 *   create / delete del vínculo        reconcilia.
 *   cambio de `status`                 reconcilia.
 *   update sin cambio de `status`      nada, sin leer (el barrido de
 *                                      entitlements toca vínculos vivos todo
 *                                      el tiempo). El par que falte lo crea el
 *                                      backfill, no este camino.
 *
 * Sin vínculos para el par (todos borrados: la purga de rechazos), el doc se
 * BORRA: no hay relación que describir. Un par terminado se CONSERVA con
 * `live: false`: es la marca de «fue tu alumno».
 *
 * Una query por par sin `status` (sólo dos `==`, que el emulador y producción
 * resuelven con los índices de un campo); los vínculos de un par son pocos.
 * `retry: true`: sin reintento, un fallo transitorio deja el par desfasado
 * hasta el próximo cambio de status; es idempotente.
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

export const PAIRS_COLLECTION = "trainer_athlete_pairs";

/** Del mejor al peor. El primero presente entre los vínculos del par es el `status`. */
export const PAIR_STATUS_ORDER = ["active", "paused", "pending", "terminated"] as const;
export type PairStatus = (typeof PAIR_STATUS_ORDER)[number];

/** Status que cuentan como vínculo vivo. Espeja `LIVE_LINK_STATUSES` del chat. */
export const LIVE_PAIR_STATUSES: readonly PairStatus[] = ["active", "paused"];

type LinkData = Record<string, unknown>;

/** Qué hizo el handler; lo devuelve para que los tests no dependan de los logs. */
export type SyncPairResult = "skipped" | "invalid" | "written" | "deleted" | "unchanged";

export const pairIdFor = (trainerId: string, athleteId: string): string =>
  `${trainerId}_${athleteId}`;

/**
 * Status del par a partir de los status de sus vínculos. Puro: lo comparte el
 * backfill. `null` = sin vínculos (el doc no tiene que existir). Un status
 * desconocido no suma; si no hay ninguno conocido, el par cuenta `terminated`
 * (no vivo: ante la duda, cerrado).
 */
export function reducePairStatus(statuses: readonly unknown[]): PairStatus | null {
  if (statuses.length === 0) return null;
  return PAIR_STATUS_ORDER.find((s) => statuses.includes(s)) ?? "terminated";
}

export const isLivePairStatus = (status: PairStatus | null): boolean =>
  status !== null && LIVE_PAIR_STATUSES.includes(status);

/** Pure handler extracted for jest testability (`linkId` es sólo para los logs). */
export async function syncTrainerAthletePairHandler(
  app: App,
  linkId: string,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<SyncPairResult> {
  if (before && after && before.status === after.status) return "skipped";

  // trainerId/athleteId están pineados inmutables en `trainer_links/update`.
  const source = after ?? before;
  const trainerId = source?.trainerId;
  const athleteId = source?.athleteId;
  if (typeof trainerId !== "string" || !trainerId || typeof athleteId !== "string" || !athleteId) {
    logger.warn("syncTrainerAthletePair: falta trainerId o athleteId", { linkId });
    return "invalid";
  }

  const db = getFirestore(app);
  const pairId = pairIdFor(trainerId, athleteId);
  const pairRef = db.collection(PAIRS_COLLECTION).doc(pairId);
  const pairLinks = db
    .collection("trainer_links")
    .where("athleteId", "==", athleteId)
    .where("trainerId", "==", trainerId);

  const result = await db.runTransaction(async (tx): Promise<SyncPairResult> => {
    // Todas las lecturas antes de la primera escritura.
    const [pairSnap, linksSnap] = await Promise.all([tx.get(pairRef), tx.get(pairLinks)]);
    const status = reducePairStatus(linksSnap.docs.map((d) => d.get("status")));

    if (status === null) {
      if (!pairSnap.exists) return "unchanged";
      tx.delete(pairRef);
      return "deleted";
    }

    const live = isLivePairStatus(status);
    if (
      pairSnap.exists &&
      pairSnap.get("status") === status &&
      pairSnap.get("live") === live &&
      pairSnap.get("trainerId") === trainerId &&
      pairSnap.get("athleteId") === athleteId
    ) {
      return "unchanged";
    }
    tx.set(pairRef, { trainerId, athleteId, live, status, updatedAt: FieldValue.serverTimestamp() });
    return "written";
  });

  logger.info("syncTrainerAthletePair", { linkId, pairId, resultado: result });
  return result;
}

/** Cloud Function trigger. Deployed to southamerica-east1 per ADR-PN-005. */
export const syncTrainerAthletePair = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1", retry: true },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await syncTrainerAthletePairHandler(ensureApp(), event.params.linkId, before, after);
  },
);
