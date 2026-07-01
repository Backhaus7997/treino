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
      gymName: json['gymName'] as String?,
      workoutsCount: (json['workoutsCount'] as num?)?.toInt(),
      racha: (json['racha'] as num?)?.toInt(),
      followersCount:
          _nonNegativeCount((json['followersCount'] as num?)?.toInt()),
      followingCount:
          _nonNegativeCount((json['followingCount'] as num?)?.toInt()),
      sharedTemplatesWithAthletes:
          json['sharedTemplatesWithAthletes'] as bool? ?? false,
    );

Map<String, dynamic> _$$UserPublicProfileImplToJson(
        _$UserPublicProfileImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'displayName': instance.displayName,
      'displayNameLowercase': instance.displayNameLowercase,
      'avatarUrl': instance.avatarUrl,
      'gymId': instance.gymId,
      'gymName': instance.gymName,
      'workoutsCount': instance.workoutsCount,
      'racha': instance.racha,
      'followersCount': instance.followersCount,
      'followingCount': instance.followingCount,
      'sharedTemplatesWithAthletes': instance.sharedTemplatesWithAthletes,
    };
