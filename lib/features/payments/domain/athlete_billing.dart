// ignore: unused_import — Timestamp is used by the generated athlete_billing.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'athlete_billing.freezed.dart';
part 'athlete_billing.g.dart';

/// Billing cadence options for per-athlete pricing.
enum BillingCadence {
  @JsonValue('mensual')
  mensual,
  @JsonValue('semanal')
  semanal,
  @JsonValue('por_sesion')
  porSesion,
  @JsonValue('suelto')
  suelto,
}

/// Per-athlete billing configuration set by the trainer.
///
/// Stored in `athlete_billing/{trainerId}_{athleteId}`.
/// Doc id is deterministic — no need to inject from snapshot.
@freezed
class AthleteBilling with _$AthleteBilling {
  const factory AthleteBilling({
    required String trainerId,
    required String athleteId,
    required int amountArs,
    required BillingCadence cadence,
    @TimestampConverter() required DateTime updatedAt,
  }) = _AthleteBilling;

  factory AthleteBilling.fromJson(Map<String, Object?> json) =>
      _$AthleteBillingFromJson(json);
}
