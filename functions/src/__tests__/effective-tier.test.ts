/**
 * Unit tests for `effectiveTier` (limite-ejercicios-pf.md, PR1). No infra.
 *
 * Separado de `effective-limit.test.ts` a proposito, aunque las dos funciones
 * viven en el mismo modulo: `effectiveTier` es una REPLICA independiente de
 * `effectiveWeightLimit`, no una que la llama, y este archivo es justo el que
 * prueba que las dos siguen de acuerdo — mezclarlo en el archivo que ya
 * prueba `effectiveWeightLimit` haria mas dificil ver cual test cubre cual
 * funcion.
 */

import {
  effectiveTier,
  effectiveWeightLimit,
  SubscriptionState,
  SubscriptionStatus,
  SUBSCRIPTION_STATUSES,
  tierLimit,
} from "../subscriptions/effective-limit";
import { TIER_CUSTOM_EXERCISE_LIMITS } from "../subscriptions/tier-config";

/** El tope de ejercicios propios que corresponde a un tier. Oraculo local. */
function customExerciseTierLimit(tier: keyof typeof TIER_CUSTOM_EXERCISE_LIMITS) {
  return TIER_CUSTOM_EXERCISE_LIMITS[tier];
}

const sub = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs?: number | null,
): SubscriptionState => ({ tier, status, currentPeriodEndMs });

const NOW = 1_000_000;

describe("effectiveTier", () => {
  it("sin suscripcion (null/undefined) → free", () => {
    expect(effectiveTier(null, NOW)).toBe("free");
    expect(effectiveTier(undefined, NOW)).toBe("free");
  });

  it("active/grace → el tier pago", () => {
    expect(effectiveTier(sub("plan1", "active"), NOW)).toBe("plan1");
    expect(effectiveTier(sub("plan2", "grace"), NOW)).toBe("plan2");
    expect(effectiveTier(sub("plan3", "active"), NOW)).toBe("plan3");
  });

  it("pending/paused → free", () => {
    expect(effectiveTier(sub("plan2", "pending"), NOW)).toBe("free");
    expect(effectiveTier(sub("plan3", "paused"), NOW)).toBe("free");
  });

  it("cancelled antes de currentPeriodEnd → sigue en el tier pago", () => {
    expect(effectiveTier(sub("plan2", "cancelled", NOW + 1000), NOW)).toBe(
      "plan2",
    );
  });

  it("cancelled despues de currentPeriodEnd → free", () => {
    expect(effectiveTier(sub("plan2", "cancelled", NOW - 1000), NOW)).toBe(
      "free",
    );
  });

  it("cancelled con currentPeriodEnd null → free", () => {
    expect(effectiveTier(sub("plan2", "cancelled", null), NOW)).toBe("free");
  });

  it("tier desconocido con status valido → free", () => {
    const forged = { tier: "plan22", status: "active" } as unknown as SubscriptionState;
    expect(effectiveTier(forged, NOW)).toBe("free");
  });

  it("mapa ausente por completo → free (mismo caso que null)", () => {
    expect(effectiveTier(undefined, NOW)).toBe("free");
  });

  it("status con typo ('canceled') → free, nunca undefined", () => {
    const forged = {
      tier: "plan2",
      status: "canceled",
    } as unknown as SubscriptionState;
    expect(effectiveTier(forged, NOW)).toBe("free");
  });

  describe("exhaustividad — cada status de la union tiene una respuesta DECIDIDA", () => {
    const PLAN3_POR_STATUS: Record<SubscriptionStatus, string> = {
      active: "plan3",
      grace: "plan3",
      cancelled: "free", // sin currentPeriodEnd = ya vencido
      pending: "free",
      paused: "free",
    };

    it.each(SUBSCRIPTION_STATUSES)("plan3 + %s", (status) => {
      expect(effectiveTier({ tier: "plan3", status }, NOW)).toBe(
        PLAN3_POR_STATUS[status],
      );
    });
  });

  describe("el piso prepago — por RANGO DE TIER, no por limite", () => {
    const conPiso = (
      tier: SubscriptionState["tier"],
      status: SubscriptionState["status"],
      piso: { tier: SubscriptionState["tier"]; untilMs: number } | null,
      currentPeriodEndMs: number | null = null,
    ): SubscriptionState => ({
      tier,
      status,
      currentPeriodEndMs,
      prepaidTier: piso === null ? null : piso.tier,
      prepaidUntilMs: piso === null ? null : piso.untilMs,
    });

    it("un piso plan3 sobre un plan1 activo da plan3, no plan1", () => {
      expect(
        effectiveTier(
          conPiso("plan1", "active", { tier: "plan3", untilMs: NOW + 1 }),
          NOW,
        ),
      ).toBe("plan3");
    });

    it("un piso VENCIDO no aporta nada", () => {
      expect(
        effectiveTier(
          conPiso("plan1", "active", { tier: "plan3", untilMs: NOW }),
          NOW,
        ),
      ).toBe("plan1");
    });

    it("un piso MENOR que el plan vigente no baja nada — es piso, no techo", () => {
      expect(
        effectiveTier(
          conPiso("plan2", "active", { tier: "plan1", untilMs: NOW + 1 }),
          NOW,
        ),
      ).toBe("plan2");
    });

    it("el piso NO pasa por el switch de status: un `pending` igual lo conserva", () => {
      expect(
        effectiveTier(
          conPiso("plan1", "pending", { tier: "plan2", untilMs: NOW + 1 }),
          NOW,
        ),
      ).toBe("plan2");
    });
  });
});

/**
 * LA CONSISTENCIA, con el tope de alumnos como ORACULO — decision explicita
 * del plan (limite-ejercicios-pf.md, PR1): `effectiveTier` no comparte codigo
 * con `effectiveWeightLimit`, asi que lo unico que garantiza que las dos
 * sigan de acuerdo es este test corriendo sobre TODA la matriz.
 *
 * Para cada caso: `tierLimit(effectiveTier(s)) === effectiveWeightLimit(s)`.
 */
describe("consistencia effectiveTier / effectiveWeightLimit", () => {
  const casos: [string, SubscriptionState | null | undefined][] = [
    ["sin suscripcion", null],
    ["undefined", undefined],
  ];
  for (const tier of ["free", "plan1", "plan2", "plan3"] as const) {
    for (const status of SUBSCRIPTION_STATUSES) {
      casos.push([`${tier} ${status}`, { tier, status, currentPeriodEndMs: null }]);
      casos.push([
        `${tier} ${status} (periodo vigente)`,
        { tier, status, currentPeriodEndMs: NOW + 10_000 },
      ]);
      casos.push([
        `${tier} ${status} (periodo vencido)`,
        { tier, status, currentPeriodEndMs: NOW - 10_000 },
      ]);
    }
  }

  it.each(casos)("%s", (_label, s) => {
    expect(tierLimit(effectiveTier(s, NOW))).toBe(effectiveWeightLimit(s, NOW));
  });

  it("tambien vale para el tope de EJERCICIOS PROPIOS con el piso prepago activo", () => {
    const s: SubscriptionState = {
      tier: "plan1",
      status: "active",
      currentPeriodEndMs: null,
      prepaidTier: "plan3",
      prepaidUntilMs: NOW + 1000,
    };
    expect(effectiveTier(s, NOW)).toBe("plan3");
    expect(customExerciseTierLimit(effectiveTier(s, NOW))).toBeNull();
  });
});
