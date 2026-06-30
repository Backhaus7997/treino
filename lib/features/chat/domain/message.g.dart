// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MessageImpl _$$MessageImplFromJson(Map<String, dynamic> json) =>
    _$MessageImpl(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      text: json['text'] as String? ?? '',
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: _mediaTypeFromJson(json['mediaType']),
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$MessageImplToJson(_$MessageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'senderId': instance.senderId,
      'text': instance.text,
      'mediaUrl': instance.mediaUrl,
      'mediaType': _mediaTypeToJson(instance.mediaType),
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };
