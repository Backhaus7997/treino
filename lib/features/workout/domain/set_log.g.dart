// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SetLogImpl _$$SetLogImplFromJson(Map<String, dynamic> json) => _$SetLogImpl(
      id: json['id'] as String,
      exerciseId: json['exerciseId'] as String,
      exerciseName: json['exerciseName'] as String,
      setNumber: (json['setNumber'] as num).toInt(),
      reps: (json['reps'] as num).toInt(),
      weightKg: (json['weightKg'] as num).toDouble(),
      rpe: (json['rpe'] as num?)?.toInt(),
      completedAt:
          const TimestampConverter().fromJson(json['completedAt'] as Timestamp),
    );

Map<String, dynamic> _$$SetLogImplToJson(_$SetLogImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'exerciseId': instance.exerciseId,
      'exerciseName': instance.exerciseName,
      'setNumber': instance.setNumber,
      'reps': instance.reps,
      'weightKg': instance.weightKg,
      'rpe': instance.rpe,
      'completedAt': const TimestampConverter().toJson(instance.completedAt),
    };
