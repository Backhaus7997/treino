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
    /// Es informativo: NO decide si se puede escribir. Hasta el 2026-10-21
    /// (REQ-FOLLOW-012) `senderMayPost` escapaba por `'linkId' in chat` y la UI
    /// tenía que espejarlo; ese cambio de producto sacó el requisito de follow
    /// y con él el escape. Hoy en un chat existente escriben los dos miembros y
    /// lo único que corta es un bloqueo o [closedAt] — tener `linkId` no abre
    /// ni cierra nada. La validez del link la garantiza `chatCreateOk` al crear
    /// el doc y el pin de inmutabilidad en `chats/update`; acá sólo se lee.
    String? linkId,

    /// Naturaleza del chat cuando NO lo respalda un vínculo formal.
    ///
    /// Hoy el único valor es `'inquiry'`: la PRE-CONSULTA de #637, que un
    /// atleta abre desde el perfil público de un PF para preguntar antes de
    /// comprometerse. Un chat social no lleva el campo.
    ///
    /// Espeja la tercera rama de `chatCreateOk`, que es donde importa: decide
    /// quién puede CREAR el chat. No habilita la escritura posterior — desde
    /// el 2026-10-21 `senderMayPost`/`chatWriterOk` ya no escapan por
    /// `kind == 'inquiry'` ni por `linkId`. Está pineado inmutable en
    /// `chats/update`. Acá sólo se lee — la validez la garantiza el servidor al
    /// crear el doc.
    String? kind,

    /// Cuándo se CERRÓ el chat: el vínculo PF↔alumno del par terminó y no hay
    /// otro vigente. `null` = abierto, que es también como se lee un doc
    /// viejo que no trae el campo.
    ///
    /// Lo escribe sólo una Cloud Function (`syncChatOnTrainerLink`) y las rules
    /// lo tienen pineado en `chats/update`, así que un cliente nunca lo setea.
    /// Cerrado, `senderMayPost` rechaza todo mensaje nuevo y el historial sigue
    /// legible. Si el par se vuelve a vincular, la función borra el campo y el
    /// chat reabre ([isClosed]).
    @TimestampConverter() DateTime? closedAt,

    /// Archivado POR MIEMBRO: `uid → cuándo lo archivó`. Esconde el chat de la
    /// lista principal de ese uid hasta que llega un mensaje posterior
    /// ([isArchivedFor]). Desarchivar borra la clave. Cada miembro sólo puede
    /// escribir la suya (`ownStampOk` en `firestore.rules`).
    @TimestampMapConverter() Map<String, DateTime>? archivedAt,

    /// "Eliminar" POR MIEMBRO: `uid → desde cuándo ve el historial`. Oculta
    /// el chat y los mensajes anteriores sólo para ese uid; si llega un
    /// mensaje nuevo, el chat vuelve desde ahí ([isHiddenFor]). No borra nada
    /// del otro participante: los mensajes son inmutables.
    @TimestampMapConverter() Map<String, DateTime>? hiddenBefore,
  }) = _Chat;

  const Chat._();

  /// Chat de pre-consulta (#637): sin vínculo formal todavía.
  bool get isInquiry => kind == inquiryKind;

  /// El vínculo del par terminó: se lee el historial pero no se puede mandar
  /// nada nuevo (ver [closedAt]).
  bool get isClosed => closedAt != null;

  /// Archivado por [uid] y sin mensajes desde entonces.
  bool isArchivedFor(String uid) => _stampCovers(archivedAt?[uid]);

  /// Eliminado por [uid] y sin mensajes desde entonces.
  bool isHiddenFor(String uid) => _stampCovers(hiddenBefore?[uid]);

  /// Un mensaje posterior a la estampa la vence: así el chat "vuelve solo"
  /// sin que nadie tenga que escribir la entrada de otro miembro.
  bool _stampCovers(DateTime? stamp) {
    if (stamp == null) return false;
    final last = lastMessageAt;
    return last == null || !last.isAfter(stamp);
  }

  /// Valor de [kind] para la pre-consulta. Tiene que coincidir EXACTAMENTE con
  /// el literal de `chatCreateOk` en `firestore.rules` — si divergen, el CTA
  /// abre chats que el backend rechaza.
  static const String inquiryKind = 'inquiry';

  factory Chat.fromJson(Map<String, Object?> json) => _$ChatFromJson(json);
}
