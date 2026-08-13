// ignore: unused_import — Timestamp is used by the generated chat.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'chat.freezed.dart';
part 'chat.g.dart';

/// Chat 1-1 entre PF y athlete. Doc en `chats/{chatId}` con id determinístico
/// (`sortedUids.join('_')`) para que ambos miembros resuelvan al mismo doc
/// sin tener que consultar primero.
@freezed
class Chat with _$Chat {
  const factory Chat({
    required String chatId,
    required List<String> members,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? lastMessageAt,
    String? lastMessageText,
    String? lastMessageSenderId,
    @TimestampMapConverter() Map<String, DateTime>? lastRead,

    /// Id del `trainer_links` que respalda este chat, si es un chat de Coach.
    ///
    /// Se expone al cliente porque el gate de escritura del chat social
    /// (REQ-FOLLOW-012) tiene que poder distinguir un chat de Coach: las rules
    /// escapan por `'linkId' in chat` en `senderMayPost`, y si la UI no mira lo
    /// mismo le bloquearía el composer al entrenador aunque el servidor se lo
    /// permita. La validez del link la garantiza `chatCreateOk` al crear el doc
    /// y el pin de inmutabilidad en `chats/update`; acá sólo se lee.
    String? linkId,
  }) = _Chat;

  factory Chat.fromJson(Map<String, Object?> json) => _$ChatFromJson(json);
}
