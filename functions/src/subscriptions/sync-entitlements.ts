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
 * Transaccional por el mismo motivo que `syncTrainerLoad`: lee
 * `users/{trainerId}` (necesita `subscription`) y escribe `weightedLoad` ahi
 * mismo, asi que ese par read-write serializa contra las promociones
 * concurrentes. Sin eso, un accept y un downgrade simultaneos podrian dejar la
 * carga inconsistente.
 */

import * as admin from "firebase-admin";

import { effectiveWeightLimit, SubscriptionState } from "./effective-limit";
import { computeWeightedLoad, WeightedLink } from "./weighted-load";
import { reconcileEntitlements, BlockableLink } from "./select-blocked-links";

export interface SyncEntitlementsResult {
  trainerId: string;
  limit: number;
  blocked: string[];
  unblocked: string[];
  weightedLoad: number;
}

function toSubscriptionState(
  data: admin.firestore.DocumentData | undefined,
): SubscriptionState | null {
  const sub = data?.subscription as
    | {
        tier: SubscriptionState["tier"];
        status: SubscriptionState["status"];
        currentPeriodEnd?: admin.firestore.Timestamp | null;
      }
    | undefined;
  if (!sub) return null;
  return {
    tier: sub.tier,
    status: sub.status,
    currentPeriodEndMs: sub.currentPeriodEnd
      ? sub.currentPeriodEnd.toMillis()
      : null,
  };
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

    const sub = toSubscriptionState(trainerSnap.data());
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

    // Carga resultante: se recalcula sobre el estado YA reconciliado, no sobre
    // el previo. Si se usara el previo, `weightedLoad` mostraria la carga vieja
    // hasta el proximo trigger.
    const after: WeightedLink[] = links.map((l) => ({
      athleteId: l.athleteId,
      status: l.status,
      entitlement: block.includes(l.id)
        ? "blocked"
        : unblock.includes(l.id)
          ? "entitled"
          : l.entitlement,
    })) as WeightedLink[];
    const weightedLoad = computeWeightedLoad(after);

    // ── frontera: writes ──────────────────────────────────────────────────
    for (const id of block) {
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

    return { trainerId, limit, blocked: block, unblocked: unblock, weightedLoad };
  });
}
