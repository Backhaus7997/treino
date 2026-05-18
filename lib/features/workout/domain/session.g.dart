// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SessionImpl _$$SessionImplFromJson(Map<String, dynamic> json) =>
    _$SessionImpl(
      id: json['id'] as String,
      uid: json['uid'] as String,
      routineId: json['routineId'] as String,
      routineName: json['routineName'] as String,
      startedAt:
          const TimestampConverter().fromJson(json['startedAt'] as Timestamp),
      finishedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['finishedAt'], const TimestampConverter().fromJson),
      totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble() ?? 0.0,
      durationMin: (json['durationMin'] as num?)?.toInt() ?? 0,
      status: $enumDecode(_$SessionStatusEnumMap, json['status']),
    );

Map<String, dynamic> _$$SessionImplToJson(_$SessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'uid': instance.uid,
      'routineId': instance.routineId,
      'routineName': instance.routineName,
      'startedAt': const TimestampConverter().toJson(instance.startedAt),
      'finishedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.finishedAt, const TimestampConverter().toJson),
      'totalVolumeKg': instance.totalVolumeKg,
      'durationMin': instance.durationMin,
      'status': _$SessionStatusEnumMap[instance.status]!,
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

const _$SessionStatusEnumMap = {
  SessionStatus.active: 'active',
  SessionStatus.finished: 'finished',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
