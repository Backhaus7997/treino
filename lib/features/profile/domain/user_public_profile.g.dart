// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_public_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserPublicProfileImpl _$$UserPublicProfileImplFromJson(
        Map<String, dynamic> json) =>
    _$UserPublicProfileImpl(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String?,
      displayNameLowercase: json['displayNameLowercase'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      gymId: json['gymId'] as String?,
    );

Map<String, dynamic> _$$UserPublicProfileImplToJson(
        _$UserPublicProfileImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'displayName': instance.displayName,
      'displayNameLowercase': instance.displayNameLowercase,
      'avatarUrl': instance.avatarUrl,
      'gymId': instance.gymId,
    };
