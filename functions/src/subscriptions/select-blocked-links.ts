/**
 * select-blocked-links.ts — decide QUIENES quedan bloqueados cuando un PF
 * queda por encima de su limite efectivo (paywall Fase 7, downgrade).
 *
 * Pura: sin Firestore, sin reloj, sin efectos. La CF que la usa se encarga de
 * leer, escribir y transaccionar; aca solo vive la decision, que es la parte
 * que tiene reglas de negocio y bordes.
 *
 * QUE SIGNIFICA BLOQUEADO: el vinculo deja de contar para el limite del PF y
 * el PF pierde la capacidad de operar sobre ese alumno. **El alumno NO pierde
 * nada** — conserva rutinas, historial y chat. La presion va sobre quien paga,
 * no sobre quien no decide. Este modulo solo elige; el enforcement vive en
 * firestore.rules y llega despues.
 *
 * CRITERIO: se conservan los mas RECIENTES por `acceptedAt`. Es el mismo
 * default que ya muestra la pantalla keep-2, y el PF puede sobrescribirlo
 * eligiendo a mano. Un vinculo sin `acceptedAt` se trata como el mas viejo.
 */

export interface BlockableLink {
  id: string;
  athleteId: string;
  status: "pending" | "active" | "paused" | "terminated";
  entitlement?: "entitled" | "blocked";
  /** ms epoch. null/undefined ⇒ tratado como el mas viejo. */
  acceptedAtMs?: number | null;
}

export interface BlockSelection {
  /** ids de vinculos que pasan a `entitlement: 'blocked'`. */
  block: string[];
  /** carga ponderada que queda despues de bloquear. */
  keptLoad: number;
}

/** Mismos pesos que `weighted-load.ts` — si divergen, el gate y el downgrade
 * discrepan sobre quien entra. */
const STATUS_WEIGHT: Record<BlockableLink["status"], number> = {
  active: 1.0,
  paused: 0.5,
  pending: 0.0,
  terminated: 0.0,
};

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Elige a quien conservar (los mas recientes) hasta llenar `limit`, y devuelve
 * el resto para bloquear.
 *
 * Los ya `blocked` se ignoran por completo: no pesan y no se re-reportan, o
 * cada barrido generaria escrituras identicas para siempre.
 */
export function selectLinksToBlock(
  links: BlockableLink[],
  limit: number | null,
): BlockSelection {
  // 1. Solo los que pesan: activos y pausados, aun entitled.
  const candidates = links.filter(
    (l) =>
      l.entitlement !== "blocked" &&
      (l.status === "active" || l.status === "paused"),
  );

  // 2. Dedupe por atleta, quedandose con el vinculo mas pesado (mismo criterio
  //    que computeWeightedLoad). Sin esto, un alumno con un vinculo duplicado
  //    consumiria doble cupo y bloquearia a otra persona sin motivo.
  const byAthlete = new Map<string, BlockableLink>();
  for (const l of candidates) {
    const prev = byAthlete.get(l.athleteId);
    if (!prev || STATUS_WEIGHT[l.status] > STATUS_WEIGHT[prev.status]) {
      byAthlete.set(l.athleteId, l);
    }
  }

  // 3. Mas reciente primero. Desempate por id para que dos barridos con los
  //    mismos datos elijan siempre a las mismas personas — sin esto, quien se
  //    queda afuera dependeria del orden en que Firestore devolvio los docs.
  const ordered = [...byAthlete.values()].sort((a, b) => {
    const at = a.acceptedAtMs ?? Number.NEGATIVE_INFINITY;
    const bt = b.acceptedAtMs ?? Number.NEGATIVE_INFINITY;
    if (at !== bt) return bt - at;
    return a.id.localeCompare(b.id);
  });

  // 4. Greedy: se conserva mientras entre en el limite.
  const block: string[] = [];
  let keptLoad = 0;
  for (const l of ordered) {
    const w = STATUS_WEIGHT[l.status];
    // limit === null ⇒ plan3, sin tope: entra todo y no se bloquea a nadie.
    if (limit === null || round2(keptLoad + w) <= limit) {
      keptLoad = round2(keptLoad + w);
    } else {
      block.push(l.id);
    }
  }

  return { block, keptLoad: round2(keptLoad) };
}

export interface EntitlementReconciliation {
  /** ids que pasan a `blocked`. */
  block: string[];
  /** ids que vuelven a `entitled`. */
  unblock: string[];
  /** carga ponderada resultante. */
  keptLoad: number;
}

/**
 * Reconciliacion en DOS direcciones: que bloquear y que devolver.
 *
 * Bloquear solo no alcanza. Un PF que vuelve a pagar recupera cupo, y sin
 * devolucion queda roto para siempre — con alumnos bloqueados que ya no
 * tendrian por que estarlo.
 *
 * A diferencia de [selectLinksToBlock], los ya bloqueados SI son candidatos:
 * compiten por el cupo con todos los demas segun el mismo criterio (mas
 * reciente primero). Si el estado ya es correcto no devuelve nada, asi el
 * barrido diario no escribe todos los dias lo mismo.
 */
export function reconcileEntitlements(
  links: BlockableLink[],
  limit: number | null,
): EntitlementReconciliation {
  const candidates = links.filter(
    (l) => l.status === "active" || l.status === "paused",
  );

  const byAthlete = new Map<string, BlockableLink>();
  for (const l of candidates) {
    const prev = byAthlete.get(l.athleteId);
    if (!prev || STATUS_WEIGHT[l.status] > STATUS_WEIGHT[prev.status]) {
      byAthlete.set(l.athleteId, l);
    }
  }

  const ordered = [...byAthlete.values()].sort((a, b) => {
    const at = a.acceptedAtMs ?? Number.NEGATIVE_INFINITY;
    const bt = b.acceptedAtMs ?? Number.NEGATIVE_INFINITY;
    if (at !== bt) return bt - at;
    return a.id.localeCompare(b.id);
  });

  const kept = new Set<string>();
  let keptLoad = 0;
  for (const l of ordered) {
    const w = STATUS_WEIGHT[l.status];
    // limit === null ⇒ plan3, sin tope: todos quedan, y los que estaban
    // bloqueados de un plan anterior se devuelven.
    if (limit === null || round2(keptLoad + w) <= limit) {
      keptLoad = round2(keptLoad + w);
      kept.add(l.id);
    }
  }

  // Solo se reportan CAMBIOS: lo que ya esta en su estado correcto no genera
  // escritura. Sin esto, el barrido diario reescribiria los mismos campos
  // indefinidamente.
  const block: string[] = [];
  const unblock: string[] = [];
  for (const l of ordered) {
    const isBlocked = l.entitlement === "blocked";
    if (kept.has(l.id) && isBlocked) unblock.push(l.id);
    if (!kept.has(l.id) && !isBlocked) block.push(l.id);
  }

  return { block, unblock, keptLoad: round2(keptLoad) };
}
