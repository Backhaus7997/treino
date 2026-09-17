/**
 * athlete-plan-config.ts — el precio del plan del ALUMNO, server-authoritative.
 *
 * El alumno suelto tiene UN plan con dos ciclos, no una escalera de tiers: lo
 * que el pago le destraba es la FORMA de la rutina que se arma (dias, semanas,
 * catalogo), no una capacidad que crezca. Ver `docs/paywall-alumno-suelto.md`.
 *
 * ── Por que un archivo propio y no `tier-config.ts` ──
 *
 * Porque `tier-config.ts` esta tipado sobre `SubscriptionTier`, que son los
 * cuatro tiers del PF. Sumarle un miembro `athlete` se propaga a
 * `TIER_WEIGHT_LIMITS`, al switch exhaustivo de `effectiveWeightLimit` —que
 * rompe el build a proposito cuando la union crece—, a `PAID_TIERS`, a
 * `amountFor`, y al enum `@JsonValue` de `subscription_tier.dart`. Radio de
 * explosion desproporcionado para un producto que no tiene tiers.
 *
 * Lo que SI se comparte con el PF es el indice inverso monto → plan de
 * `mp/tier-mapping.ts`. Ver [ATHLETE_PRICES_ARS].
 */

import type { SubscriptionCycle } from "./tier-config";

/**
 * Precio mensual del plan del alumno, en ARS y con impuestos incluidos.
 *
 * **Decidido por Martin el 2026-09-17: el TECHO de la banda de mercado.**
 *
 * ── Contra que se fijo, y contra que NO ──
 *
 * Contra las referencias argentinas de `docs/paywall-alumno-suelto.md` §8.1,
 * verificadas el 2026-09-03: Spotify Individual ARS 4.499 + impuestos, SMVM
 * ARS 383.800, y un plan online de PF argentino ARS 20.000–40.000. A 3.500 el
 * plan es el **0,9% del SMVM** y entre el **9% y el 17%** de lo que cobra un
 * PF. Ese ultimo numero es el que importa: el paywall no compite con el PF,
 * esta un orden de magnitud abajo.
 *
 * NO se fijo contra lo que se iba a facturar por IAP, y la diferencia es
 * material — conviene tenerla escrita porque el numero se ve arbitrario sin
 * ella. §8 proponia USD 2,99, de los que a TREINO le llegaban ~ARS 3.833 por
 * alumno-mes; de estos 3.500 entran ~3.272 (comision de MP 6,53% al instante)
 * o ~3.377 (3,52% a 18 dias). O sea que se resigna un ~15% de ingreso por
 * alumno — y el alumno pasa de pagar ARS 6.931 a pagar 3.500, la mitad.
 *
 * El punto de empate con el IAP estaba en ~ARS 4.100. Se eligio no ir ahi: a
 * ese precio el plan queda 17% arriba del techo de la banda y al 91% de un
 * Spotify, y el argumento de que es barato se debilita. La diferencia la paga
 * el margen a proposito, no por descuido.
 *
 * ⚠️ Si alguna vez se revisa hacia arriba, **4.100 es el numero que empata**.
 *
 * ── Como se cambia ──
 *
 * Esta linea, y nada mas: el anual se deriva, y el espejo de Dart lo pinea un
 * test de paridad.
 *
 * ── ⚠️ La restriccion que no es obvia ──
 *
 * Ni este monto ni su anual pueden IGUALAR ninguno de los seis precios del PF
 * (`TIER_PRICES_ARS`: 12.000/120.000, 22.000/220.000, 39.000/390.000). El
 * fallback por monto de `mp/tier-mapping.ts` identifica el plan por lo que se
 * cobro, asi que dos planes con el mismo monto hacen que a alguien se le
 * acredite un plan que no compro.
 *
 * No hay que recordarlo: el indice `BY_AMOUNT` tira al importar el modulo si
 * detecta la colision, y el deploy no arranca. Pero conviene saber por que
 * rompe. Valores prohibidos hoy: **2.200** (su anual seria 22.000, el mensual
 * del Plan 2) y **12.000**.
 */
export const ATHLETE_PRICE_MONTHLY_ARS = 3500;

/**
 * Precio del plan del alumno, en ARS y con impuestos incluidos.
 *
 * El anual se DERIVA del mensual y no se escribe a mano. Es la convencion de
 * la casa —`tier-config.ts` la documenta: `monthly × 10`, dos meses gratis,
 * ~17% off— pero ahi los seis numeros estan escritos uno por uno y hay que
 * mantenerlos sincronizados de memoria. Con un solo producto no hay ninguna
 * razon para repetir ese error.
 */
export const ATHLETE_PRICES_ARS: Record<SubscriptionCycle, number> = {
  monthly: ATHLETE_PRICE_MONTHLY_ARS,
  annual: ATHLETE_PRICE_MONTHLY_ARS * 10,
};

/**
 * El monto en ARS que le corresponde a este ciclo. SERVER-AUTHORITATIVE: es la
 * unica fuente del precio del alumno, y nunca se acepta un monto que venga del
 * cliente.
 *
 * Espeja `amountFor` de `tier-mapping.ts`, que hace lo mismo para el PF.
 */
export function athleteAmountFor(cycle: SubscriptionCycle): number {
  return ATHLETE_PRICES_ARS[cycle];
}
