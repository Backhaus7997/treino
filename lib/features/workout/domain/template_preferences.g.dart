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
      goal: $enumDecodeNullable(_$RoutineGoalEnumMap, json['goal'],
          unknownValue: JsonKey.nullForUndefinedEnumValue),
      priorityMuscleGroups: (json['priorityMuscleGroups'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$$TemplatePreferencesImplToJson(
        _$TemplatePreferencesImpl instance) =>
    <String, dynamic>{
      'daysPerWeek': instance.daysPerWeek,
      'minutesPerSession': instance.minutesPerSession,
      'goal': _$RoutineGoalEnumMap[instance.goal],
      'priorityMuscleGroups': instance.priorityMuscleGroups,
    };

const _$RoutineGoalEnumMap = {
  RoutineGoal.health: 'health',
  RoutineGoal.injuryPrevention: 'injury_prevention',
  RoutineGoal.aesthetics: 'aesthetics',
  RoutineGoal.sport: 'sport',
  RoutineGoal.wellbeing: 'wellbeing',
};
