// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RoutineImpl _$$RoutineImplFromJson(Map<String, dynamic> json) =>
    _$RoutineImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      split: json['split'] as String,
      level: $enumDecode(_$ExperienceLevelEnumMap, json['level']),
      days: (json['days'] as List<dynamic>)
          .map((e) => RoutineDay.fromJson(e as Map<String, dynamic>))
          .toList(),
      estimatedMinutesPerDay: (json['estimatedMinutesPerDay'] as num?)?.toInt(),
      imageUrl: json['imageUrl'] as String?,
    );

Map<String, dynamic> _$$RoutineImplToJson(_$RoutineImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'split': instance.split,
      'level': _$ExperienceLevelEnumMap[instance.level]!,
      'days': instance.days.map((e) => e.toJson()).toList(),
      'estimatedMinutesPerDay': instance.estimatedMinutesPerDay,
      'imageUrl': instance.imageUrl,
    };

const _$ExperienceLevelEnumMap = {
  ExperienceLevel.beginner: 'beginner',
  ExperienceLevel.intermediate: 'intermediate',
  ExperienceLevel.advanced: 'advanced',
};
