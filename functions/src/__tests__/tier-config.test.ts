/**
 * Unit tests for the tier price/limit config (paywall). Guards the pricing
 * invariants so a future edit can't silently break the "2 months free" promise
 * or drift the client/server limits apart.
 */

import {
  SubscriptionCycle,
  SubscriptionTier,
  TIER_CUSTOM_EXERCISE_LIMITS,
  TIER_PRICES_ARS,
  TIER_WEIGHT_LIMITS,
} from "../subscriptions/tier-config";
import { limitRank } from "../subscriptions/effective-limit";

describe("TIER_WEIGHT_LIMITS", () => {
  it("free=2, plan1=7, plan2=15, plan3=sin limite", () => {
    // plan3: null = ILIMITADO, no "falta el dato". La distincion importa: un
    // `?? FREE_LIMIT` en el resolvedor convertia ese null en 2, y el plan mas
    // caro daba MENOS alumnos que el mas barato — compilando perfecto.
    expect(TIER_WEIGHT_LIMITS).toEqual({
      free: 2,
      plan1: 7,
      plan2: 15,
      plan3: null,
    });
  });
});

/**
 * limite-ejercicios-pf.md, PR1. La escalera tiene que ser monotona Y seguir
 * el MISMO orden que `TIER_WEIGHT_LIMITS`: `effectiveTier` (effective-limit.ts)
 * rankea TIERS reusando `tierLimit`+`limitRank` de la escalera de PESO, y eso
 * solo es correcto si las dos escaleras avanzan juntas — si algun dia
 * divergieran (p.ej. plan2 con mas alumnos pero MENOS ejercicios que plan1),
 * el piso prepago de ejercicios quedaria calculado con el orden EQUIVOCADO.
 */
describe("TIER_CUSTOM_EXERCISE_LIMITS", () => {
  const ORDEN: SubscriptionTier[] = ["free", "plan1", "plan2", "plan3"];

  it("free=20, plan1=60, plan2=120, plan3=sin limite", () => {
    expect(TIER_CUSTOM_EXERCISE_LIMITS).toEqual({
      free: 20,
      plan1: 60,
      plan2: 120,
      plan3: null,
    });
  });

  it("la escalera es monotona: 20 < 60 < 120 < sin tope", () => {
    for (let i = 1; i < ORDEN.length; i++) {
      const anterior = limitRank(TIER_CUSTOM_EXERCISE_LIMITS[ORDEN[i - 1]]);
      const actual = limitRank(TIER_CUSTOM_EXERCISE_LIMITS[ORDEN[i]]);
      expect(actual).toBeGreaterThan(anterior);
    }
  });

  it("sigue el MISMO orden que TIER_WEIGHT_LIMITS — el piso prepago necesita que crezcan juntas", () => {
    // Si algun tier de ejercicios rankeara distinto que el mismo tier de
    // peso, `effectiveTier` (que rankea por la escalera de PESO) elegiria un
    // piso equivocado para ejercicios. Esto lo cierra comparando, para cada
    // PAR de tiers consecutivos, que las dos escaleras esten de acuerdo sobre
    // cual es mayor.
    for (let i = 1; i < ORDEN.length; i++) {
      const pesoAnterior = limitRank(TIER_WEIGHT_LIMITS[ORDEN[i - 1]]);
      const pesoActual = limitRank(TIER_WEIGHT_LIMITS[ORDEN[i]]);
      const ejerciciosAnterior = limitRank(TIER_CUSTOM_EXERCISE_LIMITS[ORDEN[i - 1]]);
      const ejerciciosActual = limitRank(TIER_CUSTOM_EXERCISE_LIMITS[ORDEN[i]]);
      expect(pesoActual > pesoAnterior).toBe(ejerciciosActual > ejerciciosAnterior);
    }
  });
});

describe("TIER_PRICES_ARS", () => {
  it("Plan 1 = $12.000/mes, $120.000/año", () => {
    expect(TIER_PRICES_ARS.plan1).toEqual({ monthly: 12000, annual: 120000 });
  });

  it("Plan 2 = $22.000/mes, $220.000/año", () => {
    expect(TIER_PRICES_ARS.plan2).toEqual({ monthly: 22000, annual: 220000 });
  });

  it("annual = monthly × 10 (2 months free) for every paid tier", () => {
    for (const tier of ["plan1", "plan2"] as const) {
      const p = TIER_PRICES_ARS[tier];
      expect(p.annual).toBe(p.monthly * 10);
    }
  });

  it("every paid tier has a positive price for every cycle", () => {
    const cycles: SubscriptionCycle[] = ["monthly", "annual"];
    for (const tier of ["plan1", "plan2"] as const) {
      for (const cycle of cycles) {
        expect(TIER_PRICES_ARS[tier][cycle]).toBeGreaterThan(0);
      }
    }
  });
});
