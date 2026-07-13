/**
 * weighted-load.ts — fractional weighted-load computation for the paywall
 * (Fase 7, PR1). Pure functions, no Firestore — fully unit-testable.
 *
 * ## Fractional weight model (business decision #220)
 * A trainer's "load" toward their tier limit is a WEIGHTED sum, not a count:
 *   - active     student → 1.0
 *   - paused     student → 0.5   (still costs half; closes pause-to-dodge)
 *   - terminated student → 0.0
 *   - blocked-by-nonpayment link → 0.0 (parked excess — NEVER counts, or
 *     reactivation would be impossible: permanently over limit — ADR-5)
 *
 * The limit check blocks when a new student would push the weighted sum OVER
 * the integer tier limit. Any fraction over the limit blocks (7.5 > 7).
 */

/** A trainer_link, reduced to the fields the weighted-load math needs. */
export interface WeightedLink {
  athleteId: string;
  status: "pending" | "active" | "paused" | "terminated";
  /** entitlement overlay (paywall). Absent ⇒ 'entitled' (no backfill). */
  entitlement?: "entitled" | "blocked";
}

const STATUS_WEIGHT: Record<WeightedLink["status"], number> = {
  active: 1.0,
  paused: 0.5,
  pending: 0.0, // a pending request isn't following yet
  terminated: 0.0,
};

/**
 * Rounds to the nearest 0.5 to guard against IEEE-754 accumulation drift when
 * summing many halves. Weights are exact halves, so this never changes a
 * legitimate value — it only cleans float noise on large sets.
 */
export function round2(n: number): number {
  return Math.round(n * 2) / 2;
}

/**
 * Deduplicates links by athleteId, keeping the "heaviest" status per athlete
 * (a pair can have historical terminated + a live active link — count the
 * live one only). Mirrors facturacion_tab.dart's dedup-by-athleteId display.
 */
function dedupeByAthlete(links: WeightedLink[]): WeightedLink[] {
  const best = new Map<string, WeightedLink>();
  for (const link of links) {
    const cur = best.get(link.athleteId);
    if (!cur || STATUS_WEIGHT[link.status] > STATUS_WEIGHT[cur.status]) {
      best.set(link.athleteId, link);
    }
  }
  return [...best.values()];
}

/**
 * Weighted load of a trainer's links. Blocked links are excluded (parked
 * excess). Deduped by athlete. Returns a float, e.g. 6.0, 7.5.
 */
export function computeWeightedLoad(links: WeightedLink[]): number {
  let sum = 0;
  for (const link of dedupeByAthlete(links)) {
    if (link.entitlement === "blocked") continue; // parked — never counts
    sum += STATUS_WEIGHT[link.status];
  }
  return round2(sum);
}

/**
 * Whether accepting an incoming student (default weight 1.0 — a new active
 * follow) keeps the trainer at or under the tier limit.
 *
 * Strict `<=`: at-limit is allowed, any fraction over blocks.
 *   - 6 active + 2 paused = 7.0 at plan1(7) → adding an active = 8.0 > 7 → block
 *   - 6 active + 1 paused = 6.5 → adding an active = 7.5 > 7 → block
 */
export function canAccept(
  currentLoad: number,
  incomingWeight: number,
  limit: number,
): boolean {
  return round2(currentLoad + incomingWeight) <= limit;
}
