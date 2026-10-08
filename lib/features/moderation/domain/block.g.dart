// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BlockImpl _$$BlockImplFromJson(Map<String, dynamic> json) => _$BlockImpl(
      id: json['id'] as String,
      blockerUid: json['blockerUid'] as String,
      blockedUid: json['blockedUid'] as String,
      members:
          (json['members'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$BlockImplToJson(_$BlockImpl instance) =>
    <String, dynamic>{
      'blockerUid': instance.blockerUid,
      'blockedUid': instance.blockedUid,
      'members': instance.members,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };
