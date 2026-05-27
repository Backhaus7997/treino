import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'commercial_plan.freezed.dart';
part 'commercial_plan.g.dart';

/// How often the trainer charges the athlete for this plan.
enum BillingFrequency {
  @JsonValue('monthly')
  monthly,
  @JsonValue('quarterly')
  quarterly,
  @JsonValue('yearly')
  yearly,
  @JsonValue('one_time')
  oneTime,
}

extension BillingFrequencyX on BillingFrequency {
  /// Display label in Rioplatense Spanish (ADR-4).
  String get label => switch (this) {
        BillingFrequency.monthly => 'Mensual',
        BillingFrequency.quarterly => 'Trimestral',
        BillingFrequency.yearly => 'Anual',
        BillingFrequency.oneTime => 'Pago único',
      };
}

/// Lifecycle status of a commercial plan.
///
/// `active` plans are visible to the trainer's UI; `archived` are hidden
/// from default lists but the docs remain for historical reference
/// (subscriptions that were created against them, etc.).
enum CommercialPlanStatus {
  @JsonValue('active')
  active,
  @JsonValue('archived')
  archived,
}

/// Features included in a commercial plan. Trainer ticks which features
/// the athlete gets for the price.
///
/// Stored as a list of wire strings in Firestore so we can add new options
/// later without a migration.
enum PlanInclude {
  @JsonValue('routines')
  routines,
  @JsonValue('nutrition')
  nutrition,
  @JsonValue('chat')
  chat,
  @JsonValue('presential_sessions')
  presentialSessions,
  @JsonValue('online_sessions')
  onlineSessions,
  @JsonValue('progress_tracking')
  progressTracking,
}

extension PlanIncludeX on PlanInclude {
  /// Display label in Rioplatense Spanish (ADR-4).
  String get label => switch (this) {
        PlanInclude.routines => 'Rutinas personalizadas',
        PlanInclude.nutrition => 'Plan nutricional',
        PlanInclude.chat => 'Chat ilimitado',
        PlanInclude.presentialSessions => 'Sesiones presenciales',
        PlanInclude.onlineSessions => 'Sesiones online',
        PlanInclude.progressTracking => 'Seguimiento de progreso',
      };
}

/// A commercial plan (pricing tier) the trainer offers to their athletes.
///
/// Stored at `commercialPlans/{planId}` with a Firestore-generated id.
/// `trainerId` is indexed for the trainer's "my plans" list query.
@freezed
class CommercialPlan with _$CommercialPlan {
  const factory CommercialPlan({
    required String id,
    required String trainerId,
    required String name,
    @Default('') String shortDescription,
    required int priceArs,
    @Default(1) int durationMonths,
    @Default(BillingFrequency.monthly) BillingFrequency billingFrequency,
    @Default(<PlanInclude>[]) List<PlanInclude> includes,
    @Default(CommercialPlanStatus.active) CommercialPlanStatus status,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
  }) = _CommercialPlan;

  factory CommercialPlan.fromJson(Map<String, Object?> json) =>
      _$CommercialPlanFromJson(json);
}
