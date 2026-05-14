// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PostImpl _$$PostImplFromJson(Map<String, dynamic> json) => _$PostImpl(
      id: json['id'] as String,
      authorUid: json['authorUid'] as String,
      authorGymId: json['authorGymId'] as String?,
      text: json['text'] as String,
      routineTag: json['routineTag'] == null
          ? null
          : RoutineTag.fromJson(json['routineTag'] as Map<String, dynamic>),
      privacy: $enumDecode(_$PostPrivacyEnumMap, json['privacy']),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$PostImplToJson(_$PostImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'authorUid': instance.authorUid,
      'authorGymId': instance.authorGymId,
      'text': instance.text,
      'routineTag': instance.routineTag?.toJson(),
      'privacy': _$PostPrivacyEnumMap[instance.privacy]!,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$PostPrivacyEnumMap = {
  PostPrivacy.friends: 'friends',
  PostPrivacy.gym: 'gym',
  PostPrivacy.public: 'public',
};
