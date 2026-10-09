/**
 * Aviso al equipo cuando entra un reporte.
 *
 * Sin esto, la cola de `report-review.ts` existe pero nadie la mira, y las 24
 * horas que promete `docs/legal/normas-de-comunidad.md:123` —un documento
 * publicado, que el usuario acepta— siguen siendo mentira. La cola no es lo que
 * hace verdadera la promesa: lo que la hace verdadera es que alguien se entere.
 *
 * ## Que NO viaja en el correo
 *
 * El contenido reportado. Solo van el id del reporte, el tipo de objetivo y el
 * motivo. Un mail con el texto adentro es una copia de datos personales de
 * terceros viajando a un buzon, y en el chat pueden ser datos de salud. El
 * contenido se mira en la cola, autenticado.
 *
 * Tampoco va el `detail` que escribio el denunciante, por lo mismo: es texto
 * libre y puede citar lo que le dijeron.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { MAIL_QUEUE_COLLECTION } from "../mail/types";

/**
 * El app de firebase-admin, inicializado si hace falta.
 *
 * `getFirestore()` SIN argumento busca el app por defecto y tira «The default
 * Firebase app does not exist» si nadie lo inicializo. `index.ts` no llama a
 * `initializeApp()`: cada modulo se lo asegura solo (mismo patron que
 * `sync-shared-profile.ts` y el resto del repo). Este modulo no lo hacia, y en
 * produccion fallaba en CADA invocacion desde el primer deploy. Los tests no
 * lo veian porque inicializaban el app por defecto ellos mismos.
 */
function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

const REGION = "southamerica-east1";

/** Buzon del equipo. Es el mismo que publica `docs/legal/`. */
export const MODERATION_MAILBOX = "treino@gettreino.com";

export const notifyReportCreated = onDocumentCreated(
  // `retry: true`, igual que `sendQueuedMail` y por el mismo motivo: sin el,
  // un fallo transitorio al encolar pierde PARA SIEMPRE el unico aviso que le
  // dice al equipo que hay un reporte nuevo — y el reporte queda en la cola sin
  // que nadie sepa que existe, que es el estado que esta funcion viene a
  // impedir.
  //
  // Es seguro reintentar porque el id del documento es deterministico: el
  // segundo intento choca con ALREADY_EXISTS y no manda un segundo mail.
  { document: "reports/{reportId}", region: REGION, retry: true },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reportId = event.params.reportId;

    // Id derivado del reporte, no autogenerado: `reports` es append-only y su
    // id es deterministico, asi que un reintento del trigger —que Firestore
    // puede hacer, los triggers son at-least-once— no manda el mail dos veces.
    await getFirestore(ensureApp())
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(`moderation-report-created__${reportId}`)
      .create({
        toUid: "",
        toAddress: MODERATION_MAILBOX,
        kind: "moderation-report-created",
        params: {
          reportId,
          targetKind: String(snap.get("targetKind") ?? "?"),
          reason: String(snap.get("reason") ?? "sin motivo"),
        },
        status: "pending",
        attempts: 0,
        createdAt: new Date(),
      })
      .catch((err: { code?: number }) => {
        // `create` falla si el doc ya existe (ALREADY_EXISTS = 6). Eso es
        // exactamente lo que se busca: el segundo disparo del mismo reporte no
        // encola un segundo mail. Cualquier otro error si se propaga.
        if (err?.code === 6) {
          logger.info("notifyReportCreated: ya encolado", { reportId });
          return;
        }
        throw err;
      });

    logger.info("notifyReportCreated: aviso encolado", { reportId });
  },
);
