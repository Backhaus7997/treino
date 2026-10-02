// ignore: unused_import — Timestamp is used by the generated
// trainer_subscription.g.dart part.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'subscription_tier.dart';

part 'trainer_subscription.freezed.dart';
part 'trainer_subscription.g.dart';

/// Suscripción del PF a TREINO (paywall Fase 7, PR1). Vive embebida en
/// `users/{uid}.subscription` — ver design paywall-profes-fase7 §1.1.
///
/// CF-write-only (firestore.rules pin, §5.1): el cliente nunca escribe este
/// mapa. Un `UserProfile` sin `subscription` (campo ausente) es un PF Free
/// sin necesidad de backfill — [effectiveWeightLimit] en
/// `functions/src/subscriptions/effective-limit.ts` resuelve `null` → 2.
@freezed
class TrainerSubscription with _$TrainerSubscription {
  const factory TrainerSubscription({
    required SubscriptionTier tier,
    required SubscriptionStatus status,
    SubscriptionCycle? cycle,
    // Tope de carga ponderada que el servidor NO escribe, ni escribió nunca:
    // `git log -S weightLimit -- functions scripts` sólo trae fixtures de
    // tests de reglas. La única escritura de este mapa, en
    // functions/src/subscriptions/mp/reconcile.ts, no lo incluye. El cliente
    // no puede escribirlo (las rules pinnean el mapa entero) y ninguna regla
    // lo lee. Ningún código de este repo lo pone en un doc.
    //
    // Por eso acá `null` es «no está», no «sin límite». El sin límite del
    // Plan 3 vive en la tabla del tier (`SubscriptionTier.weightLimit`, de
    // `kTierWeightLimits`), espejo de `TIER_WEIGHT_LIMITS`
    // (functions/src/subscriptions/tier-config.ts), con la que el servidor
    // calcula el tope. Si leés este campo, caé a `tier.weightLimit`, nunca a
    // una constante: con `?? 2` el Plan 3 se quedaría con el cupo del Free.
    int? weightLimit,
    @TimestampConverter() DateTime? currentPeriodEnd,
    @TimestampConverter() DateTime? graceUntil,
    String? mpPreapprovalId,
    @TimestampConverter() DateTime? updatedByWebhookAt,
    String? lastMpEventId,
  }) = _TrainerSubscription;

  factory TrainerSubscription.fromJson(Map<String, Object?> json) =>
      _$TrainerSubscriptionFromJson(json);
}
