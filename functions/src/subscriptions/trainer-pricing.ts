/**
 * trainer-pricing.ts — `getTrainerPricing`: el precio y los topes de los planes
 * del entrenador, para que la landing los muestre.
 *
 * Gemelo de `getAthletePricing` (`mp/create-athlete-preapproval.ts`) y por el
 * mismo motivo: la landing vive en otro repo y un precio escrito a mano ahi se
 * desincroniza de `TIER_PRICES_ARS`; el modo de falla es mostrar un precio y
 * cobrar otro, que en Argentina es publicidad enganosa. Se pregunta al servidor.
 *
 * ── Mismo contrato que `getAthletePricing` ──
 *
 * Region `southamerica-east1`, SIN auth, SIN App Check (la landing no tiene
 * Firebase), sin body, y no lee ni escribe Firestore: todo sale de constantes de
 * `tier-config.ts`. Ningun literal de plata o de tope vive en este archivo.
 *
 * ── Sobre `available` ──
 *
 * `getAthletePricing` no mira ningun interruptor, y el lado del entrenador no
 * tiene uno equivalente: `createPreapproval` no esta gateado por flag (no hay
 * `TRAINER_PAYWALL_*`; los interruptores `TRAINER_*_LIMITS_ENABLED` de
 * `trainer-plan-limits.ts` solo prenden los TOPES, no la venta). Por eso
 * `available` no es un flag: es "todo plan pago tiene un precio valido en
 * `TIER_PRICES_ARS`". Si manana alguien agrega un plan sin precio, o rompe uno,
 * la landing deja de anunciar en vez de publicar un plan que no se puede
 * cobrar. Si algun dia aparece un interruptor de venta, se compone aca.
 *
 * `athletes` es el tope de CARGA PONDERADA (activo = 1, pausado = 0,5), o sea
 * `TIER_WEIGHT_LIMITS`; `null` = sin tope en los tres topes.
 */

import * as functions from "firebase-functions/v2/https";

import {
  SubscriptionTier,
  TIER_CUSTOM_EXERCISE_LIMITS,
  TIER_LABELS,
  TIER_PRICES_ARS,
  TIER_TEMPLATE_LIMITS,
  TIER_WEIGHT_LIMITS,
} from "./tier-config";

const MONTHS_PER_YEAR = 12;

export interface TrainerPlanPricing {
  tier: SubscriptionTier;
  monthly: number | null;
  annual: number | null;
  limits: {
    athletes: number | null;
    exercises: number | null;
    templates: number | null;
  };
}

export interface TrainerPricing {
  currency: "ARS";
  available: boolean;
  /** Meses gratis del anual vs. 12 mensuales; ausente si los planes no coinciden. */
  annualFreeMonths?: number;
  plans: TrainerPlanPricing[];
}

/** free -> plan3: el orden en que `TIER_LABELS` declara la escalera. */
const TIERS = Object.keys(TIER_LABELS) as SubscriptionTier[];

function isPaid(tier: SubscriptionTier): tier is Exclude<SubscriptionTier, "free"> {
  return Object.prototype.hasOwnProperty.call(TIER_PRICES_ARS, tier);
}

export function buildTrainerPricing(): TrainerPricing {
  const plans: TrainerPlanPricing[] = TIERS.map((tier) => ({
    tier,
    monthly: isPaid(tier) ? TIER_PRICES_ARS[tier].monthly : null,
    annual: isPaid(tier) ? TIER_PRICES_ARS[tier].annual : null,
    limits: {
      athletes: TIER_WEIGHT_LIMITS[tier],
      exercises: TIER_CUSTOM_EXERCISE_LIMITS[tier],
      templates: TIER_TEMPLATE_LIMITS[tier],
    },
  }));

  const paid = plans.filter((p) => isPaid(p.tier));
  const validPrice = (n: number | null) =>
    typeof n === "number" && Number.isFinite(n) && n > 0;
  const available =
    paid.length > 0 && paid.every((p) => validPrice(p.monthly) && validPrice(p.annual));

  const freeMonths = new Set(
    paid.map((p) => MONTHS_PER_YEAR - (p.annual as number) / (p.monthly as number)),
  );
  const [only] = [...freeMonths];

  const result: TrainerPricing = { currency: "ARS", available, plans };
  if (available && freeMonths.size === 1 && Number.isInteger(only) && only > 0) {
    result.annualFreeMonths = only;
  }
  return result;
}

/** Lectura publica: ver el encabezado y el comentario de `index.ts`. */
export const getTrainerPricing = functions.onCall(
  { region: "southamerica-east1" },
  async () => buildTrainerPricing(),
);
