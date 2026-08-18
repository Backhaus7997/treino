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
  limit: number,
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
    if (round2(keptLoad + w) <= limit) {
      keptLoad = round2(keptLoad + w);
    } else {
      block.push(l.id);
    }
  }

  return { block, keptLoad: round2(keptLoad) };
}
