import 'package:json_annotation/json_annotation.dart';

/// Tier de suscripción del PF a TREINO (monetización Fase 7, PR1).
///
/// El PF paga a TREINO por usar la plataforma según cuántos "alumnos activos"
/// tiene, medidos por PESO PONDERADO (ver [kTierWeightLimits] y
/// `functions/src/subscriptions/weighted-load.ts`): un alumno activo pesa 1.0
/// y uno pausado 0.5 hacia el límite del tier.
///
/// Fase 1 = solo estos 3 tiers FLAT. El tier usage-based (16+ alumnos,
/// $1/alumno) es Fase 2 y NO está acá.
enum SubscriptionTier {
  @JsonValue('free')
  free,
  @JsonValue('plan1')
  plan1,
  @JsonValue('plan2')
  plan2,
}

/// Límite de peso ponderado por tier. Es la fuente de verdad client-side;
/// DEBE mantenerse en sync con `TIER_WEIGHT_LIMITS` en
/// `functions/src/subscriptions/tier-config.ts` (el servidor es la autoridad
/// real — este mapa es para mostrar "N/límite" en la UI sin un round-trip).
///
/// Free 2 · Plan 1 7 · Plan 2 15.
const Map<SubscriptionTier, int> kTierWeightLimits = {
  SubscriptionTier.free: 2,
  SubscriptionTier.plan1: 7,
  SubscriptionTier.plan2: 15,
};

/// Precios en ARS por tier pago y ciclo. Fuente de verdad para la UI del
/// paywall (pricing page, cards de plan). DEBE mantenerse en sync con
/// `TIER_PRICES_ARS` en `functions/src/subscriptions/tier-config.ts` — el
/// servidor es la autoridad al crear la preapproval; este mapa es solo para
/// mostrar los montos sin un round-trip.
///
/// Free no tiene precio (nunca se cobra). Anual = mensual × 10 (2 meses
/// gratis, ~17% off). Definidos con estudio de mercado AR.
///   Plan 1: $12.000/mes · $120.000/año
///   Plan 2: $22.000/mes · $220.000/año
const Map<SubscriptionTier, ({int monthly, int annual})> kTierPricesArs = {
  SubscriptionTier.plan1: (monthly: 12000, annual: 120000),
  SubscriptionTier.plan2: (monthly: 22000, annual: 220000),
};

/// Estado de la suscripción del PF.
///
/// - `active`  — pago al día, con derecho al límite del tier.
/// - `pending` — preapproval creado en MP, checkout aún sin confirmar. El
///   límite efectivo NO sube hasta que el webhook confirme (en el launch,
///   cae a Free=2).
/// - `grace`   — falló un cobro recurrente; ventana de 7 días donde MP
///   reintenta. El derecho SIGUE en el tier pago durante la gracia (no se
///   castiga al primer fallo).
/// - `paused`  — el PF pausó la suscripción en MP. Derecho cae a Free=2.
/// - `cancelled` — cancelada; el derecho cae a Free al llegar
///   `currentPeriodEnd`.
enum SubscriptionStatus {
  @JsonValue('active')
  active,
  @JsonValue('pending')
  pending,
  @JsonValue('grace')
  grace,
  @JsonValue('paused')
  paused,
  @JsonValue('cancelled')
  cancelled,
}

/// Ciclo de cobro. `annual` con descuento; `null` mientras el PF está en Free.
enum SubscriptionCycle {
  @JsonValue('monthly')
  monthly,
  @JsonValue('annual')
  annual,
}

extension SubscriptionTierX on SubscriptionTier {
  String toJson() => switch (this) {
        SubscriptionTier.free => 'free',
        SubscriptionTier.plan1 => 'plan1',
        SubscriptionTier.plan2 => 'plan2',
      };

  /// Límite de peso ponderado de este tier.
  int get weightLimit => kTierWeightLimits[this]!;

  static SubscriptionTier fromJson(String? value) => switch (value) {
        'free' => SubscriptionTier.free,
        'plan1' => SubscriptionTier.plan1,
        'plan2' => SubscriptionTier.plan2,
        // Default defensivo: un doc sin/con-tier-desconocido decodifica como
        // Free (sin backfill — un PF sin suscripción es Free por definición).
        _ => SubscriptionTier.free,
      };
}

extension SubscriptionStatusX on SubscriptionStatus {
  String toJson() => switch (this) {
        SubscriptionStatus.active => 'active',
        SubscriptionStatus.pending => 'pending',
        SubscriptionStatus.grace => 'grace',
        SubscriptionStatus.paused => 'paused',
        SubscriptionStatus.cancelled => 'cancelled',
      };

  static SubscriptionStatus fromJson(String? value) => switch (value) {
        'active' => SubscriptionStatus.active,
        'pending' => SubscriptionStatus.pending,
        'grace' => SubscriptionStatus.grace,
        'paused' => SubscriptionStatus.paused,
        'cancelled' => SubscriptionStatus.cancelled,
        // Un doc sin status conocido → active (el default de un PF sin
        // suscripción es Free/active/límite-2, resuelto en effectiveWeightLimit).
        _ => SubscriptionStatus.active,
      };
}

extension SubscriptionCycleX on SubscriptionCycle {
  String toJson() => switch (this) {
        SubscriptionCycle.monthly => 'monthly',
        SubscriptionCycle.annual => 'annual',
      };

  static SubscriptionCycle? fromJson(String? value) => switch (value) {
        'monthly' => SubscriptionCycle.monthly,
        'annual' => SubscriptionCycle.annual,
        _ => null, // null mientras el PF está en Free (sin ciclo).
      };
}
