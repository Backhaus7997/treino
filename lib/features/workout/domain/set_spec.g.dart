// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_spec.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SetSpecImpl _$$SetSpecImplFromJson(Map<String, dynamic> json) =>
    _$SetSpecImpl(
      type: $enumDecodeNullable(_$SetTypeEnumMap, json['type'],
              unknownValue: SetType.normal) ??
          SetType.normal,
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      reps: (json['reps'] as num?)?.toInt(),
      repsMin: (json['repsMin'] as num?)?.toInt(),
      repsMax: (json['repsMax'] as num?)?.toInt(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$SetSpecImplToJson(_$SetSpecImpl instance) =>
    <String, dynamic>{
      'type': _$SetTypeEnumMap[instance.type]!,
      'weightKg': instance.weightKg,
      'reps': instance.reps,
      'repsMin': instance.repsMin,
      'repsMax': instance.repsMax,
      'durationSeconds': instance.durationSeconds,
    };

const _$SetTypeEnumMap = {
  SetType.warmup: 'warmup',
  SetType.normal: 'normal',
  SetType.drop: 'drop',
  SetType.failure: 'failure',
};
