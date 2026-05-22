// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'availability_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AvailabilityRuleImpl _$$AvailabilityRuleImplFromJson(
        Map<String, dynamic> json) =>
    _$AvailabilityRuleImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      dayOfWeek: (json['dayOfWeek'] as num).toInt(),
      startHour: (json['startHour'] as num).toInt(),
      startMinute: (json['startMinute'] as num).toInt(),
      endHour: (json['endHour'] as num).toInt(),
      endMinute: (json['endMinute'] as num).toInt(),
      slotDurationMin: (json['slotDurationMin'] as num).toInt(),
    );

Map<String, dynamic> _$$AvailabilityRuleImplToJson(
        _$AvailabilityRuleImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'dayOfWeek': instance.dayOfWeek,
      'startHour': instance.startHour,
      'startMinute': instance.startMinute,
      'endHour': instance.endHour,
      'endMinute': instance.endMinute,
      'slotDurationMin': instance.slotDurationMin,
    };
