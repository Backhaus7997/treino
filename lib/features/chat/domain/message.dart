// ignore: unused_import — Timestamp is used by the generated message.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'message.freezed.dart';
part 'message.g.dart';

/// Mensaje dentro de un chat. Doc en `chats/{chatId}/messages/{messageId}`
/// con id auto-generado. Inmutable en MVP (no edit / delete).
@freezed
class Message with _$Message {
  const factory Message({
    required String id,
    required String senderId,
    required String text,
    @TimestampConverter() required DateTime createdAt,
  }) = _Message;

  factory Message.fromJson(Map<String, Object?> json) =>
      _$MessageFromJson(json);
}
