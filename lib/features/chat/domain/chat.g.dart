// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ChatImpl _$$ChatImplFromJson(Map<String, dynamic> json) => _$ChatImpl(
      chatId: json['chatId'] as String,
      members:
          (json['members'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      lastMessageAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['lastMessageAt'], const TimestampConverter().fromJson),
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageSenderId: json['lastMessageSenderId'] as String?,
    );

Map<String, dynamic> _$$ChatImplToJson(_$ChatImpl instance) =>
    <String, dynamic>{
      'chatId': instance.chatId,
      'members': instance.members,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'lastMessageAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.lastMessageAt, const TimestampConverter().toJson),
      'lastMessageText': instance.lastMessageText,
      'lastMessageSenderId': instance.lastMessageSenderId,
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
