/**
 * syncSessionShareOnTrainerLink — Cloud Function for TREINO.
 *
 * Fires on every WRITE to `trainer_links/{linkId}` (`onDocumentWritten` — a
 * write trigger, NOT a transition trigger). Owns `session_shares/{athleteId}`,
 * the doc that grants a trainer read access to the athlete's sessions and their
 * setLogs (firestore.rules ~1471 / ~1485). For self-logged measurements it is
 * NECESSARY BUT NOT SUFFICIENT: that clause (~1727) demands a matching
 * `profile_shares/{athleteId}` as well, which this handler does not own.
 *
 * CONTRACT. `session_shares/{athleteId}` holds ONE trainerId, but an athlete can
 * hold several trainer_links at once, so this handler is deliberately NOT a
 * mirror of one link's status. It is authoritative only over its OWN claim:
 *
 *   - status TRANSITIONED into `active` (pending → active, paused → active, or
 *     a create that already reads `active`)
 *     → set the share to this trainer, OVERWRITING whoever held it, without
 *       reading first. This is the one write that ignores ownership; the branch
 *       comment spells out why, and which window it leaves open.
 *   - status IS `active` but did NOT change (entitlement sweep write, or any
 *     unrelated field edit on a live link)
 *     → read the share first and write ONLY when nobody else holds it: rebuild
 *       it when it is missing, leave it untouched when it names another trainer.
 *   - `after` absent (delete) OR status is not `active`
 *     → read the share and delete it, but only while it still carries THIS
 *       trainerId. Pointing at a different trainer → leave it alone.
 *
 * WHAT IS GUARANTEED, and what is NOT. The guard is about OWNERSHIP, not about
 * status — and it is narrower than "this trainer always has a share":
 *
 *   1. It NEVER deletes a share that names another trainer. The only exit that
 *      actually deletes is gated on the stored trainerId matching this one; the
 *      other revoke exit returns early because there is no doc to remove. So no
 *      path removes someone else's claim.
 *   2. OUTSIDE a real transition into `active` it never overwrites another
 *      trainer's claim either. ON a real transition it does, deliberately and
 *      unconditionally — see the transition branch.
 *   3. Rebuilding a lost share is BEST EFFORT, not an invariant. While this
 *      link is active and NOBODY holds the share, the next write to that link
 *      puts it back. Two ways this trainer is still left without one:
 *        - another trainer holds the share and nothing transitions here → this
 *          handler exits without writing, and this trainer stays without read
 *          access until EITHER its own link transitions into `active` again, OR
 *          the other claim disappears (that trainer's link leaves `active`, so
 *          their own revoke deletes it) and any later write to this live link
 *          rebuilds it;
 *        - terminating an OLD link of the SAME pair deletes the share the live
 *          link needs (rules allow several historical links per pair,
 *          firestore.rules ~474; the trainerId check cannot tell them apart)
 *          → repaired on the NEXT write to the live link, not immediately.
 *
 * `entitlement: 'blocked'` is on purpose NOT part of this contract. The sweep
 * (subscriptions/sync-entitlements.ts) writes entitlement/blockedAt/
 * blockedReason and leaves `status` alone, and `entitlement` gates no read
 * clause in firestore.rules — a blocked-but-active link keeps its share.
 *
 * Uses Admin SDK (bypasses Firestore security rules).
 *
 * Deployed to southamerica-east1 per ADR-PN-005.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

type LinkData = Record<string, unknown>;

/**
 * Pure handler extracted for jest testability.
 *
 * @param app    - Admin SDK app.
 * @param before - Snapshot data before the write (undefined for creates).
 * @param after  - Snapshot data after the write (undefined for deletes).
 */
