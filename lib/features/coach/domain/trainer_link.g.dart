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
      pausedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['pausedAt'], const TimestampConverter().fromJson),
      sharedWithTrainer: json['sharedWithTrainer'] as bool? ?? false,
      entitlement: $enumDecodeNullable(
              _$TrainerLinkEntitlementEnumMap, json['entitlement']) ??
          TrainerLinkEntitlement.entitled,
      blockedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['blockedAt'], const TimestampConverter().fromJson),
      blockedReason: json['blockedReason'] as String?,
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
      'pausedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.pausedAt, const TimestampConverter().toJson),
      'sharedWithTrainer': instance.sharedWithTrainer,
      'entitlement': _$TrainerLinkEntitlementEnumMap[instance.entitlement]!,
      'blockedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.blockedAt, const TimestampConverter().toJson),
      'blockedReason': instance.blockedReason,
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

const _$TrainerLinkEntitlementEnumMap = {
  TrainerLinkEntitlement.entitled: 'entitled',
  TrainerLinkEntitlement.blocked: 'blocked',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
