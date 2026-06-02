// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'measurement.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MeasurementImpl _$$MeasurementImplFromJson(Map<String, dynamic> json) =>
    _$MeasurementImpl(
      id: json['id'] as String,
      athleteId: json['athleteId'] as String,
      recordedBy: json['recordedBy'] as String,
      recordedAt:
          const TimestampConverter().fromJson(json['recordedAt'] as Timestamp),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      fatPercentage: (json['fatPercentage'] as num?)?.toDouble(),
      muscleMassKg: (json['muscleMassKg'] as num?)?.toDouble(),
      shouldersCm: (json['shouldersCm'] as num?)?.toDouble(),
      chestCm: (json['chestCm'] as num?)?.toDouble(),
      waistCm: (json['waistCm'] as num?)?.toDouble(),
      hipsCm: (json['hipsCm'] as num?)?.toDouble(),
      glutesCm: (json['glutesCm'] as num?)?.toDouble(),
      bicepsLCm: (json['bicepsLCm'] as num?)?.toDouble(),
      bicepsRCm: (json['bicepsRCm'] as num?)?.toDouble(),
      bicepsFlexedLCm: (json['bicepsFlexedLCm'] as num?)?.toDouble(),
      bicepsFlexedRCm: (json['bicepsFlexedRCm'] as num?)?.toDouble(),
      forearmLCm: (json['forearmLCm'] as num?)?.toDouble(),
      forearmRCm: (json['forearmRCm'] as num?)?.toDouble(),
      upperThighLCm: (json['upperThighLCm'] as num?)?.toDouble(),
      upperThighRCm: (json['upperThighRCm'] as num?)?.toDouble(),
      midThighLCm: (json['midThighLCm'] as num?)?.toDouble(),
      midThighRCm: (json['midThighRCm'] as num?)?.toDouble(),
      calfLCm: (json['calfLCm'] as num?)?.toDouble(),
      calfRCm: (json['calfRCm'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$MeasurementImplToJson(_$MeasurementImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'athleteId': instance.athleteId,
      'recordedBy': instance.recordedBy,
      'recordedAt': const TimestampConverter().toJson(instance.recordedAt),
      'weightKg': instance.weightKg,
      'fatPercentage': instance.fatPercentage,
      'muscleMassKg': instance.muscleMassKg,
      'shouldersCm': instance.shouldersCm,
      'chestCm': instance.chestCm,
      'waistCm': instance.waistCm,
      'hipsCm': instance.hipsCm,
      'glutesCm': instance.glutesCm,
      'bicepsLCm': instance.bicepsLCm,
      'bicepsRCm': instance.bicepsRCm,
      'bicepsFlexedLCm': instance.bicepsFlexedLCm,
      'bicepsFlexedRCm': instance.bicepsFlexedRCm,
      'forearmLCm': instance.forearmLCm,
      'forearmRCm': instance.forearmRCm,
      'upperThighLCm': instance.upperThighLCm,
      'upperThighRCm': instance.upperThighRCm,
      'midThighLCm': instance.midThighLCm,
      'midThighRCm': instance.midThighRCm,
      'calfLCm': instance.calfLCm,
      'calfRCm': instance.calfRCm,
      'notes': instance.notes,
    };
