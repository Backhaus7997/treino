import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/chat_providers.dart';
import '../domain/message.dart';

/// Pantalla de chat 1-1. Burbujas + textfield + send. Real-time via
/// `messagesProvider(chatId)`.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  final String chatId;
  final String otherUid;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    if (_sending) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final currentUid = ref.read(currentUidProvider);
    if (currentUid == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(
            chatId: widget.chatId,
            senderId: currentUid,
            text: text,
          );
      ref.read(analyticsServiceProvider).logChatMessageSent(
            chatId: widget.chatId,
            senderId: currentUid,
          );
      _textController.clear();
    } catch (e, st) {
      developer.log(
        'sendMessage failed',
        name: 'chat',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos enviar el mensaje. Probá de nuevo.'),
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
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));
    final currentUid = ref.watch(currentUidProvider);
    final pubAsync = ref.watch(userPublicProfileProvider(widget.otherUid));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: pubAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Text(
            'Usuario',
            style: TextStyle(color: palette.textPrimary, fontSize: 16),
          ),
          data: (pub) {
            final name = pub?.displayName ?? 'Usuario';
            final avatar = pub?.avatarUrl;
            return Row(
              children: [
                PostAvatar(
                  authorDisplayName: name,
                  authorAvatarUrl: avatar,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messagesAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: palette.accent),
                ),
                error: (_, __) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No pudimos cargar los mensajes.',
                      style: TextStyle(color: palette.textMuted),
                    ),
                  ),
                ),
                data: (messages) {
                  if (messages.isEmpty) {
                    return _ConversationEmpty(palette: palette);
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      final isMine = msg.senderId == currentUid;
                      return _Bubble(
                        message: msg,
                        isMine: isMine,
                        palette: palette,
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _textController,
              sending: _sending,
              onSend: _onSend,
              palette: palette,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.palette,
  });

  final Message message;
  final bool isMine;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? palette.accent : palette.bgCard,
            borderRadius: radius,
            border: isMine ? null : Border.all(color: palette.border),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              color: isMine ? palette.bg : palette.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: TextField(
                controller: controller,
                style: TextStyle(color: palette.textPrimary, fontSize: 14),
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Escribí un mensaje…',
                  hintStyle: TextStyle(color: palette.textMuted),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                enabled: !sending,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: sending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.accent),
                  )
                : Icon(TreinoIcon.send, color: palette.accent),
            tooltip: 'Enviar',
          ),
        ],
      ),
    );
  }
}

class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.chat, color: palette.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              'Sin mensajes todavía',
              style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mandá el primero para arrancar la conversación.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
