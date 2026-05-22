// ignore: unused_import — Timestamp is used by the generated availability_override.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'availability_override.freezed.dart';
part 'availability_override.g.dart';

/// Date-specific override that either blocks an entire day or adds an extra
/// availability window on top of (or outside of) the recurring weekly rules.
///
/// Stored at `coach_availability_overrides/{id}`. Sealed union discriminated
/// by the `type` field on the JSON wire (`"block" | "extra"`). ADR-6.
@Freezed(unionKey: 'type', unionValueCase: FreezedUnionCase.none)
sealed class AvailabilityOverride with _$AvailabilityOverride {
  /// Blocks the entire `date` — no slots will be generated.
  @FreezedUnionValue('block')
  const factory AvailabilityOverride.block({
    required String id,
    required String trainerId,
    @TimestampConverter() required DateTime date,
  }) = AvailabilityOverrideBlock;

  /// Adds an extra availability window on `date`. Time fields are required.
  @FreezedUnionValue('extra')
  @Assert(
    'slotDurationMin == 30 || slotDurationMin == 60 || slotDurationMin == 90 || slotDurationMin == 120',
    'slotDurationMin must be one of {30, 60, 90, 120}',
  )
  const factory AvailabilityOverride.extra({
    required String id,
    required String trainerId,
    @TimestampConverter() required DateTime date,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int slotDurationMin,
  }) = AvailabilityOverrideExtra;

  factory AvailabilityOverride.fromJson(Map<String, Object?> json) =>
      _$AvailabilityOverrideFromJson(json);
}
