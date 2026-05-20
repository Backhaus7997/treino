// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserProfileImpl _$$UserProfileImplFromJson(Map<String, dynamic> json) =>
    _$UserProfileImpl(
      uid: json['uid'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      role: $enumDecode(_$UserRoleEnumMap, json['role']),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
      gymId: json['gymId'] as String?,
      bodyWeightKg: (json['bodyWeightKg'] as num?)?.toDouble(),
      heightCm: (json['heightCm'] as num?)?.toInt(),
      gender: $enumDecodeNullable(_$GenderEnumMap, json['gender']),
      experienceLevel: $enumDecodeNullable(
          _$ExperienceLevelEnumMap, json['experienceLevel']),
      avatarUrl: json['avatarUrl'] as String?,
      bornAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['bornAt'], const TimestampConverter().fromJson),
      trainerBio: json['trainerBio'] as String?,
      trainerSpecialty: json['trainerSpecialty'] as String?,
      trainerLatitude: (json['trainerLatitude'] as num?)?.toDouble(),
      trainerLongitude: (json['trainerLongitude'] as num?)?.toDouble(),
      trainerGeohash: json['trainerGeohash'] as String?,
      trainerHourlyRate: (json['trainerHourlyRate'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$UserProfileImplToJson(_$UserProfileImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'email': instance.email,
      'displayName': instance.displayName,
      'role': _$UserRoleEnumMap[instance.role]!,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
      'gymId': instance.gymId,
      'bodyWeightKg': instance.bodyWeightKg,
      'heightCm': instance.heightCm,
      'gender': _$GenderEnumMap[instance.gender],
      'experienceLevel': _$ExperienceLevelEnumMap[instance.experienceLevel],
      'avatarUrl': instance.avatarUrl,
      'bornAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.bornAt, const TimestampConverter().toJson),
      'trainerBio': instance.trainerBio,
      'trainerSpecialty': instance.trainerSpecialty,
      'trainerLatitude': instance.trainerLatitude,
      'trainerLongitude': instance.trainerLongitude,
      'trainerGeohash': instance.trainerGeohash,
      'trainerHourlyRate': instance.trainerHourlyRate,
    };

const _$UserRoleEnumMap = {
  UserRole.athlete: 'athlete',
  UserRole.trainer: 'trainer',
};

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
