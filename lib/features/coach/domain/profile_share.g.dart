// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_share.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ProfileShareImpl _$$ProfileShareImplFromJson(Map<String, dynamic> json) =>
    _$ProfileShareImpl(
      trainerId: json['trainerId'] as String,
      phone: json['phone'] as String?,
      bornAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['bornAt'], const TimestampConverter().fromJson),
      heightCm: (json['heightCm'] as num?)?.toInt(),
      bodyWeightKg: (json['bodyWeightKg'] as num?)?.toDouble(),
      gender: $enumDecodeNullable(_$GenderEnumMap, json['gender']),
      experienceLevel: $enumDecodeNullable(
          _$ExperienceLevelEnumMap, json['experienceLevel']),
      updatedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['updatedAt'], const TimestampConverter().fromJson),
    );

Map<String, dynamic> _$$ProfileShareImplToJson(_$ProfileShareImpl instance) =>
    <String, dynamic>{
      'trainerId': instance.trainerId,
      'phone': instance.phone,
      'bornAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.bornAt, const TimestampConverter().toJson),
      'heightCm': instance.heightCm,
      'bodyWeightKg': instance.bodyWeightKg,
      'gender': _$GenderEnumMap[instance.gender],
      'experienceLevel': _$ExperienceLevelEnumMap[instance.experienceLevel],
      'updatedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.updatedAt, const TimestampConverter().toJson),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

const _$GenderEnumMap = {
  Gender.male: 'male',
  Gender.female: 'female',
  Gender.nonBinary: 'non_binary',
  Gender.undisclosed: 'undisclosed',
};

const _$ExperienceLevelEnumMap = {
  ExperienceLevel.beginner: 'beginner',
  ExperienceLevel.intermediate: 'intermediate',
  ExperienceLevel.advanced: 'advanced',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
