/**
 * cancelDuplicatePendingLinks — al aceptar una solicitud de vínculo, cancela las OTRAS
 * solicitudes `pending` del mismo alumno al mismo PF (#1812, sale de #1698 / #1739).
 *
 * Dos dispositivos del alumno pueden crear dos solicitudes al mismo PF: #1739 lo evita en el
 * cliente, pero ni las reglas (ids autogenerados: no pueden buscar «otro doc del par») ni
 * `acceptTrainerLink` lo cierran. Aceptar una dejaba la otra `pending` en la bandeja del PF.
 *
 * Termina con las convenciones que ya existen para cancelar una solicitud (`terminated` +
 * `terminationReason: 'cancelled-by-athlete'`, que `purgeRejectedLink` ya borra) y agrega
 * `reason: DUPLICATE_REQUEST_REASON`. No es decorativo: terminar un link de un par que acaba de
 * quedar vivo dispara triggers escritos para «un solo link por par», y dos lo leen:
 *   - `notifyOnLinkChange`: sin él le avisa al PF «X canceló su solicitud» tras aceptarla.
 *   - `cleanupAssignedPlansOnUnlink`: sin él archiva los planes de un par con vínculo vivo.
 * (`syncSessionShareOnTrainerLink` no lo necesita: sale solo con `pending → terminated`, #1826.)
 *
 * Va DESPUÉS de promover y fuera de su transacción: `pending` pesa 0 en el cupo del PF
 * (`weighted-load.ts`), así que no cambia lo que `syncTrainerLoad` calculó, y un fallo acá no debe
 * tirar abajo un accept ya confirmado. Una transacción por solicitud, que re-lee y sólo escribe si
 * sigue `pending` y sin `acceptedAt`. Idempotente: el reintento de un accept (`noop`) pasa de nuevo.
 */

import { App } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

/**
 * `reason` con el que se termina una solicitud duplicada. Contrato CF->CF, mismo patrón que
 * `TRAINER_ACCOUNT_DELETED_REASON`: un solo símbolo en el productor, importado por los consumidores
 * (`notify-link-change`, `cleanup-assigned-plans`).
 */
export const DUPLICATE_REQUEST_REASON = "duplicate-request";

/**
 * Cancela las solicitudes `pending` del par de `keepLinkId` (el vínculo que se acaba de aceptar).
 * Devuelve cuántas canceló. No hace nada si `keepLinkId` no existe o ya no está `active`.
 */
export async function cancelDuplicatePendingLinks(app: App, keepLinkId: string): Promise<number> {
  const db = getFirestore(app);
  const keep = await db.collection("trainer_links").doc(keepLinkId).get();
  const trainerId = keep.get("trainerId");
  const athleteId = keep.get("athleteId");
  if (!keep.exists || keep.get("status") !== "active") return 0;
  if (typeof trainerId !== "string" || typeof athleteId !== "string") return 0;

  // Igualdad triple: sin índice compuesto, como las demás queries de `trainer_links` por par.
  const pending = await db
    .collection("trainer_links")
    .where("trainerId", "==", trainerId)
    .where("athleteId", "==", athleteId)
    .where("status", "==", "pending")
    .get();

  let cancelled = 0;
  for (const doc of pending.docs) {
    if (doc.id === keepLinkId) continue;
    cancelled += await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      // `acceptedAt` en un `pending` es un defecto de datos: ante la duda no se toca.
      if (!fresh.exists || fresh.get("status") !== "pending" || fresh.get("acceptedAt") != null) return 0;
      tx.update(doc.ref, {
        status: "terminated",
        terminatedAt: FieldValue.serverTimestamp(),
        terminationReason: "cancelled-by-athlete",
        reason: DUPLICATE_REQUEST_REASON,
      });
      return 1;
    });
  }

  if (cancelled > 0) {
    logger.info("cancelDuplicatePendingLinks: solicitudes duplicadas canceladas", {
      keepLinkId,
      trainerId,
      athleteId,
      cancelled,
    });
  }
  return cancelled;
}
