// ignore_for_file: invalid_annotation_target — @JsonKey on a freezed factory
// param is the documented pattern for custom enum (de)serialization (mirrors
// trainer_public_profile.dart).
// ignore: unused_import — Timestamp is used by the generated message.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'media_type.dart';

part 'message.freezed.dart';
part 'message.g.dart';

/// Mensaje dentro de un chat. Doc en `chats/{chatId}/messages/{messageId}`
/// con id auto-generado. Inmutable en MVP (no edit / delete).
///
/// Los campos [mediaUrl] y [mediaType] son opcionales — mensajes de texto
/// existentes deserializan sin cambios (REQ-CHATMEDIA-001, REQ-CHATMEDIA-015).
@freezed
class Message with _$Message {
  const factory Message({
    required String id,
    required String senderId,
    @Default('') String text,
    String? mediaUrl,
    @JsonKey(
      fromJson: _mediaTypeFromJson,
      toJson: _mediaTypeToJson,
    )
    MediaType? mediaType,
    @TimestampConverter() required DateTime createdAt,
  }) = _Message;

  factory Message.fromJson(Map<String, Object?> json) =>
      _$MessageFromJson(json);
}

MediaType? _mediaTypeFromJson(Object? value) {
  if (value == null) return null;
  return MediaTypeX.fromJson(value as String);
}

Object? _mediaTypeToJson(MediaType? mediaType) => mediaType?.toJson();
