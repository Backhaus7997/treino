// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ReactionImpl _$$ReactionImplFromJson(Map<String, dynamic> json) =>
    _$ReactionImpl(
      uid: json['uid'] as String,
      type: $enumDecode(_$ReactionTypeEnumMap, json['type']),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$ReactionImplToJson(_$ReactionImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'type': _$ReactionTypeEnumMap[instance.type]!,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$ReactionTypeEnumMap = {
  ReactionType.strong: 'strong',
  ReactionType.fire: 'fire',
  ReactionType.clap: 'clap',
};
