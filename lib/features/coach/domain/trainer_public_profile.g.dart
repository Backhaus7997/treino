// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_public_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrainerPublicProfileImpl _$$TrainerPublicProfileImplFromJson(
        Map<String, dynamic> json) =>
    _$TrainerPublicProfileImpl(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String?,
      displayNameLowercase: json['displayNameLowercase'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      trainerBio: json['trainerBio'] as String?,
      trainerSpecialty: _specialtyFromJson(json['trainerSpecialty']),
      trainerGeohash: json['trainerGeohash'] as String?,
      trainerLatitude: (json['trainerLatitude'] as num?)?.toDouble(),
      trainerLongitude: (json['trainerLongitude'] as num?)?.toDouble(),
      trainerMonthlyRate: (json['trainerMonthlyRate'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$TrainerPublicProfileImplToJson(
        _$TrainerPublicProfileImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'displayName': instance.displayName,
      'displayNameLowercase': instance.displayNameLowercase,
      'avatarUrl': instance.avatarUrl,
      'trainerBio': instance.trainerBio,
      'trainerSpecialty': _specialtyToJson(instance.trainerSpecialty),
      'trainerGeohash': instance.trainerGeohash,
      'trainerLatitude': instance.trainerLatitude,
      'trainerLongitude': instance.trainerLongitude,
      'trainerMonthlyRate': instance.trainerMonthlyRate,
    };
