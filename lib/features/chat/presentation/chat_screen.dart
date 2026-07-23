import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/chat_media_send_controller.dart';
import '../application/chat_providers.dart';
import '../domain/media_type.dart';
import '../domain/message.dart';
import 'chat_image_bubble.dart';
import 'chat_video_bubble.dart';

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

  // Upload state (progress bar + disabled composer) ya no vive acá: lo
  // expone chatMediaSendControllerProvider(chatId), que sobrevive al dispose
  // de esta pantalla (issue #435).

  @override
  void initState() {
    super.initState();
    // REQ-CHATUNREAD-007: mark this conversation read once it's on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
  }

  /// Records the current user's read position for this chat. Best-effort —
  /// a failure must never break the screen (REQ-CHATUNREAD-007).
  Future<void> _markAsRead() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markAsRead(chatId: widget.chatId, uid: uid);
    } catch (e, st) {
      developer.log('markAsRead failed',
          name: 'chat', error: e, stackTrace: st);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _mediaSendInFlight =>
      ref.read(chatMediaSendControllerProvider(widget.chatId)).uploading;

  Future<void> _onSend() async {
    if (_sending || _mediaSendInFlight) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final currentUid = ref.read(currentUidProvider);
    if (currentUid == null) return;

    setState(() => _sending = true);
    // Capturados antes del await (mismo criterio que _onAttach / issue #435):
    // el envío pertenece a ESTE chat y `ref` no se puede usar una vez que la
    // pantalla murió, pero el mensaje igual salió y el evento corresponde.
    final chatId = widget.chatId;
    final repository = ref.read(chatRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);
    try {
      await repository.sendMessage(
        chatId: chatId,
        senderId: currentUid,
        text: text,
      );
      analytics.logChatMessageSent(chatId: chatId, senderId: currentUid);
      // #501: el await pudo sobrevivir a la pantalla (back, deep-link,
      // logout). Tocar el controller ya disposed tira "used after being
      // disposed" y el catch de abajo lo reporta como envío fallido cuando en
      // realidad salió.
      if (!mounted) return;
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
          SnackBar(
            content: Text(AppL10n.of(context).chatScreenSendError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onAttach() async {
    if (_sending || _mediaSendInFlight) return;
    final l10n = AppL10n.of(context);
    // Capturado antes de los awaits: el envío pertenece a ESTE chat pase lo
    // que pase con la pantalla mientras el sheet/picker están abiertos.
    final chatId = widget.chatId;
    final picked = await showModalBottomSheet<_PickChoice>(
      context: context,
      builder: (_) => _AttachSheet(l10n: l10n),
    );
    if (picked == null || !mounted) return;

    final currentUid = ref.read(currentUidProvider);
    if (currentUid == null) return;

    final picker = ImagePicker();
    XFile? file;
    MediaType mediaType;

    if (picked == _PickChoice.image) {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      mediaType = MediaType.image;
    } else {
      file = await picker.pickVideo(source: ImageSource.gallery);
      mediaType = MediaType.video;
    }

    if (file == null || !mounted) return;

    // Fire-and-forget A PROPÓSITO (issue #435): el controller vive en el
    // ProviderContainer y completa upload+send aunque esta pantalla muera.
    // Errores, cleanup de huérfanos y aviso al usuario son responsabilidad
    // del controller (snackbar por el ScaffoldMessenger root).
    unawaited(
      ref.read(chatMediaSendControllerProvider(chatId).notifier).sendMedia(
            localPath: file.path,
            senderId: currentUid,
            mediaType: mediaType,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));
    final currentUid = ref.watch(currentUidProvider);
    final pubAsync = ref.watch(userPublicProfileProvider(widget.otherUid));
    final mediaSend = ref.watch(chatMediaSendControllerProvider(widget.chatId));

    // REQ-CHATUNREAD-007: re-mark as read when a new message arrives while
    // the screen is open, so the badge doesn't re-appear.
    ref.listen(messagesProvider(widget.chatId), (_, __) => _markAsRead());

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          tooltip: l10n.commonBack,
          // Opened from a push the deep-link uses context.go() (replaces the
          // stack), so there's nothing to pop — fall back to the chat inbox
          // instead of a dead button.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/feed/messages'),
        ),
        title: pubAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Text(
            l10n.chatScreenTitleFallback,
            style: TextStyle(color: palette.textPrimary, fontSize: 16),
          ),
          data: (pub) {
            // When userPublicProfiles/{uid} is deleted, pub is null →
            // show "Usuario eliminado" per ADR-ACCDEL-005.
            final name = pub?.displayName ?? l10n.chatListDeletedUser;
            final avatar = pub?.avatarUrl;
            return Row(
              children: [
                Semantics(
                  image: true,
                  label: l10n.a11yAvatarLabel(name),
                  child: PostAvatar(
                    authorDisplayName: name,
                    authorAvatarUrl: avatar,
                    size: 36,
                  ),
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
                      l10n.chatScreenLoadError,
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
            if (mediaSend.uploading)
              LinearProgressIndicator(
                value: mediaSend.progress > 0 ? mediaSend.progress : null,
                color: palette.accent,
                backgroundColor: palette.bgCard,
              ),
            _Composer(
              controller: _textController,
              sending: _sending || mediaSend.uploading,
              onSend: _onSend,
              onAttach: _onAttach,
              palette: palette,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

/// Routes to the correct bubble widget based on [message.mediaType].
///
/// - null (text-only) → text bubble (unchanged, REQ-CHATMEDIA-015)
/// - image → [ChatImageBubble]
/// - video → [ChatVideoBubble]
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
    final mediaType = message.mediaType;

    // Media bubbles: image or video — skip the text-bubble container.
    if (mediaType == MediaType.image) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChatImageBubble(message: message),
        ),
      );
    }

    if (mediaType == MediaType.video) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChatVideoBubble(message: message),
        ),
      );
    }

    // Text-only bubble — original implementation, unchanged.
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
    required this.onAttach,
    required this.palette,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button.
          IconButton(
            onPressed: sending ? null : onAttach,
            tooltip: l10n.chatAttachMediaLabel,
            icon: Icon(
              TreinoIcon.attach,
              color: sending ? palette.textMuted : palette.textMuted,
            ),
          ),
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
                  hintText: l10n.chatScreenComposerHint,
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
                ? Semantics(
                    label: l10n.chatSendingA11y,
                    enabled: false,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: palette.accent),
                    ),
                  )
                : Icon(TreinoIcon.send, color: palette.accent),
            tooltip: sending ? l10n.chatSendingA11y : l10n.chatScreenSendLabel,
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the attach button.
class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.l10n});

  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: Icon(TreinoIcon.image, color: palette.textPrimary),
            title: Text(l10n.chatPickImageLabel,
                style: TextStyle(color: palette.textPrimary)),
            onTap: () => Navigator.of(context).pop(_PickChoice.image),
          ),
          ListTile(
            leading: Icon(TreinoIcon.video, color: palette.textPrimary),
            title: Text(l10n.chatPickVideoLabel,
                style: TextStyle(color: palette.textPrimary)),
            onTap: () => Navigator.of(context).pop(_PickChoice.video),
          ),
        ],
      ),
    );
  }
}

enum _PickChoice { image, video }

class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.chat, color: palette.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              l10n.chatListEmptyTitle,
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
