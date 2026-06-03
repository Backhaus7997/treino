// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'athlete_billing.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AthleteBillingImpl _$$AthleteBillingImplFromJson(Map<String, dynamic> json) =>
    _$AthleteBillingImpl(
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      amountArs: (json['amountArs'] as num).toInt(),
      cadence: $enumDecode(_$BillingCadenceEnumMap, json['cadence']),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$AthleteBillingImplToJson(
        _$AthleteBillingImpl instance) =>
    <String, dynamic>{
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'amountArs': instance.amountArs,
      'cadence': _$BillingCadenceEnumMap[instance.cadence]!,
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };

const _$BillingCadenceEnumMap = {
  BillingCadence.mensual: 'mensual',
  BillingCadence.semanal: 'semanal',
  BillingCadence.porSesion: 'por_sesion',
  BillingCadence.suelto: 'suelto',
};
