import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../chat/application/chat_providers.dart';
import '../../../../../chat/domain/media_type.dart';
import '../../../../../chat/domain/message.dart';
import '../../../../../profile/application/user_public_profile_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'chat_message_bubble.dart';

/// Panel derecho del split-pane: header con el otro user + lista invertida
/// de mensajes + composer de texto + foto + video (V3, 2026-07-01).
///
/// V3 upgrade: el botón "Adjuntar" abre un bottom sheet con "Foto" / "Video".
/// El picker respectivo (`pickImage` / `pickVideo`) devuelve el XFile, se
/// sube vía [ChatMediaUploadServiceWeb] y se postea el mensaje con `mediaUrl`
/// + `mediaType`. Durante el upload el composer se deshabilita y muestra un
/// `LinearProgressIndicator` con la fracción real que devuelve Storage.
/// Videos se renderean inline en la burbuja usando el mismo
/// `FirebaseStorageVideoPlayer` que mobile, para mantener UX consistente.
class ChatDetailPane extends ConsumerStatefulWidget {
  const ChatDetailPane({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatDetailPane> createState() => _ChatDetailPaneState();
}

class _ChatDetailPaneState extends ConsumerState<ChatDetailPane> {
  final _composerCtrl = TextEditingController();
  bool _sending = false;
  bool _uploading = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    // Marca el chat como leído cuando se abre. Best-effort: si falla
    // (red caída, etc.) el badge de unread quedará vivo hasta el próximo
    // intento — preferible a hacer crashear el pane.
    _markAsReadBestEffort();
  }

  @override
  void didUpdateWidget(ChatDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el PF cambia de chat sin salir del pane, re-marcamos el nuevo
    // como leído.
    if (oldWidget.chatId != widget.chatId) {
      _markAsReadBestEffort();
    }
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }

  Future<void> _markAsReadBestEffort() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markAsRead(chatId: widget.chatId, uid: uid);
    } catch (_) {
      // Silencioso — el badge persiste si la red falla, no es crítico.
    }
  }

  Future<void> _send() async {
    final text = _composerCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(
            chatId: widget.chatId,
            senderId: uid,
            text: text,
          );
      _composerCtrl.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No pudimos enviar el mensaje. Reintentá.'), // i18n: Fase W2
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// V2 (foto) + V3 (video): abre un menú Foto/Video y delega en
  /// [_pickAndSendMedia] con el [MediaType] elegido. Mismo patrón que el
  /// chat mobile — un solo entrypoint desde el composer.
  Future<void> _openAttachMenu() async {
    if (_uploading || _sending) return;
    final palette = AppPalette.of(context);
    final choice = await showModalBottomSheet<MediaType>(
      context: context,
      backgroundColor: palette.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('chat_composer_attach_menu_photo'),
              leading: Icon(TreinoIcon.image, color: palette.textPrimary),
              title: Text(
                'Foto', // i18n: Fase W2
                style: GoogleFonts.barlow(color: palette.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(MediaType.image),
            ),
            ListTile(
              key: const Key('chat_composer_attach_menu_video'),
              leading: Icon(TreinoIcon.play, color: palette.textPrimary),
              title: Text(
                'Video', // i18n: Fase W2
                style: GoogleFonts.barlow(color: palette.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(MediaType.video),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _pickAndSendMedia(choice);
  }

  /// Corre el pick + upload + send de una media (foto o video). Handler
  /// agnóstico usado por el menú del composer.
  Future<void> _pickAndSendMedia(MediaType mediaType) async {
    if (_uploading || _sending) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final picker = ImagePicker();
    // On web, imageQuality is ignored by the platform but harmless — mobile
    // path resizes to ~80% quality which cuts network cost noticeably. We
    // keep the arg for parity.
    final XFile? file;
    if (mediaType == MediaType.image) {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
    } else {
      file = await picker.pickVideo(source: ImageSource.gallery);
    }
    if (file == null || !mounted) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final uploadService = ref.read(chatMediaUploadServiceProvider);
      final mediaUrl = await uploadService.upload(
        file.path,
        chatId: widget.chatId,
        mediaType: mediaType,
        onProgress: (fraction) {
          if (mounted) setState(() => _uploadProgress = fraction);
        },
      );

      if (!mounted) return;

      await ref.read(chatRepositoryProvider).sendMessage(
            chatId: widget.chatId,
            senderId: uid,
            mediaUrl: mediaUrl,
            mediaType: mediaType,
          );
    } catch (e, st) {
      developer.log(
        'chat web media upload/send failed',
        name: 'chat',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        final label = mediaType == MediaType.image ? 'la foto' : 'el video';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No pudimos enviar $label. Reintentá.', // i18n: Fase W2
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final currentUid = ref.watch(currentUidProvider);
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));

    return Container(
      color: palette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(chatId: widget.chatId),
          const Divider(height: 1),
          Expanded(
            child: messagesAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => Center(
                child: Text(
                  'No pudimos cargar los mensajes.', // i18n: Fase W2
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ),
              data: (messages) => _MessagesList(
                messages: messages,
                currentUid: currentUid ?? '',
              ),
            ),
          ),
          const Divider(height: 1),
          if (_uploading)
            LinearProgressIndicator(
              value: _uploadProgress > 0 ? _uploadProgress : null,
              minHeight: 2,
              color: palette.accent,
              backgroundColor: palette.bgCard,
            ),
          _Composer(
            controller: _composerCtrl,
            sending: _sending || _uploading,
            onSend: _send,
            onAttach: _openAttachMenu,
            palette: palette,
          ),
        ],
      ),
    );
  }
}

/// Header del pane derecho — avatar + displayName del otro user.
/// Resuelve `otherUid` desde el chat document para evitar duplicar la
/// lógica con el row de la lista (cada uno hace su `_otherUidOf`).
class _Header extends ConsumerWidget {
  const _Header({required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);
    final chatsAsync = ref.watch(chatsForCurrentUserProvider);
    final otherUid = chatsAsync.maybeWhen(
      data: (chats) {
        for (final c in chats) {
          if (c.chatId != chatId) continue;
          final others = c.members.where((m) => m != uid).toList();
          if (others.isNotEmpty) return others.first;
          return c.members.isNotEmpty ? c.members.first : null;
        }
        return null;
      },
      orElse: () => null,
    );

    final pubAsync = otherUid != null
        ? ref.watch(userPublicProfileProvider(otherUid))
        : const AsyncValue.data(null);

    return Container(
      color: palette.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: palette.bg,
            backgroundImage: pubAsync.maybeWhen(
              data: (p) => (p?.avatarUrl != null && p!.avatarUrl!.isNotEmpty)
                  ? NetworkImage(p.avatarUrl!)
                  : null,
              orElse: () => null,
            ),
            child: pubAsync.maybeWhen(
              data: (p) =>
                  (p?.avatarUrl == null || (p?.avatarUrl ?? '').isEmpty)
                      ? Text(
                          (p?.displayName ?? '?').isNotEmpty
                              ? (p?.displayName ?? '?')[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: palette.textMuted,
                          ),
                        )
                      : null,
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pubAsync.maybeWhen(
                data: (p) => p?.displayName ?? 'Usuario eliminado',
                orElse: () => '…',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({required this.messages, required this.currentUid});

  final List<Message> messages;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      final palette = AppPalette.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sin mensajes todavía. Escribí el primero abajo.', // i18n: Fase W2
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      // `watchMessages` viene DESC por createdAt — el índice 0 es el más
      // nuevo. `reverse: true` lo pinta abajo, sin tener que invertir la
      // lista en memoria.
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final hasMedia = m.mediaUrl != null && m.mediaUrl!.isNotEmpty;
        final isImage = hasMedia && m.mediaType == MediaType.image;
        final isVideo = hasMedia && m.mediaType == MediaType.video;
        return ChatMessageBubble(
          key: ValueKey(m.id),
          text: m.text,
          isOwn: m.senderId == currentUid,
          createdAt: m.createdAt,
          // V3 (2026-07-01): imagen y video inline. Placeholder queda solo
          // para mediaType desconocido (defensivo).
          imageUrl: isImage ? m.mediaUrl : null,
          videoUrl: isVideo ? m.mediaUrl : null,
          mediaPlaceholderLabel:
              hasMedia && !isImage && !isVideo ? _mediaLabel(m) : null,
        );
      },
    );
  }

  /// Label placeholder para media que NO renderea inline. En V3 solo se
  /// llega acá si `mediaType == null` (defensivo — no debería pasar en la
  /// práctica porque el rule de Firestore exige mediaType cuando hay
  /// mediaUrl). Foto y video renderean inline via [ChatMessageBubble].
  String _mediaLabel(Message m) {
    return switch (m.mediaType) {
      MediaType.video =>
        '🎥 Video', // never reached in V3 (video renders inline)
      MediaType.image =>
        '📷 Foto', // never reached in V3 (image renders inline)
      null => '📎 Adjunto', // i18n: Fase W2 — defensive
    };
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    required this.palette,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  /// Handler del botón "Adjuntar". V2 (2026-07-01): abre el picker de
  /// imágenes del navegador. `null` = deshabilitado (mientras hay upload en
  /// curso). Video sigue diferido a V3.
  final VoidCallback onAttach;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botón "Adjuntar" — V2 habilitado (foto). Se deshabilita mientras
          // hay upload o send en curso para evitar dobles envíos.
          Tooltip(
            message: 'Adjuntar foto', // i18n: Fase W2
            child: IconButton(
              key: const Key('chat_composer_attach_button'),
              icon: Icon(
                TreinoIcon.attach,
                size: 20,
                color: sending
                    ? palette.textMuted.withValues(alpha: 0.4)
                    : palette.accent,
              ),
              onPressed: sending ? null : onAttach,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const Key('chat_composer_field'),
              controller: controller,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              enabled: !sending,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Escribí un mensaje…', // i18n: Fase W2
                hintStyle: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                filled: true,
                fillColor: palette.bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('chat_send_button'),
            icon: sending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  )
                : Icon(
                    TreinoIcon.send,
                    size: 20,
                    color: palette.accent,
                  ),
            onPressed: sending ? null : onSend,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
