// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_exercise.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CustomExerciseImpl _$$CustomExerciseImplFromJson(Map<String, dynamic> json) =>
    _$CustomExerciseImpl(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String,
      name: json['name'] as String,
      muscleGroup: json['muscleGroup'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['videoUrl'] as String?,
      defaultRestSeconds: (json['defaultRestSeconds'] as num?)?.toInt(),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$CustomExerciseImplToJson(
        _$CustomExerciseImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'ownerId': instance.ownerId,
      'name': instance.name,
      'muscleGroup': instance.muscleGroup,
      'description': instance.description,
      'videoUrl': instance.videoUrl,
      'defaultRestSeconds': instance.defaultRestSeconds,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };
