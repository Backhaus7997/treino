// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parsed_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ParsedPlanImpl _$$ParsedPlanImplFromJson(Map<String, dynamic> json) =>
    _$ParsedPlanImpl(
      name: json['name'] as String,
      daysPerWeek: (json['daysPerWeek'] as num).toInt(),
      durationWeeks: (json['durationWeeks'] as num).toInt(),
      level: $enumDecode(_$ExperienceLevelEnumMap, json['level']),
      days: (json['days'] as List<dynamic>)
          .map((e) => ParsedPlanDay.fromJson(e as Map<String, dynamic>))
          .toList(),
      unmatched: (json['unmatched'] as List<dynamic>?)
              ?.map((e) =>
                  ParsedPlanUnmatched.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <ParsedPlanUnmatched>[],
    );

Map<String, dynamic> _$$ParsedPlanImplToJson(_$ParsedPlanImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'daysPerWeek': instance.daysPerWeek,
      'durationWeeks': instance.durationWeeks,
      'level': _$ExperienceLevelEnumMap[instance.level]!,
      'days': instance.days.map((e) => e.toJson()).toList(),
      'unmatched': instance.unmatched.map((e) => e.toJson()).toList(),
    };

const _$ExperienceLevelEnumMap = {
  ExperienceLevel.beginner: 'beginner',
  ExperienceLevel.intermediate: 'intermediate',
  ExperienceLevel.advanced: 'advanced',
};

_$ParsedPlanDayImpl _$$ParsedPlanDayImplFromJson(Map<String, dynamic> json) =>
    _$ParsedPlanDayImpl(
      dayNumber: (json['dayNumber'] as num).toInt(),
      items: (json['items'] as List<dynamic>)
          .map((e) => ParsedPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$ParsedPlanDayImplToJson(_$ParsedPlanDayImpl instance) =>
    <String, dynamic>{
      'dayNumber': instance.dayNumber,
      'items': instance.items.map((e) => e.toJson()).toList(),
    };

_$ParsedPlanItemImpl _$$ParsedPlanItemImplFromJson(Map<String, dynamic> json) =>
    _$ParsedPlanItemImpl(
      rowName: json['rowName'] as String,
      sets: (json['sets'] as num).toInt(),
      repsMin: (json['repsMin'] as num).toInt(),
      repsMax: (json['repsMax'] as num).toInt(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      restSec: (json['restSec'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      exerciseId: json['exerciseId'] as String?,
      exerciseName: json['exerciseName'] as String,
      muscleGroup: json['muscleGroup'] as String?,
    );

Map<String, dynamic> _$$ParsedPlanItemImplToJson(
        _$ParsedPlanItemImpl instance) =>
    <String, dynamic>{
      'rowName': instance.rowName,
      'sets': instance.sets,
      'repsMin': instance.repsMin,
      'repsMax': instance.repsMax,
      'weightKg': instance.weightKg,
      'restSec': instance.restSec,
      'notes': instance.notes,
      'exerciseId': instance.exerciseId,
      'exerciseName': instance.exerciseName,
      'muscleGroup': instance.muscleGroup,
    };

_$ParsedPlanUnmatchedImpl _$$ParsedPlanUnmatchedImplFromJson(
        Map<String, dynamic> json) =>
    _$ParsedPlanUnmatchedImpl(
      dayNumber: (json['dayNumber'] as num).toInt(),
      rowName: json['rowName'] as String,
    );

Map<String, dynamic> _$$ParsedPlanUnmatchedImplToJson(
        _$ParsedPlanUnmatchedImpl instance) =>
    <String, dynamic>{
      'dayNumber': instance.dayNumber,
      'rowName': instance.rowName,
    };
