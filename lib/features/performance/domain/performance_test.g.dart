// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'performance_test.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PerformanceTestImpl _$$PerformanceTestImplFromJson(
        Map<String, dynamic> json) =>
    _$PerformanceTestImpl(
      id: json['id'] as String,
      athleteId: json['athleteId'] as String,
      recordedBy: json['recordedBy'] as String,
      recordedAt:
          const TimestampConverter().fromJson(json['recordedAt'] as Timestamp),
      cmjCm: (json['cmjCm'] as num?)?.toDouble(),
      squatJumpCm: (json['squatJumpCm'] as num?)?.toDouble(),
      abalakovCm: (json['abalakovCm'] as num?)?.toDouble(),
      broadJumpCm: (json['broadJumpCm'] as num?)?.toDouble(),
      sprint10mS: (json['sprint10mS'] as num?)?.toDouble(),
      sprint20mS: (json['sprint20mS'] as num?)?.toDouble(),
      sprint30mS: (json['sprint30mS'] as num?)?.toDouble(),
      sprint40mS: (json['sprint40mS'] as num?)?.toDouble(),
      squat1rmKg: (json['squat1rmKg'] as num?)?.toDouble(),
      benchPress1rmKg: (json['benchPress1rmKg'] as num?)?.toDouble(),
      deadlift1rmKg: (json['deadlift1rmKg'] as num?)?.toDouble(),
      overheadPress1rmKg: (json['overheadPress1rmKg'] as num?)?.toDouble(),
      pullUp1rmKg: (json['pullUp1rmKg'] as num?)?.toDouble(),
      vo2maxMlKgMin: (json['vo2maxMlKgMin'] as num?)?.toDouble(),
      courseNavetteLevel: (json['courseNavetteLevel'] as num?)?.toDouble(),
      cooperMeters: (json['cooperMeters'] as num?)?.toDouble(),
      sitAndReachCm: (json['sitAndReachCm'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$PerformanceTestImplToJson(
        _$PerformanceTestImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'athleteId': instance.athleteId,
      'recordedBy': instance.recordedBy,
      'recordedAt': const TimestampConverter().toJson(instance.recordedAt),
      'cmjCm': instance.cmjCm,
      'squatJumpCm': instance.squatJumpCm,
      'abalakovCm': instance.abalakovCm,
      'broadJumpCm': instance.broadJumpCm,
      'sprint10mS': instance.sprint10mS,
      'sprint20mS': instance.sprint20mS,
      'sprint30mS': instance.sprint30mS,
      'sprint40mS': instance.sprint40mS,
      'squat1rmKg': instance.squat1rmKg,
      'benchPress1rmKg': instance.benchPress1rmKg,
      'deadlift1rmKg': instance.deadlift1rmKg,
      'overheadPress1rmKg': instance.overheadPress1rmKg,
      'pullUp1rmKg': instance.pullUp1rmKg,
      'vo2maxMlKgMin': instance.vo2maxMlKgMin,
      'courseNavetteLevel': instance.courseNavetteLevel,
      'cooperMeters': instance.cooperMeters,
      'sitAndReachCm': instance.sitAndReachCm,
      'notes': instance.notes,
    };
