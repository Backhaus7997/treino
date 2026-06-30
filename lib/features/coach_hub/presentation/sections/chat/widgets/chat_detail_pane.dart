import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
/// de mensajes + composer de texto.
///
/// V1 — solo texto. El botón de adjuntar está visible pero deshabilitado
/// con tooltip "Próximamente". Cuando un mensaje del otro lado trae media,
/// se renderea como placeholder "[Foto] / [Video]" arriba del texto para
/// que el PF SEPA que llegó (no se lo escondemos), aunque no pueda verla
/// inline hasta V2.
class ChatDetailPane extends ConsumerStatefulWidget {
  const ChatDetailPane({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatDetailPane> createState() => _ChatDetailPaneState();
}

class _ChatDetailPaneState extends ConsumerState<ChatDetailPane> {
  final _composerCtrl = TextEditingController();
  bool _sending = false;

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
          _Composer(
            controller: _composerCtrl,
            sending: _sending,
            onSend: _send,
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
        return ChatMessageBubble(
          key: ValueKey(m.id),
          text: m.text,
          isOwn: m.senderId == currentUid,
          createdAt: m.createdAt,
          mediaPlaceholderLabel: _mediaLabel(m),
        );
      },
    );
  }

  /// V1: si el mensaje carga media, mostramos un chip "📷 Foto" / "🎥 Video"
  /// arriba del texto. Pintar la media real queda para V2.
  String? _mediaLabel(Message m) {
    if (m.mediaUrl == null || m.mediaUrl!.isEmpty) return null;
    return switch (m.mediaType) {
      MediaType.image => '📷 Foto', // i18n: Fase W2
      MediaType.video => '🎥 Video', // i18n: Fase W2
      null => '📎 Adjunto', // i18n: Fase W2 — defensive
    };
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.palette,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botón "Adjuntar" deshabilitado: señaliza la intención de V2 sin
          // bloquear V1. Tooltip explica.
          Tooltip(
            message: 'Próximamente — fotos y videos', // i18n: Fase W2
            child: IconButton(
              icon: Icon(
                TreinoIcon.attach,
                size: 20,
                color: palette.textMuted.withValues(alpha: 0.4),
              ),
              onPressed: null,
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
