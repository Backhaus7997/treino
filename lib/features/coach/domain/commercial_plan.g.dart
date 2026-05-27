// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commercial_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CommercialPlanImpl _$$CommercialPlanImplFromJson(Map<String, dynamic> json) =>
    _$CommercialPlanImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      name: json['name'] as String,
      shortDescription: json['shortDescription'] as String? ?? '',
      priceArs: (json['priceArs'] as num).toInt(),
      durationMonths: (json['durationMonths'] as num?)?.toInt() ?? 1,
      billingFrequency: $enumDecodeNullable(
              _$BillingFrequencyEnumMap, json['billingFrequency']) ??
          BillingFrequency.monthly,
      includes: (json['includes'] as List<dynamic>?)
              ?.map((e) => $enumDecode(_$PlanIncludeEnumMap, e))
              .toList() ??
          const <PlanInclude>[],
      status:
          $enumDecodeNullable(_$CommercialPlanStatusEnumMap, json['status']) ??
              CommercialPlanStatus.active,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$CommercialPlanImplToJson(
        _$CommercialPlanImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'name': instance.name,
      'shortDescription': instance.shortDescription,
      'priceArs': instance.priceArs,
      'durationMonths': instance.durationMonths,
      'billingFrequency': _$BillingFrequencyEnumMap[instance.billingFrequency]!,
      'includes':
          instance.includes.map((e) => _$PlanIncludeEnumMap[e]!).toList(),
      'status': _$CommercialPlanStatusEnumMap[instance.status]!,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };

const _$BillingFrequencyEnumMap = {
  BillingFrequency.monthly: 'monthly',
  BillingFrequency.quarterly: 'quarterly',
  BillingFrequency.yearly: 'yearly',
  BillingFrequency.oneTime: 'one_time',
};

const _$PlanIncludeEnumMap = {
  PlanInclude.routines: 'routines',
  PlanInclude.nutrition: 'nutrition',
  PlanInclude.chat: 'chat',
  PlanInclude.presentialSessions: 'presential_sessions',
  PlanInclude.onlineSessions: 'online_sessions',
  PlanInclude.progressTracking: 'progress_tracking',
};

const _$CommercialPlanStatusEnumMap = {
  CommercialPlanStatus.active: 'active',
  CommercialPlanStatus.archived: 'archived',
};
