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
    // Límite de peso ponderado cacheado (denormalizado) — el CF lo escribe
    // junto con `tier` para que UI/rules lean sin lookup. Nunca confiar en
    // un valor client-provisto (rules lo pinnea CF-write-only).
    required int weightLimit,
    @TimestampConverter() DateTime? currentPeriodEnd,
    @TimestampConverter() DateTime? graceUntil,
    String? mpPreapprovalId,
    @TimestampConverter() DateTime? updatedByWebhookAt,
    String? lastMpEventId,
  }) = _TrainerSubscription;

  factory TrainerSubscription.fromJson(Map<String, Object?> json) =>
      _$TrainerSubscriptionFromJson(json);
}
