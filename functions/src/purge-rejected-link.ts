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
 * HASTA DÓNDE VALE ESO, porque escrito sin límite es un cartel falso y este
 * repo ya pagó por uno (AGENTS.md §11.1):
 *
 *   - Para lo que se escribe DE ACÁ EN ADELANTE, sí es hermético: no hay
 *     camino a `active` que no pase por promote-link, y el pin de las rules
 *     impide que un cliente lo invente.
 *   - Para docs VIEJOS, NO. `subscriptions/select-blocked-links.ts:192` llama
 *     textual «un DEFECTO DE DATOS» a un vínculo sin `acceptedAt`, y
 *     `promote-link.ts:221` describe un stamp faltante que degrada a
 *     `requestedAt` en vez de fallar. O sea que puede existir un vínculo REAL
 *     viejo sin la marca.
 *
 * Acá esa distinción no muerde: este handler sólo ve el `after` de una
 * escritura que ACABA de ocurrir, o sea data nueva. Sí muerde en la limpieza
 * retroactiva, y por eso `scripts/cleanup_rejected_links.js` NO borra sólo por
 * `acceptedAt`: exige además que `terminationReason` sea de rechazo o
 * cancelación, y manda el resto a un grupo ambiguo que no toca.
 *
 * NO chequea `reason === 'account-deleted'`: el único llamador
 * (`notifications/notify-link-change.ts`) ya corta antes, y hay un test que lo
 * pinea. Si algún día se llama desde otro lado, ese guard hay que traerlo.
 */
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

export async function purgeRejectedLinkHandler(
  app: admin.app.App,
  linkId: string,
  after: Record<string, unknown> | undefined,
): Promise<boolean> {
  if (after?.status !== "terminated" || after.acceptedAt != null) {
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
