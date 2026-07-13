// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_subscription.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrainerSubscriptionImpl _$$TrainerSubscriptionImplFromJson(
        Map<String, dynamic> json) =>
    _$TrainerSubscriptionImpl(
      tier: $enumDecode(_$SubscriptionTierEnumMap, json['tier']),
      status: $enumDecode(_$SubscriptionStatusEnumMap, json['status']),
      cycle: $enumDecodeNullable(_$SubscriptionCycleEnumMap, json['cycle']),
      weightLimit: (json['weightLimit'] as num).toInt(),
      currentPeriodEnd: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['currentPeriodEnd'], const TimestampConverter().fromJson),
      graceUntil: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['graceUntil'], const TimestampConverter().fromJson),
      mpPreapprovalId: json['mpPreapprovalId'] as String?,
      updatedByWebhookAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['updatedByWebhookAt'], const TimestampConverter().fromJson),
      lastMpEventId: json['lastMpEventId'] as String?,
    );

Map<String, dynamic> _$$TrainerSubscriptionImplToJson(
        _$TrainerSubscriptionImpl instance) =>
    <String, dynamic>{
      'tier': _$SubscriptionTierEnumMap[instance.tier]!,
      'status': _$SubscriptionStatusEnumMap[instance.status]!,
      'cycle': _$SubscriptionCycleEnumMap[instance.cycle],
      'weightLimit': instance.weightLimit,
      'currentPeriodEnd': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.currentPeriodEnd, const TimestampConverter().toJson),
      'graceUntil': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.graceUntil, const TimestampConverter().toJson),
      'mpPreapprovalId': instance.mpPreapprovalId,
      'updatedByWebhookAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.updatedByWebhookAt, const TimestampConverter().toJson),
      'lastMpEventId': instance.lastMpEventId,
    };

const _$SubscriptionTierEnumMap = {
  SubscriptionTier.free: 'free',
  SubscriptionTier.plan1: 'plan1',
  SubscriptionTier.plan2: 'plan2',
};

const _$SubscriptionStatusEnumMap = {
  SubscriptionStatus.active: 'active',
  SubscriptionStatus.pending: 'pending',
  SubscriptionStatus.grace: 'grace',
  SubscriptionStatus.paused: 'paused',
  SubscriptionStatus.cancelled: 'cancelled',
};

const _$SubscriptionCycleEnumMap = {
  SubscriptionCycle.monthly: 'monthly',
  SubscriptionCycle.annual: 'annual',
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
