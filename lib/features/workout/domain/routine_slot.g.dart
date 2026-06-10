// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routine_slot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RoutineSlotImpl _$$RoutineSlotImplFromJson(Map<String, dynamic> json) =>
    _$RoutineSlotImpl(
      exerciseId: json['exerciseId'] as String,
      exerciseName: json['exerciseName'] as String,
      muscleGroup: json['muscleGroup'] as String,
      targetSets: (json['targetSets'] as num).toInt(),
      targetRepsMin: (json['targetRepsMin'] as num).toInt(),
      targetRepsMax: (json['targetRepsMax'] as num).toInt(),
      restSeconds: (json['restSeconds'] as num).toInt(),
      targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      supersetGroup: (json['supersetGroup'] as num?)?.toInt(),
      targetReps: (json['targetReps'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[],
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      exerciseMode: $enumDecodeNullable(
              _$ExerciseModeEnumMap, json['exerciseMode'],
              unknownValue: ExerciseMode.reps) ??
          ExerciseMode.reps,
      repMode: $enumDecodeNullable(_$RepModeEnumMap, json['repMode'],
              unknownValue: RepMode.single) ??
          RepMode.single,
      sets: (json['sets'] as List<dynamic>?)
              ?.map((e) => SetSpec.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <SetSpec>[],
      weeklySets: json['weeklySets'] == null
          ? const <List<SetSpec>>[]
          : const WeeklySetsConverter().fromJson(json['weeklySets'] as List),
    );

Map<String, dynamic> _$$RoutineSlotImplToJson(_$RoutineSlotImpl instance) =>
    <String, dynamic>{
      'exerciseId': instance.exerciseId,
      'exerciseName': instance.exerciseName,
      'muscleGroup': instance.muscleGroup,
      'targetSets': instance.targetSets,
      'targetRepsMin': instance.targetRepsMin,
      'targetRepsMax': instance.targetRepsMax,
      'restSeconds': instance.restSeconds,
      'targetWeightKg': instance.targetWeightKg,
      'notes': instance.notes,
      'supersetGroup': instance.supersetGroup,
      'targetReps': instance.targetReps,
      'durationSeconds': instance.durationSeconds,
      'exerciseMode': _$ExerciseModeEnumMap[instance.exerciseMode]!,
      'repMode': _$RepModeEnumMap[instance.repMode]!,
      'sets': instance.sets.map((e) => e.toJson()).toList(),
      'weeklySets': const WeeklySetsConverter().toJson(instance.weeklySets),
    };

const _$ExerciseModeEnumMap = {
  ExerciseMode.reps: 'reps',
  ExerciseMode.duration: 'duration',
};

const _$RepModeEnumMap = {
  RepMode.single: 'single',
  RepMode.range: 'range',
};
