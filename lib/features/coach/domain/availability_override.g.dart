// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'availability_override.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AvailabilityOverrideBlockImpl _$$AvailabilityOverrideBlockImplFromJson(
        Map<String, dynamic> json) =>
    _$AvailabilityOverrideBlockImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      date: const TimestampConverter().fromJson(json['date'] as Timestamp),
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$$AvailabilityOverrideBlockImplToJson(
        _$AvailabilityOverrideBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'date': const TimestampConverter().toJson(instance.date),
      'type': instance.$type,
    };

_$AvailabilityOverrideExtraImpl _$$AvailabilityOverrideExtraImplFromJson(
        Map<String, dynamic> json) =>
    _$AvailabilityOverrideExtraImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      date: const TimestampConverter().fromJson(json['date'] as Timestamp),
      startHour: (json['startHour'] as num).toInt(),
      startMinute: (json['startMinute'] as num).toInt(),
      endHour: (json['endHour'] as num).toInt(),
      endMinute: (json['endMinute'] as num).toInt(),
      slotDurationMin: (json['slotDurationMin'] as num).toInt(),
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$$AvailabilityOverrideExtraImplToJson(
        _$AvailabilityOverrideExtraImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'date': const TimestampConverter().toJson(instance.date),
      'startHour': instance.startHour,
      'startMinute': instance.startMinute,
      'endHour': instance.endHour,
      'endMinute': instance.endMinute,
      'slotDurationMin': instance.slotDurationMin,
      'type': instance.$type,
    };
