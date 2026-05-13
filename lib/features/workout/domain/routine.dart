import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import 'routine_day.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

@freezed
class Routine with _$Routine {
  const factory Routine({
    required String id,
    required String name,
    required String split, // 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form)
    required ExperienceLevel level,
    required List<RoutineDay> days, // empty list valid (spec SCENARIO-052)
    int? estimatedMinutesPerDay,
    String? imageUrl, // null for seed PR 2 (ADR-3); future Storage URL
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
