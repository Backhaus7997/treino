/**
 * trainer-pricing.test.ts — el contrato de `getTrainerPricing`, la lectura
 * publica del precio y los topes de los planes del entrenador. LOCAL — sin
 * emulador: el handler no lee Firestore, deriva todo de `tier-config.ts`.
 */

import {
  TIER_CUSTOM_EXERCISE_LIMITS,
  TIER_PRICES_ARS,
  TIER_TEMPLATE_LIMITS,
  TIER_WEIGHT_LIMITS,
} from "../subscriptions/tier-config";
import {
  buildTrainerPricing,
  getTrainerPricing,
} from "../subscriptions/trainer-pricing";

describe("buildTrainerPricing", () => {
  const pricing = buildTrainerPricing();

  it("va en pesos y ordena free -> plan3", () => {
    expect(pricing.currency).toBe("ARS");
    expect(pricing.plans.map((p) => p.tier)).toEqual([
      "free",
      "plan1",
      "plan2",
      "plan3",
    ]);
  });

  it("free no tiene precio: null, nunca 0", () => {
    const free = pricing.plans[0];
    expect(free.monthly).toBeNull();
    expect(free.annual).toBeNull();
  });

  it("los precios de los planes pagos SON TIER_PRICES_ARS", () => {
    for (const plan of pricing.plans.filter((p) => p.tier !== "free")) {
      const tier = plan.tier as keyof typeof TIER_PRICES_ARS;
      expect(plan.monthly).toBe(TIER_PRICES_ARS[tier].monthly);
      expect(plan.annual).toBe(TIER_PRICES_ARS[tier].annual);
    }
  });

  it("los topes SON los de tier-config, y null es sin tope", () => {
    for (const plan of pricing.plans) {
      expect(plan.limits).toEqual({
        athletes: TIER_WEIGHT_LIMITS[plan.tier],
        exercises: TIER_CUSTOM_EXERCISE_LIMITS[plan.tier],
        templates: TIER_TEMPLATE_LIMITS[plan.tier],
      });
    }
    const plan3 = pricing.plans[3];
    expect(plan3.limits.athletes).toBeNull();
    expect(plan3.limits.exercises).toBeNull();
    expect(plan3.limits.templates).toBeNull();
  });

  it("annualFreeMonths se deriva de monthly x 12 vs annual", () => {
    expect(pricing.annualFreeMonths).toBe(2);
  });

  it("sobrevive a JSON.stringify sin perder ningun tope", () => {
    const roundTrip = JSON.parse(JSON.stringify(pricing));
    expect(roundTrip).toEqual(pricing);
    expect(roundTrip.plans[3].limits.athletes).toBeNull();
  });

  it("available es true cuando todo plan pago tiene precio", () => {
    expect(pricing.available).toBe(true);
  });
});

describe("getTrainerPricing (callable)", () => {
  it("responde sin auth y sin body", async () => {
    const res = await (getTrainerPricing as unknown as { run: (r: unknown) => Promise<unknown> }).run({
      data: undefined,
      auth: undefined,
      rawRequest: {},
    });
    expect(res).toEqual(buildTrainerPricing());
  });
});

describe("available: no anuncia lo que no se puede cobrar", () => {
  it("es false y sin annualFreeMonths si un plan pago quedo sin precio valido", () => {
    jest.isolateModules(() => {
      jest.doMock("../subscriptions/tier-config", () => {
        const real = jest.requireActual("../subscriptions/tier-config");
        return {
          ...real,
          TIER_PRICES_ARS: {
            ...real.TIER_PRICES_ARS,
            plan2: { monthly: 0, annual: 0 },
          },
        };
      });
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const mod = require("../subscriptions/trainer-pricing");
      const res = mod.buildTrainerPricing();
      expect(res.available).toBe(false);
      expect(res.annualFreeMonths).toBeUndefined();
    });
  });
});
