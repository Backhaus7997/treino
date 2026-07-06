// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PaymentImpl _$$PaymentImplFromJson(Map<String, dynamic> json) =>
    _$PaymentImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      amountArs: (json['amountArs'] as num).toInt(),
      concept: json['concept'] as String,
      status: $enumDecode(_$PaymentStatusEnumMap, json['status']),
      periodKey: json['periodKey'] as String?,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      paidAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['paidAt'], const TimestampConverter().fromJson),
      dueAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['dueAt'], const TimestampConverter().fromJson),
      lastOverdueNotifiedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['lastOverdueNotifiedAt'], const TimestampConverter().fromJson),
    );

Map<String, dynamic> _$$PaymentImplToJson(_$PaymentImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'amountArs': instance.amountArs,
      'concept': instance.concept,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'periodKey': instance.periodKey,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'paidAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.paidAt, const TimestampConverter().toJson),
      'dueAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.dueAt, const TimestampConverter().toJson),
      'lastOverdueNotifiedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.lastOverdueNotifiedAt, const TimestampConverter().toJson),
    };

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.paid: 'paid',
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
