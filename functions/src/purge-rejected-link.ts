/**
 * Borra solicitudes rechazadas o canceladas, después de notificar el cambio.
 *
 * `terminated` es el MISMO estado para cuatro cosas —rechazo del PF,
 * cancelación del alumno, fin de un vínculo real y cambio de entrenador—, así
 * que el status solo no alcanza para decidir un borrado: de los dos últimos
 * cuelgan pagos y sesiones. El discriminador es `acceptedAt`, que sólo estampa
 * el servidor (`subscriptions/promote-link.ts`, al aceptar) y que
 * `firestore.rules` pinea inmutable en create y en update.
 *
 * POR QUÉ NO ALCANZA CON `acceptedAt` — y esto costó un bug en review, así que
 * conviene leerlo antes de simplificar el predicado.
 *
 * Una versión anterior de este archivo borraba con `terminated` +
 * `acceptedAt == null` a secas, y se justificaba diciendo que «este handler
 * sólo ve el `after` de una escritura que ACABA de ocurrir, o sea data nueva».
 * Eso confunde **escritura** nueva con **documento** nuevo: el `after` de un
 * `terminate` sobre un doc de hace un año arrastra el `acceptedAt` (ausente)
 * de hace un año. Un vínculo REAL, con pagos y sesiones, se borraba solo.
 *
 * Y no hace falta data vieja para llegar ahí:
 *
 *   - `firestore.rules` (~781) deja al PF escribir `paused` desde CUALQUIER
 *     status, incluido `pending` — no exige `active` previo.
 *   - `subscriptions/promote-link.ts` (~231) en la rama RESUME promueve a
 *     `active` sin estampar `acceptedAt`: sólo limpia `pausedAt`.
 *
 *   → `pending` → `paused` → `resume` da un vínculo ACTIVO sin la marca, con
 *     datos enteramente nuevos. Después cualquier `terminate` lo dejaba
 *     borrable.
 *
 * Los docs viejos son la otra mitad: `select-blocked-links.ts:192` llama
 * textual «un DEFECTO DE DATOS» a un vínculo sin `acceptedAt`.
 *
 * De estos docs cuelgan las reviews (`reviews/{linkId}_{athleteId}`) y el
 * `linkId` estampado en `chats`, y `firestore.rules` (~811) es
 * `allow delete: if false` — nada los repone.
 *
 * Por eso el criterio es COMPUESTO y es el MISMO que el de
 * `scripts/cleanup_rejected_links.js`: hace falta además que
 * `terminationReason` sea una de las dos razones que sólo se escriben sobre un
 * `pending`. Ese campo SÍ es confiable como señal positiva —
 * `TrainerLinkRepository.decline()` y `.cancel()` lo escriben siempre— y ante
 * su ausencia el handler conserva, que es el lado correcto para equivocarse.
 *
 * NO chequea `reason === 'account-deleted'`: el único llamador
 * (`notifications/notify-link-change.ts`) ya corta antes, y hay un test que lo
 * pinea. Si algún día se llama desde otro lado, ese guard hay que traerlo.
 */
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

/**
 * Las DOS únicas razones que el cliente escribe sobre un vínculo en `pending`
 * (`TrainerLinkRepository.decline` y `.cancel`). Son las únicas que garantizan
 * que el vínculo NUNCA existió.
 *
 * TIENE QUE COINCIDIR con `RAZONES_DE_NO_VINCULO` de
 * `scripts/cleanup_rejected_links.js`. Los dos deciden EL MISMO borrado y no
 * pueden opinar distinto: si alguna vez divergen, gana el que corre solo en
 * producción, que es éste.
 */
const RAZONES_DE_NO_VINCULO = new Set(["declined", "cancelled-by-athlete"]);

export async function purgeRejectedLinkHandler(
  app: admin.app.App,
  linkId: string,
  after: Record<string, unknown> | undefined,
): Promise<boolean> {
  if (after?.status !== "terminated" || after.acceptedAt != null) {
    return false;
  }

  // El tercer requisito, y el que evita destruir historia real. `acceptedAt`
  // solo NO alcanza: ver el bloque «POR QUÉ NO ALCANZA CON acceptedAt» del
  // header. Ante un `terminationReason` ausente, desconocido o que no sea
  // string, se CONSERVA — el modo de falla de este handler tiene que ser
  // siempre "no borré", nunca "borré de más".
  if (!RAZONES_DE_NO_VINCULO.has(after.terminationReason as string)) {
    logger.info(
      "purgeRejectedLink: terminated que no es rechazo ni cancelación, se conserva",
      { linkId, terminationReason: after.terminationReason },
    );
    return false;
  }

  try {
    await admin.firestore(app).collection("trainer_links").doc(linkId).delete();
    return true;
  } catch (error: unknown) {
    logger.error("purgeRejectedLink: no se pudo borrar el rechazo", {
      linkId,
      error,
    });
    return false;
  }
}
