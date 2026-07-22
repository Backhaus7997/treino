// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PostImpl _$$PostImplFromJson(Map<String, dynamic> json) => _$PostImpl(
      id: json['id'] as String,
      authorUid: json['authorUid'] as String,
      authorDisplayName: json['authorDisplayName'] as String? ?? 'Anónimo',
      authorAvatarUrl: json['authorAvatarUrl'] as String?,
      authorGymId: json['authorGymId'] as String?,
      text: json['text'] as String,
      routineTag: json['routineTag'] == null
          ? null
          : RoutineTag.fromJson(json['routineTag'] as Map<String, dynamic>),
      privacy: $enumDecode(_$PostPrivacyEnumMap, json['privacy']),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      workoutStats: json['workoutStats'] == null
          ? null
          : WorkoutStats.fromJson(json['workoutStats'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$PostImplToJson(_$PostImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'authorUid': instance.authorUid,
      'authorDisplayName': instance.authorDisplayName,
      'authorAvatarUrl': instance.authorAvatarUrl,
      'authorGymId': instance.authorGymId,
      'text': instance.text,
      'routineTag': instance.routineTag?.toJson(),
      'privacy': _$PostPrivacyEnumMap[instance.privacy]!,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'workoutStats': instance.workoutStats?.toJson(),
    };

const _$PostPrivacyEnumMap = {
  PostPrivacy.friends: 'friends',
  PostPrivacy.gym: 'gym',
  PostPrivacy.public: 'public',
};
