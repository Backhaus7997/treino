// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WorkoutSnapshotImpl _$$WorkoutSnapshotImplFromJson(
        Map<String, dynamic> json) =>
    _$WorkoutSnapshotImpl(
      exercises: (json['exercises'] as List<dynamic>)
          .map((e) =>
              WorkoutSnapshotExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      setsByAxis: (json['setsByAxis'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toInt()),
          ) ??
          const <String, int>{},
      volumeKgByAxis: (json['volumeKgByAxis'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toDouble()),
          ) ??
          const <String, double>{},
      truncated: json['truncated'] as bool? ?? false,
    );

Map<String, dynamic> _$$WorkoutSnapshotImplToJson(
        _$WorkoutSnapshotImpl instance) =>
    <String, dynamic>{
      'exercises': instance.exercises.map((e) => e.toJson()).toList(),
      'setsByAxis': instance.setsByAxis,
      'volumeKgByAxis': instance.volumeKgByAxis,
      'truncated': instance.truncated,
    };

_$WorkoutSnapshotExerciseImpl _$$WorkoutSnapshotExerciseImplFromJson(
        Map<String, dynamic> json) =>
    _$WorkoutSnapshotExerciseImpl(
      exerciseName: json['exerciseName'] as String,
      sets: (json['sets'] as List<dynamic>)
          .map((e) => SetLog.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$WorkoutSnapshotExerciseImplToJson(
        _$WorkoutSnapshotExerciseImpl instance) =>
    <String, dynamic>{
      'exerciseName': instance.exerciseName,
      'sets': instance.sets.map((e) => e.toJson()).toList(),
    };
