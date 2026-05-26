// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExerciseImpl _$$ExerciseImplFromJson(Map<String, dynamic> json) =>
    _$ExerciseImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      muscleGroup: json['muscleGroup'] as String,
      category: json['category'] as String,
      techniqueInstructions: (json['techniqueInstructions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      videoUrl: json['videoUrl'] as String?,
      defaultRestSeconds: (json['defaultRestSeconds'] as num?)?.toInt(),
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$$ExerciseImplToJson(_$ExerciseImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'muscleGroup': instance.muscleGroup,
      'category': instance.category,
      'techniqueInstructions': instance.techniqueInstructions,
      'videoUrl': instance.videoUrl,
      'defaultRestSeconds': instance.defaultRestSeconds,
      'aliases': instance.aliases,
    };
