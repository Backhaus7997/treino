import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../chat/application/chat_media_send_controller.dart';
import '../../../../../chat/application/chat_providers.dart';
import '../../../../../chat/domain/media_type.dart';
import '../../../../../chat/domain/message.dart';
import '../../../../../profile/application/user_public_profile_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'avatar_color.dart';
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
  const ChatDetailPane({
    super.key,
    required this.chatId,
    this.peerUid,
    this.peerNameInitial,
  });

  final String chatId;

  /// Peer's uid when the caller already knows it (e.g. the alumno-detail
  /// Chat tab, which is fixed to one athlete). When provided, [_Header]
  /// uses it directly instead of scanning [chatsForCurrentUserProvider] —
  /// skips a cold stream hop that otherwise causes a placeholder flash
  /// ("Usuario eliminado" → "…" → real name) the first time this pane
  /// mounts. `null` preserves the original chat-derived resolution (global
  /// chat section, which doesn't know the peer up front).
  final String? peerUid;

  /// Peer's already-resolved display name when the caller has it warm
  /// (e.g. from the athlete-detail header's own profile watch). Used as
  /// the header's fallback/initial text WHILE [userPublicProfileProvider]
  /// is loading, instead of the generic '…' / 'Usuario eliminado'
  /// placeholders. The live profile value is preferred once it resolves
  /// with a non-empty `displayName` — this is only a warm-start hint.
  final String? peerNameInitial;

  @override
  ConsumerState<ChatDetailPane> createState() => _ChatDetailPaneState();
}

class _ChatDetailPaneState extends ConsumerState<ChatDetailPane> {
  final _composerCtrl = TextEditingController();
  bool _sending = false;

  // Upload state (progress + composer disabled) vive en
  // chatMediaSendControllerProvider(chatId): sobrevive al dispose del pane y
  // a los cambios de chat vía didUpdateWidget (issue #435).

