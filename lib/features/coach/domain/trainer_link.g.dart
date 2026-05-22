// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrainerLinkImpl _$$TrainerLinkImplFromJson(Map<String, dynamic> json) =>
    _$TrainerLinkImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      status: $enumDecode(_$TrainerLinkStatusEnumMap, json['status']),
      requestedAt:
          const TimestampConverter().fromJson(json['requestedAt'] as Timestamp),
      acceptedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['acceptedAt'], const TimestampConverter().fromJson),
      terminatedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['terminatedAt'], const TimestampConverter().fromJson),
      terminationReason: json['terminationReason'] as String?,
      sharedWithTrainer: json['sharedWithTrainer'] as bool? ?? false,
    );

Map<String, dynamic> _$$TrainerLinkImplToJson(_$TrainerLinkImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'status': _$TrainerLinkStatusEnumMap[instance.status]!,
      'requestedAt': const TimestampConverter().toJson(instance.requestedAt),
      'acceptedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.acceptedAt, const TimestampConverter().toJson),
      'terminatedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.terminatedAt, const TimestampConverter().toJson),
      'terminationReason': instance.terminationReason,
      'sharedWithTrainer': instance.sharedWithTrainer,
    };

const _$TrainerLinkStatusEnumMap = {
  TrainerLinkStatus.pending: 'pending',
  TrainerLinkStatus.active: 'active',
  TrainerLinkStatus.paused: 'paused',
  TrainerLinkStatus.terminated: 'terminated',
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
