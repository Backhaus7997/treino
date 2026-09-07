/**
 * Borra solicitudes rechazadas o canceladas después de notificar el cambio.
 *
 * `acceptedAt` es el discriminador persistido por el servidor: si nunca fue
 * estampado, el documento nunca representó una relación real. Los vínculos
 * aceptados conservan su historia aunque luego terminen.
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
