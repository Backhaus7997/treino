/**
 * sync-entitlements.ts — escribe `entitlement` en los vinculos de un PF segun
 * su limite efectivo (paywall Fase 7, downgrade).
 *
 * EL AGUJERO QUE CIERRA: el gate de `syncTrainerLoad` impide ACEPTAR por
 * encima del limite, pero no hace nada con los que ya estaban adentro. Un PF
 * con 7 alumnos cuya suscripcion vence pasa a limite 2 y conserva los 7: el
 * limite queda decorativo para todo el que ya entro.
 *
 * QUE SIGNIFICA BLOQUEADO HOY: el vinculo deja de contar para el limite. Nada
 * mas — `entitlement` no aparece todavia en ninguna clausula de
 * firestore.rules. El enforcement del lado del PF llega en un slice posterior.
 * **El alumno NO pierde nada en ningun caso**: conserva rutinas, historial y
 * chat. La presion va sobre quien paga.
 *
 * DATOS DEGRADADOS: si `subscription` no se pudo leer bien, este barrido NO
 * bloquea a nadie — solo devuelve. Ver la valvula mas abajo y la POLITICA en
 * subscription-state.ts.
 *
 * Transaccional por el mismo motivo que `syncTrainerLoad`: lee
 * `users/{trainerId}` (necesita `subscription`) y escribe `weightedLoad` ahi
 * mismo, asi que ese par read-write serializa contra las promociones
 * concurrentes. Sin eso, un accept y un downgrade simultaneos podrian dejar la
 * carga inconsistente.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { effectiveWeightLimit } from "./effective-limit";
import { toSubscriptionState } from "./subscription-state";
import { computeWeightedLoad, WeightedLink } from "./weighted-load";
import { reconcileEntitlements, BlockableLink } from "./select-blocked-links";

export interface SyncEntitlementsResult {
  trainerId: string;
  /** `null` = sin limite (plan3). */
  limit: number | null;
  /**
   * ids efectivamente bloqueados. Vacio cuando la `subscription` venia
   * degradada, aunque `limit` diga que sobran vinculos: ver la valvula.
   */
  blocked: string[];
  unblocked: string[];
  weightedLoad: number;
}

/**
 * Reconcilia `entitlement` para todos los vinculos de un PF.
 *
 * Idempotente: si el estado ya es correcto no escribe nada, asi el barrido
 * diario no reescribe los mismos campos todos los dias.
 */
export async function syncTrainerEntitlements(
  app: admin.app.App,
  trainerId: string,
  nowMs?: number,
): Promise<SyncEntitlementsResult> {
  const db = admin.firestore(app);
  const clock = nowMs ?? Date.now();

  return db.runTransaction(async (tx) => {
    // Reads-before-writes: Firestore exige TODAS las lecturas antes de la
    // primera escritura.
    const [trainerSnap, linksSnap] = await Promise.all([
      tx.get(db.collection("users").doc(trainerId)),
      tx.get(db.collection("trainer_links").where("trainerId", "==", trainerId)),
    ]);

    const { state: sub, degraded } = toSubscriptionState(trainerSnap.data(), trainerId);
    const limit = effectiveWeightLimit(sub, clock);

    const links: BlockableLink[] = linksSnap.docs.map((doc) => {
      const d = doc.data() as admin.firestore.DocumentData;
      const acceptedAt = d.acceptedAt as admin.firestore.Timestamp | undefined;
      return {
        id: doc.id,
        athleteId: d.athleteId as string,
        status: d.status as BlockableLink["status"],
        entitlement: d.entitlement as BlockableLink["entitlement"],
        acceptedAtMs: acceptedAt ? acceptedAt.toMillis() : null,
      };
    });

    const { block, unblock } = reconcileEntitlements(links, limit);

    // ── VALVULA DE DEGRADACION ────────────────────────────────────────────
    //
    // POLITICA (definida en subscription-state.ts): la degradacion de datos
    // frena TRABAJO NUEVO (friccion sobre el entrenador) pero NUNCA revoca
    // relaciones existentes (friccion sobre el alumno).
    //
    // El barrido es el lado "no revoca". Si el mapa `subscription` no se
    // entendio, el `limit` que llego aca no sale de lo que el PF pago: sale del
    // fallback conservador. Bloquear con ese numero significa cortarle el
    // servicio a los alumnos de un PF que capaz pago plan3, por un typo
    // NUESTRO. `unblock` SI corre — devolver nunca puede empeorar la situacion
    // de un alumno, y un PF con datos rotos no tiene por que quedarse ademas
    // con vinculos bloqueados de un downgrade anterior.
    //
    // Asimetrico contra el gate de promote-link.ts, que con el mismo flag sigue
    // denegando. Es la asimetria del enunciado, no una inconsistencia.
    const blockNow = degraded ? [] : block;
    if (degraded && block.length > 0) {
      // error y no warn: es accionable y hay UN documento que arreglar a mano.
      // Va con el uid y con los ids salteados porque sin eso no hay como saber
      // a quien se le esta perdonando el limite ni por cuanto tiempo.
      logger.error(
        "sync-entitlements: subscription degradada — se SALTEA el bloqueo",
        { trainerId, limit, skippedBlock: block, skippedCount: block.length },
      );
    }

    // Carga resultante: se recalcula sobre el estado YA reconciliado, no sobre
    // el previo. Si se usara el previo, `weightedLoad` mostraria la carga vieja
    // hasta el proximo trigger. Con la valvula abierta esto refleja la carga
    // REAL (nadie fue bloqueado), que es justamente lo que hace visible el
    // documento roto: un weightedLoad por arriba del limite.
    const after: WeightedLink[] = links.map((l) => ({
      athleteId: l.athleteId,
      status: l.status,
      entitlement: blockNow.includes(l.id)
        ? "blocked"
        : unblock.includes(l.id)
          ? "entitled"
          : l.entitlement,
    })) as WeightedLink[];
    const weightedLoad = computeWeightedLoad(after);

    // ── frontera: writes ──────────────────────────────────────────────────
    for (const id of blockNow) {
      tx.update(db.collection("trainer_links").doc(id), {
        entitlement: "blocked",
        blockedAt: admin.firestore.Timestamp.fromMillis(clock),
        blockedReason: "over-limit",
      });
    }
    for (const id of unblock) {
      tx.update(db.collection("trainer_links").doc(id), {
        entitlement: "entitled",
        blockedAt: admin.firestore.FieldValue.delete(),
        blockedReason: admin.firestore.FieldValue.delete(),
      });
    }
    tx.set(
      db.collection("users").doc(trainerId),
      { weightedLoad },
      { merge: true },
    );

    return { trainerId, limit, blocked: blockNow, unblocked: unblock, weightedLoad };
  });
}
