import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/root_scaffold_messenger.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/media_type.dart';
import 'chat_providers.dart';

/// Estado del envío de media de UN chat (family key = chatId).
@immutable
class ChatMediaSendState {
  const ChatMediaSendState({
    this.uploading = false,
    this.progress = 0,
  });

  /// True mientras hay un upload+send en vuelo para este chat.
  final bool uploading;

  /// Fracción 0..1 subida a Storage — alimenta la barra de progreso del
  /// composer.
  final double progress;

  ChatMediaSendState copyWith({bool? uploading, double? progress}) =>
      ChatMediaSendState(
        uploading: uploading ?? this.uploading,
        progress: progress ?? this.progress,
      );
}

/// Sube un adjunto y crea el mensaje como UNA unidad que vive en el
/// ProviderContainer, no en el State de la pantalla (issue #435 /
/// QA-CHAT-005).
///
/// Antes upload+send corrían dentro del State del chat: al popear la pantalla
/// mid-upload, el `if (!mounted) return` entre las dos fases cortaba DESPUÉS
/// de subir el archivo y ANTES de crear el mensaje — media huérfana en
/// `chatMedia/` y el destinatario nunca recibía nada, sin error ni aviso.
///
/// Contrato:
/// - [Ref.keepAlive] mantiene vivo el notifier hasta que el envío termina,
///   aunque la pantalla que lo disparó ya no exista.
/// - Si el send falla tras un upload exitoso, el objeto subido se borra
///   best-effort ([ChatMediaUploadService.deleteByDownloadUrl]) para no dejar
///   huérfanos.
/// - Toda falla se avisa por el ScaffoldMessenger ROOT
///   ([rootScaffoldMessengerKeyProvider]), que sobrevive la navegación —
///   mismo patrón que ADR-PN-010 y el fix de #430 (PR #468).
///
/// Family por chatId: un envío en vuelo pertenece a SU chat. En el split-pane
/// del Coach Hub el PF puede cambiar de conversación sin desmontar el pane;
/// con el estado keyed acá, el mensaje aterriza en el chat donde se eligió el
/// adjunto y el progreso mostrado es siempre el del chat visible.
class ChatMediaSendController
    extends AutoDisposeFamilyNotifier<ChatMediaSendState, String> {
  @override
  ChatMediaSendState build(String chatId) => const ChatMediaSendState();

  /// Sube [localPath] al chat [arg] y crea el mensaje con la URL resultante.
  ///
  /// Nunca relanza: loguea, limpia el huérfano si corresponde y avisa por el
  /// messenger root. Ignorado si ya hay un envío en vuelo para este chat.
  Future<void> sendMedia({
    required String localPath,
    required String senderId,
    required MediaType mediaType,
  }) async {
    if (state.uploading) return;
    final chatId = arg;
    // Pin del provider durante todo el envío: la pantalla puede morir, el
    // envío no (issue #435). Recién al cerrar el link puede autodisponerse.
    final keepAlive = ref.keepAlive();
    var settled = false;
    state = const ChatMediaSendState(uploading: true);

    String? uploadedUrl;
    try {
      final uploadService = ref.read(chatMediaUploadServiceProvider);
      uploadedUrl = await uploadService.upload(
        localPath,
        chatId: chatId,
        mediaType: mediaType,
        onProgress: (fraction) {
          // Un evento de progreso rezagado no debe tocar un provider ya
          // dispuesto (el stream de snapshots puede emitir en microtasks
          // posteriores al await del task).
          if (!settled) state = state.copyWith(progress: fraction);
        },
      );
      await ref.read(chatRepositoryProvider).sendMessage(
            chatId: chatId,
            senderId: senderId,
            mediaUrl: uploadedUrl,
            mediaType: mediaType,
          );
    } catch (e, st) {
      developer.log(
        'media upload/send failed',
        name: 'chat',
        error: e,
        stackTrace: st,
      );
      await _deleteOrphan(uploadedUrl);
      _notifyFailure();
    } finally {
      settled = true;
      state = const ChatMediaSendState();
      keepAlive.close();
    }
  }

  /// Borra el objeto subido cuando el mensaje no llegó a crearse. Best-effort:
  /// un fallo acá solo se loguea (el aviso al usuario ya salió por el path
  /// principal).
  Future<void> _deleteOrphan(String? url) async {
    if (url == null) return;
    try {
      await ref.read(chatMediaUploadServiceProvider).deleteByDownloadUrl(url);
    } catch (e, st) {
      developer.log(
        'orphan chat media cleanup failed',
        name: 'chat',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Muestra el aviso de falla en el ScaffoldMessenger root — visible aunque
  /// el chat ya no esté en pantalla. No-op en unit tests sin MaterialApp.
  void _notifyFailure() {
    final messenger = ref.read(rootScaffoldMessengerKeyProvider).currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppL10n.of(messenger.context).chatMediaUploadFailed),
      ),
    );
  }
}

/// Ver [ChatMediaSendController]. Watch de la instancia del chat visible para
/// progreso/disable del composer; `.notifier.sendMedia(...)` para disparar.
final chatMediaSendControllerProvider = AutoDisposeNotifierProviderFamily<
    ChatMediaSendController, ChatMediaSendState, String>(
  ChatMediaSendController.new,
);
