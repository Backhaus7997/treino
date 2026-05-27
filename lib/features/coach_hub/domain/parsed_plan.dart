import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';

part 'parsed_plan.freezed.dart';
part 'parsed_plan.g.dart';

/// Resultado de `parsePlan` Cloud Function — plan importado desde Excel,
/// con ejercicios ya matcheados contra la collection `exercises`.
///
/// NO se persiste todavía — el PF tiene que confirmar en el preview screen
/// antes de pasar al asignador (Etapa 8 cierre).
@freezed
class ParsedPlan with _$ParsedPlan {
  const factory ParsedPlan({
    required String name,
    required int daysPerWeek,
    required int durationWeeks,
    required ExperienceLevel level,
    required List<ParsedPlanDay> days,
    @Default(<ParsedPlanUnmatched>[]) List<ParsedPlanUnmatched> unmatched,
  }) = _ParsedPlan;

  factory ParsedPlan.fromJson(Map<String, Object?> json) =>
      _$ParsedPlanFromJson(json);
}

@freezed
class ParsedPlanDay with _$ParsedPlanDay {
  const factory ParsedPlanDay({
    required int dayNumber,
    required List<ParsedPlanItem> items,
  }) = _ParsedPlanDay;

  factory ParsedPlanDay.fromJson(Map<String, Object?> json) =>
      _$ParsedPlanDayFromJson(json);
}

@freezed
class ParsedPlanItem with _$ParsedPlanItem {
  const factory ParsedPlanItem({
    required String rowName,
    required int sets,
    required int repsMin,
    required int repsMax,
    double? weightKg,
    int? restSec,
    String? notes,
    String? exerciseId,
    required String exerciseName,
    String? muscleGroup,
  }) = _ParsedPlanItem;

  factory ParsedPlanItem.fromJson(Map<String, Object?> json) =>
      _$ParsedPlanItemFromJson(json);
}

@freezed
class ParsedPlanUnmatched with _$ParsedPlanUnmatched {
  const factory ParsedPlanUnmatched({
    required int dayNumber,
    required String rowName,
  }) = _ParsedPlanUnmatched;

  factory ParsedPlanUnmatched.fromJson(Map<String, Object?> json) =>
      _$ParsedPlanUnmatchedFromJson(json);
}