export async function syncSessionShareHandler(
  app: admin.app.App,
  before: LinkData | undefined,
  after: LinkData | undefined,
): Promise<void> {
  const db = admin.firestore(app);

  // Derive identity from whichever snapshot is present.
  const source = after ?? before;
  if (!source) {
    logger.warn("syncSessionShare: both before and after are missing — skipping");
    return;
  }

  const trainerId = source.trainerId as string | undefined;
  const athleteId = source.athleteId as string | undefined;
  const status = (after?.status as string | undefined) ?? "";
  const beforeStatus = before?.status as string | undefined;

  if (!trainerId || !athleteId) {
    logger.warn("syncSessionShare: missing trainerId or athleteId", {
      trainerId,
      athleteId,
    });
    return;
  }

  const shareRef = db.collection("session_shares").doc(athleteId);

  /** Points the share at this trainer. `reason` separates both call sites in prod logs. */
  const grantShare = async (reason: "transition" | "repair"): Promise<void> => {
    await shareRef.set({
      trainerId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info("syncSessionShare: share granted", { trainerId, athleteId, reason });
  };

  if (after && status === "active") {
    if (beforeStatus !== status) {
      // Transicion REAL hacia active. Se otorga incondicional y se PISA el
      // share de otro PF si lo hubiera, sin leer antes. El consentimiento del
      // alumno NO es parejo entre los casos, y conviene no venderlo como si lo
      // fuera:
      //
      //   - pending → active (accept): el vinculo existe porque LO CREO EL
      //     ALUMNO — firestore.rules ~487 solo deja crear al athleteId y solo
      //     en `pending`. El alumno pidio a este PF. El write lo hace el PF
      //     (acceptTrainerLink; promote-link.ts ~129 rechaza a quien no sea el
      //     trainer del vinculo), asi que el consentimiento viene del create y
      //     no de este write — pero existe.
      //   - paused → active (resume): lo maneja SOLO el PF (resumeTrainerLink,
      //     mismo chequeo de caller). El alumno no participa en ningun punto.
      //   - create ya en `active`: imposible desde un cliente (las rules fuerzan
      //     `pending` en el create). Solo Admin SDK o backfill.
      //
      // VENTANA CONOCIDA que queda abierta, escrita aca para que el proximo que
      // lea no la tome por descuido: PF1 pausa el vinculo (se revoca el share),
      // PF2 acepta el request del alumno y toma el share, PF1 hace resume y se
      // lo lleva de vuelta. PF2 —al dia, y sin que ni el alumno ni el hayan
      // hecho nada— pierde sessions, setLogs y measurements hasta la proxima
      // transicion hacia `active` de su propio vinculo.
      //
      // NO se arregla aca a proposito. Es last-writer-wins sobre una transicion
      // GENUINA, y es un limite del DOC: `session_shares/{athleteId}` guarda UN
      // solo trainerId, asi que dos vinculos activos no pueden coexistir en el.
      // Arbitrar entre dos PF activos pide otra forma de documento y es su
      // propio cambio. Lo que esta version mata es el robo INVOLUNTARIO —el de
      // las escrituras SIN transicion del barrido de entitlements sobre
      // vinculos vivos—, y de eso se ocupa la guarda por contenido de abajo.
      // Pineado tal como esta hoy en sync-session-share.test.ts ("LIMITE
      // CONOCIDO"), para que cambiarlo sea deliberado.
      await grantShare("transition");
      return;
    }

    // Sin transicion: el vinculo YA estaba activo y este write toco otra cosa.
    // Este trigger es onDocumentWritten, corre en cada escritura, y el barrido
    // de entitlements (subscriptions/sync-entitlements.ts) hace tx.update de
    // entitlement/blockedAt/blockedReason sobre vinculos vivos. Re-estampar el
    // share a ciegas aca era el ROBO: con un alumno vinculado a DOS PF, bloquear
    // el vinculo de PF1 le movia el share a PF1, y PF2 —al dia— perdia sessions,
    // setLogs y measurements. El enforcement multiplica esas escrituras.
    //
    // La guarda es por CONTENIDO, no por status: leemos el share y escribimos
    // solo si nadie mas lo reclama. Mata el robo igual, pero conserva la
    // REPARACION que el re-estampado daba de rebote y que una guarda por status
    // habria matado — y esa reparacion es la unica que hay: no existe reintento
    // para un set() de grant fallido (no hay un solo `retry: true` en el modulo),
    // asi que un grant perdido seria permanente y silencioso.
    //
    // COSTO, dicho derecho: este get() SI es nuevo en ESTE camino. Antes, una
    // escritura sin transicion sobre un vinculo activo hacia un set() a ciegas
    // y cero lecturas; ahora hace un get() por cada una de esas escrituras, y el
    // barrido de entitlements multiplica justamente esas. Que el camino de
    // revocacion de abajo ya pagara un get() no lo vuelve gratis aca: son
    // caminos distintos y el de grant no lo pagaba.
    //
    // Contra que se compara: en el caso comun —el share ya es nuestro— el get()
    // REEMPLAZA al set() que se hacia antes, o sea una lectura en lugar de una
    // escritura, que es el lado barato de la facturacion de Firestore. Los dos
    // juntos (get + set) solo se pagan cuando hay algo que reparar, y eso ocurre
    // una vez por agujero, no una vez por write. La alternativa de costo cero
    // era la guarda por status, y esa se descarto por lo de arriba: mata la
    // reparacion.
    const shareSnap = await shareRef.get();
    const existingTrainerId = shareSnap.data()?.trainerId as string | undefined;

    if (existingTrainerId === trainerId) {
      // Ya apunta a nosotros. No reescribir: solo moveria `updatedAt`.
      //
      // Esta rama y la de abajo salen las DOS sin escribir, asi que el estado
      // final no las distingue: lo unico observable que las separa es este log.
      // Por eso el test que la pinea assertea el mensaje — si lo reescribis,
      // actualizalo tambien en sync-session-share.test.ts.
      logger.info("syncSessionShare: share already correct, skipping", {
        trainerId,
        athleteId,
      });
      return;
    }

    if (existingTrainerId) {
      // Lo tiene otro PF y este write no promovio nada → no es nuestro para tomar.
      logger.info("syncSessionShare: share belongs to a different trainer — skipping grant", {
        trainerId,
        athleteId,
        existingTrainerId,
      });
      return;
    }

    // Falta el doc, o existe sin trainerId (inservible para cualquier PF: los
    // rules comparan `.data.trainerId == request.auth.uid`). Nadie lo reclama y
    // nuestro vinculo esta activo → reconstruir.
    await grantShare("repair");
    return;
  }

  // Link deleted or no longer active → conditionally remove the share.
  //
  // Este camino a proposito NO mira si el status cambio: un share que sobrevivio
  // a su vinculo es basura por definicion, y el chequeo de trainerId de abajo
  // —que sigue vigente— ya impide tocar el de otro PF. Lo que hacia PELIGROSA
  // esta asimetria era un grant que no reparase: los rules permiten varios
  // vinculos historicos por par (firestore.rules ~474), asi que terminar el
  // viejo borra el share que el nuevo —activo y del MISMO PF— necesita. Con la
  // guarda por contenido de arriba, la proxima escritura sobre ese vinculo vivo
  // lo reconstruye — no de inmediato, sino en el proximo write; por eso el
  // borrado puede seguir siendo incondicional, y por eso el punto 3 del header
  // habla de reparacion BEST EFFORT y no de invariante.
  const shareSnap = await shareRef.get();
  if (!shareSnap.exists) {
    // Nothing to clean up.
    return;
  }

  const existingTrainerId = shareSnap.data()?.trainerId as string | undefined;
  if (existingTrainerId !== trainerId) {
    // The share points to a different trainer (e.g. athlete re-linked to someone
    // else and that CF already wrote). Do NOT remove it.
    logger.info(
      "syncSessionShare: share belongs to a different trainer — skipping delete",
      { trainerId, athleteId, existingTrainerId },
    );
    return;
  }

  await shareRef.delete();
  logger.info("syncSessionShare: share revoked", { trainerId, athleteId });
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const syncSessionShareOnTrainerLink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    await syncSessionShareHandler(getApp(), before, after);
  },
);
