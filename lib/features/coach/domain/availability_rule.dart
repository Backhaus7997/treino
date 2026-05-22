import 'package:freezed_annotation/freezed_annotation.dart';

part 'availability_rule.freezed.dart';
part 'availability_rule.g.dart';

/// Allowed slot duration values, in minutes. REQ-COACH-AGENDA-001.
const Set<int> kAllowedSlotDurations = {30, 60, 90, 120};

/// Recurring weekly availability rule published by a trainer.
///
/// Stored at `coach_availability_rules/{id}`. Day of week uses the ISO
/// convention (1 = Monday, 7 = Sunday). Hours/minutes are interpreted in the
/// trainer's local timezone (Argentina UTC-3, hardcoded per ADR-7; revisit on
/// future TZ migration).
@freezed
class AvailabilityRule with _$AvailabilityRule {
  @Assert(
    'slotDurationMin == 30 || slotDurationMin == 60 || slotDurationMin == 90 || slotDurationMin == 120',
    'slotDurationMin must be one of {30, 60, 90, 120}',
  )
  const factory AvailabilityRule({
    required String id,
    required String trainerId,
    required int dayOfWeek,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int slotDurationMin,
  }) = _AvailabilityRule;

  factory AvailabilityRule.fromJson(Map<String, Object?> json) =>
      _$AvailabilityRuleFromJson(json);
}