  bool get _mediaSendInFlight =>
      ref.read(chatMediaSendControllerProvider(widget.chatId)).uploading;

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
    if (text.isEmpty || _sending || _mediaSendInFlight) return;
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
    if (_sending || _mediaSendInFlight) return;
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
                style: TextStyle(
                    fontFamily: AppFonts.barlow, color: palette.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(MediaType.image),
            ),
            ListTile(
              key: const Key('chat_composer_attach_menu_video'),
              leading: Icon(TreinoIcon.play, color: palette.textPrimary),
              title: Text(
                'Video', // i18n: Fase W2
                style: TextStyle(
                    fontFamily: AppFonts.barlow, color: palette.textPrimary),
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
    if (_sending || _mediaSendInFlight) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    // Capturado ANTES del picker: didUpdateWidget puede cambiar widget.chatId
    // sin desmontar el pane — el adjunto debe aterrizar en el chat donde el
    // PF lo eligió, no en el que quedó visible (issue #435).
    final chatId = widget.chatId;

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

    // Fire-and-forget A PROPÓSITO (issue #435): el controller vive en el
    // ProviderContainer y completa upload+send aunque el pane muera o cambie
    // de chat. Errores, cleanup de huérfanos y aviso al usuario (snackbar
    // por el ScaffoldMessenger root) son responsabilidad del controller.
    unawaited(
      ref.read(chatMediaSendControllerProvider(chatId).notifier).sendMedia(
            localPath: file.path,
            senderId: uid,
            mediaType: mediaType,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final currentUid = ref.watch(currentUidProvider);
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));
    final mediaSend = ref.watch(chatMediaSendControllerProvider(widget.chatId));

    return Container(
      color: palette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            chatId: widget.chatId,
            peerUid: widget.peerUid,
            peerNameInitial: widget.peerNameInitial,
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: TreinoStateSwitcher(
              childKey: ValueKey(messagesAsync.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (_) => 'data',
              )),
              child: messagesAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: palette.accent),
                ),
                error: (_, __) => Center(
                  child: Text(
                    'No pudimos cargar los mensajes.', // i18n: Fase W2
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
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
          ),
          Divider(height: 1, color: palette.border),
          if (mediaSend.uploading)
            LinearProgressIndicator(
              value: mediaSend.progress > 0 ? mediaSend.progress : null,
              minHeight: 2,
              color: palette.accent,
              backgroundColor: palette.bgCard,
            ),
          _Composer(
            controller: _composerCtrl,
            sending: _sending || mediaSend.uploading,
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
  const _Header({required this.chatId, this.peerUid, this.peerNameInitial});
  final String chatId;

  /// See [ChatDetailPane.peerUid].
  final String? peerUid;

  /// See [ChatDetailPane.peerNameInitial].
  final String? peerNameInitial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);

    // Cuando el caller YA conoce el peer (alumno-detail Chat tab) usamos ese
    // uid directo — evita el hop frío por `chatsForCurrentUserProvider`, que
    // no está warm ahí (issue: name flash). Sin `peerUid` (sección de chat
    // global, que no sabe el peer de antemano) se preserva la derivación
    // original desde el chat.
    String? otherUid = peerUid;
    if (otherUid == null) {
      final chatsAsync = ref.watch(chatsForCurrentUserProvider);
      // `valueOrNull` preserva la lista previa durante reloads/errores
      // transitorios → el header no parpadea a "Usuario eliminado" al cambiar
      // de chat (mismo bug que la lista).
      for (final c in (chatsAsync.valueOrNull ?? const [])) {
        if (c.chatId != chatId) continue;
        final others = c.members.where((m) => m != uid).toList();
        otherUid = others.isNotEmpty
            ? others.first
            : (c.members.isNotEmpty ? c.members.first : null);
        break;
      }
    }

    final pubAsync = otherUid != null
        ? ref.watch(userPublicProfileProvider(otherUid))
        : const AsyncValue.data(null);

    // Nombre a mostrar mientras el perfil vivo está loading/ausente. Con
    // `peerNameInitial` (ya resuelto por el caller, p.ej. el header del
    // alumno-detail) lo mostramos de entrada en vez de '…' /
    // 'Usuario eliminado' — el perfil vivo puede estar más fresco, así que
    // sólo pisa el initial cuando resuelve con un `displayName` no vacío.
    //
    // `_usableName` normaliza '' como "ausente" (igual que `null`) en TODOS
    // los puntos de uso (nombre y avatar) — antes de este fix, `''` se
    // trataba de forma inconsistente: a veces "ausente" (`isNotEmpty`) y a
    // veces se dejaba pasar (`?? '…'` sólo atrapa `null`). Nota: esto es una
    // normalización deliberada vs. el comportamiento pre-fix, donde un
    // `displayName` vivo == '' en el chat global (peerNameInitial null)
    // renderaba el header en blanco — un bug latente, no un comportamiento
    // a preservar. Con la normalización, ese caso ahora cae en 'Usuario
    // eliminado', que es más sensato que un header vacío.
    final resolvedName = pubAsync.maybeWhen(
      data: (p) =>
          _usableName(p?.displayName) ??
          _usableName(peerNameInitial) ??
          'Usuario eliminado', // i18n: Fase W2
      orElse: () => _usableName(peerNameInitial) ?? '…', // i18n: Fase W2
    );

    return Container(
      color: palette.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            // Mockup: avatar de color por usuario (inicial blanca).
            backgroundColor: avatarColorFor(otherUid ?? ''),
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
                          _avatarInitial(p?.displayName),
                          style: const TextStyle(
                            fontFamily: AppFonts.barlowCondensed,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        )
                      : null,
              // Loading/error SIN `peerNameInitial` usable (sección de chat
              // global, o alumno-detail con initial vacío): preserva el
              // círculo vacío — mismo criterio "ausente" que el nombre
              // (`_usableName`), así avatar y nombre nunca se contradicen
              // (nombre '…' con avatar en blanco, nunca con una letra).
              // Loading/error CON `peerNameInitial` usable (alumno-detail
              // Chat tab): la letra debe verse desde el primer frame, igual
              // que el nombre — evita el mismo flash que motivó este fix.
              orElse: () => _usableName(peerNameInitial) == null
                  ? const SizedBox.shrink()
                  : Text(
                      _avatarInitial(null),
                      style: const TextStyle(
                        fontFamily: AppFonts.barlowCondensed,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              resolvedName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.barlow,
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

  /// Letra del avatar: prioriza el `displayName` VIVO del perfil, cae a
  /// [peerNameInitial] (warm-start del caller) y por último a `'?'`. Mismo
  /// orden de prioridad y misma regla de "ausente" (vía [_usableName]) que
  /// [resolvedName] en `build` — avatar y nombre nunca deberían disentir.
  String _avatarInitial(String? liveDisplayName) {
    final name = _usableName(liveDisplayName) ?? _usableName(peerNameInitial);
    // `.characters.first` en vez de `name[0]`: grapheme-cluster safe para
    // emoji/caracteres astrales en el displayName (mismo patrón que
    // `_computeInitials` en `lib/features/home/widgets/home_header.dart`).
    return name != null ? name.characters.first.toUpperCase() : '?';
  }

  /// Normaliza `''` como "ausente" (igual que `null`) — único punto de
  /// verdad para la regla de emptiness usada por [resolvedName] y
  /// [_avatarInitial], así el nombre y la letra del avatar nunca disienten
  /// sobre si un valor cuenta como "hay dato" o no.
  static String? _usableName(String? s) =>
      (s != null && s.isNotEmpty) ? s : null;
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
            style: TextStyle(
              fontFamily: AppFonts.barlow,
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
          // Botón "Adjuntar" — mockup: círculo con "+". Se deshabilita
          // mientras hay upload o send en curso para evitar dobles envíos.
          Tooltip(
            message: 'Adjuntar foto o video', // i18n: Fase W2
            child: TreinoTappable(
              key: const Key('chat_composer_attach_button'),
              onTap: sending ? null : onAttach,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.bg,
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.add,
                  size: 22,
                  color: sending
                      ? palette.textMuted.withValues(alpha: 0.4)
                      : palette.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('chat_composer_field'),
              controller: controller,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              enabled: !sending,
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Escribí un mensaje…', // i18n: Fase W2
                hintStyle: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                filled: true,
                fillColor: palette.bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide(color: palette.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón enviar — mockup: cuadro mint sólido con el avión en el
          // color de fondo. Redondeado, no un IconButton suelto.
          TreinoTappable(
            key: const Key('chat_send_button'),
            onTap: sending ? null : onSend,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sending
                    ? palette.accent.withValues(alpha: 0.5)
                    : palette.accent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.bg,
                      ),
                    )
                  : Icon(TreinoIcon.send, size: 20, color: palette.bg),
            ),
          ),
        ],
      ),
    );
  }
}
