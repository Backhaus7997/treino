// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_preferences.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TemplatePreferencesImpl _$$TemplatePreferencesImplFromJson(
        Map<String, dynamic> json) =>
    _$TemplatePreferencesImpl(
      daysPerWeek: (json['daysPerWeek'] as num?)?.toInt(),
      minutesPerSession: (json['minutesPerSession'] as num?)?.toInt(),
      goals: _readGoals(json, 'goals') == null
          ? const <RoutineGoal>[]
          : const RoutineGoalListConverter()
              .fromJson(_readGoals(json, 'goals') as List?),
      priorityMuscleGroups: (json['priorityMuscleGroups'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );
