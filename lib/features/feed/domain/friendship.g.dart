// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friendship.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FriendshipImpl _$$FriendshipImplFromJson(Map<String, dynamic> json) =>
    _$FriendshipImpl(
      id: json['id'] as String,
      uidA: json['uidA'] as String,
      uidB: json['uidB'] as String,
      status: $enumDecode(_$FriendshipStatusEnumMap, json['status']),
      requesterId: json['requesterId'] as String,
      members:
          (json['members'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$FriendshipImplToJson(_$FriendshipImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'uidA': instance.uidA,
      'uidB': instance.uidB,
      'status': _$FriendshipStatusEnumMap[instance.status]!,
      'requesterId': instance.requesterId,
      'members': instance.members,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$FriendshipStatusEnumMap = {
  FriendshipStatus.pending: 'pending',
  FriendshipStatus.accepted: 'accepted',
};
