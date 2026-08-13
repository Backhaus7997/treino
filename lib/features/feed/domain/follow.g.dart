// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FollowImpl _$$FollowImplFromJson(Map<String, dynamic> json) => _$FollowImpl(
      id: json['id'] as String,
      followerUid: json['followerUid'] as String,
      followeeUid: json['followeeUid'] as String,
      status: $enumDecode(_$FollowStatusEnumMap, json['status']),
      members:
          (json['members'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$FollowImplToJson(_$FollowImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'followerUid': instance.followerUid,
      'followeeUid': instance.followeeUid,
      'status': _$FollowStatusEnumMap[instance.status]!,
      'members': instance.members,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$FollowStatusEnumMap = {
  FollowStatus.pending: 'pending',
  FollowStatus.accepted: 'accepted',
};
