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
      source: $enumDecodeNullable(_$RoutineSourceEnumMap, json['source']) ??
          RoutineSource.system,
      assignedBy: json['assignedBy'] as String?,
      assignedTo: json['assignedTo'] as String?,
      visibility:
          $enumDecodeNullable(_$RoutineVisibilityEnumMap, json['visibility']) ??
              RoutineVisibility.public,
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
      'source': _$RoutineSourceEnumMap[instance.source]!,
      'assignedBy': instance.assignedBy,
      'assignedTo': instance.assignedTo,
      'visibility': _$RoutineVisibilityEnumMap[instance.visibility]!,
    };

const _$ExperienceLevelEnumMap = {
  ExperienceLevel.beginner: 'beginner',
  ExperienceLevel.intermediate: 'intermediate',
  ExperienceLevel.advanced: 'advanced',
};

const _$RoutineSourceEnumMap = {
  RoutineSource.system: 'system',
  RoutineSource.trainerAssigned: 'trainer-assigned',
  RoutineSource.userCreated: 'user-created',
};

const _$RoutineVisibilityEnumMap = {
  RoutineVisibility.public: 'public',
  RoutineVisibility.private: 'private',
  RoutineVisibility.shared: 'shared',
};
