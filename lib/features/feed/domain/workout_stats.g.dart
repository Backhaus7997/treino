// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_stats.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WorkoutStatsImpl _$$WorkoutStatsImplFromJson(Map<String, dynamic> json) =>
    _$WorkoutStatsImpl(
      volumeKg: (json['volumeKg'] as num).toDouble(),
      durationMin: (json['durationMin'] as num).toInt(),
      exerciseCount: (json['exerciseCount'] as num).toInt(),
    );

Map<String, dynamic> _$$WorkoutStatsImplToJson(_$WorkoutStatsImpl instance) =>
    <String, dynamic>{
      'volumeKg': instance.volumeKg,
      'durationMin': instance.durationMin,
      'exerciseCount': instance.exerciseCount,
    };
