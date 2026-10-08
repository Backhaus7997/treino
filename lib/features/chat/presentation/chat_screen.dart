import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/application/follow_providers.dart';
import '../../feed/domain/follow.dart';
import '../../feed/domain/follow_status.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../moderation/domain/report_target_kind.dart';
import '../../moderation/presentation/moderation_actions.dart';
import '../../paywall/application/athlete_entitlement_provider.dart'
    show chatMediaQuotaProvider;
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
        // `chatScreenSendError` dice "Probá de nuevo", y para un bloqueo de
        // moderación eso es consejo falso: el mismo texto falla siempre.
        final copy = e is ModerationBlockedException
            ? AppL10n.of(context).moderationBlockedMessage
            : AppL10n.of(context).chatScreenSendError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copy)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Muestra un aviso del gate de cuota. Local y no por el messenger root: a
  /// diferencia de la falla de envío (#435), acá la pantalla está viva por
  /// construcción — el usuario acaba de tocar el clip.
  void _toastQuota(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// El gate de UX del tope de media de chat (#chat-media-quota).
  ///
  /// **Client-side es UX; server-side es la ley.** El enforcement real vive en
  /// `chatMediaWriteAllowed()` de `storage.rules` y en la CF
  /// `maintainChatMediaQuota*`. Esto sólo existe para no hacerle gastar datos
  /// móviles al usuario en bytes que el servidor va a rebotar igual.
  ///
  /// Los dos chequeos están donde están por un motivo, y no son
  /// intercambiables:
  ///
  ///   • **Cupo agotado, ANTES de abrir la galería.** Si ya no entra nada, no
  ///     hay archivo que pueda elegir que sirva: ofrecerle el picker es
  ///     hacerle perder el tiempo. Es un gate de entrada legítimo porque acá
  ///     NO hay salida adentro — los mensajes son inmutables y la app no tiene
  ///     UI para borrar media de un chat.
  ///   • **Tamaño, DESPUÉS de elegir.** Recién ahí se sabe cuánto pesa. Frenar
  ///     acá es lo que evita el peor desperdicio del flujo: sin esto el usuario
  ///     sube hasta 50 MB de datos móviles para que el servidor los rechace al
  ///     final, cuando ya los pagó él.
  ///
  /// Con cupo PARCIAL no se puede gatear en la entrada: 10 MB libres alcanzan
  /// para una foto y no para un video, y hasta no ver el archivo no se sabe
  /// cuál de los dos es. Por eso después de elegir se chequean los DOS topes
  /// —el del archivo y el del cupo que queda— con mensajes distintos.
  ///
  /// El `quota == null` NO gatea, mismo criterio que `AthleteEntitlement
  /// .unknown`: mientras el read no aterrizó no se sabe, y bloquearle el clip a
  /// alguien que tiene cupo es peor que dejar pasar un tap que el servidor
  /// rebota igual.
  Future<void> _onAttach() async {
    if (_sending || _mediaSendInFlight) return;
    final l10n = AppL10n.of(context);

    final quota = ref.read(chatMediaQuotaProvider).valueOrNull;
    if (quota != null && quota.isFull) {
      _toastQuota(l10n.chatMediaQuotaFull(_mb(quota.maxBytes)));
      return;
    }

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

    // `XFile.length()` y no `File(path).length()`: el chat también se renderiza
    // en el Coach Hub web, donde `dart:io` no existe.
    final bytes = await file.length();
    if (!mounted) return;
    if (quota != null) {
      final isVideo = mediaType == MediaType.video;
      final perFile = isVideo ? quota.maxVideoBytes : quota.maxImageBytes;
      // Los dos mensajes se separan a propósito: «el máximo es 25 MB» y «te
      // quedan 3 MB» le dicen al usuario cosas distintas sobre qué hacer, y un
      // solo mensaje genérico lo dejaría probando con archivos más chicos
      // contra un tope que no se mueve.
      if (bytes >= perFile) {
        _toastQuota(l10n.chatMediaFileTooLarge(_mb(bytes), _mb(perFile)));
        return;
      }
      if (bytes > quota.remainingBytes) {
        _toastQuota(
          l10n.chatMediaQuotaNotEnough(
            _mb(bytes),
            _mb(quota.remainingBytes < 0 ? 0 : quota.remainingBytes),
          ),
        );
        return;
      }
    }

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

    // REQ-FOLLOW-012 — ESPEJO EXACTO de `senderMayPost` en las rules.
    //
    // Escribir lo habilita la arista ENTRANTE: el otro tiene que seguirme a
    // mí. Es al revés de lo que sugiere la intuición, y es la decisión de
    // producto: dejar de seguir a alguien le saca a ESA persona la escritura
    // hacia vos, con una sola acción.
    //
    // La rama del Coach va PRIMERO, igual que en las rules. Y no es
    // decorativa: `athlete_coach_view.dart` y `athlete_detail_screen.dart`
    // empujan `/coach/chat/...`, que renderiza ESTA pantalla, así que sin este
    // escape el entrenador perdería el composer aunque el servidor se lo
    // permita.
    //
    // Mientras carga se asume que SÍ puede escribir. Un falso positivo
    // momentáneo termina en un `permission-denied` recuperable; un falso
    // negativo le tapa el composer a alguien que sí puede, en cada apertura
    // de chat.
    //
    // Eso es lo que este comentario prometía y lo que el código hacía al
    // revés. `valueOrNull` sobre un `AsyncLoading` da null, así que
    // `isCoachChat` daba false, `chat?.isInquiry == true` daba false y
    // `incomingEdge?.status` daba null: los tres términos en false y el
    // composer gris con el cartel de "esta persona tiene que seguirte" en
    // CADA entrada al chat. La única escapatoria era `currentUid == null`,
    // que es justo el caso que no le importa a nadie.
    //
    // Y no era un edge case de cold start: los dos providers son
    // `autoDispose` sin `keepAlive`, así que salir de la pantalla los
    // destruye y cada `ChatScreen` nuevo vuelve a arrancar en `AsyncLoading`.
    final chatAsync = ref.watch(chatByIdProvider(widget.chatId));
    final chat = chatAsync.valueOrNull;
    final isCoachChat = chat?.linkId != null;
    final edgeAsync = currentUid == null
        ? null
        : ref.watch(followEdgeProvider(
            Follow.edgeId(widget.otherUid, currentUid),
          ));
    final incomingEdge = edgeAsync?.valueOrNull;
    // "Ya sé la respuesta", no "la respuesta es que no". `hasValue` es false
    // mientras carga Y ante un error sin valor previo: en los dos casos no
    // sabemos, y no saber no puede leerse como una negativa.
    final gateResuelto = chatAsync.hasValue && (edgeAsync?.hasValue ?? true);
    // Las TRES ramas por las que escapa `senderMayPost` en las reglas
    // (`firestore.rules`): vínculo, pre-consulta, y arista social aceptada.
    //
    // La pre-consulta faltaba, y la asimetría siempre cae para el mismo lado:
    // la app quedaba MÁS ESTRICTA QUE EL SERVIDOR y le tapaba el composer a
    // alguien a quien Firestore le habría aceptado el mensaje. Justo el caso
    // que motiva la feature — consultarle algo a un entrenador ANTES de
    // pedirle el vínculo—, que sin escribir no existe.
    final canWrite = !gateResuelto ||
        isCoachChat ||
        chat?.isInquiry == true ||
        incomingEdge?.status == FollowStatus.accepted ||
        currentUid == null;
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
        title: TreinoStateSwitcher(
          childKey: ValueKey(pubAsync.when(
            loading: () => 'loading',
            error: (_, __) => 'error',
            data: (_) => 'data',
          )),
          child: pubAsync.when(
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Solo el estado (loading/error/empty/data) cross-fadea acá —
              // NO stagger de mensajes: la lista es reverse:true + lazy
              // (ListView.builder), reciclar ítems con TreinoFadeSlideIn los
              // reanimaría en cada scroll (docs/design-system.md).
              child: TreinoStateSwitcher(
                childKey: ValueKey(messagesAsync.when(
                  loading: () => 'loading',
                  error: (_, __) => 'error',
                  data: (messages) => messages.isEmpty ? 'empty' : 'data',
                )),
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
                          ref: ref,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (mediaSend.uploading)
              LinearProgressIndicator(
                value: mediaSend.progress > 0 ? mediaSend.progress : null,
                color: palette.accent,
                backgroundColor: palette.bgCard,
              ),
            // El aviso va ARRIBA del composer, no en su lugar: dejar el campo
            // visible pero apagado explica POR QUÉ no se puede escribir. Si el
            // composer desapareciera, la pantalla se vería rota sin motivo.
            if (!canWrite) _BlockedComposerNotice(palette: palette),
            _Composer(
              controller: _textController,
              sending: _sending || mediaSend.uploading,
              canWrite: canWrite,
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
    required this.ref,
  });

  final Message message;
  final bool isMine;
  final AppPalette palette;

  /// Sólo para disparar `reportContent` desde el long-press — mismo `ref` de
  /// `_ChatScreenState`, no un provider propio.
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final mediaType = message.mediaType;

    // Media bubbles: image or video — skip the text-bubble container.
    if (mediaType == MediaType.image) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChatImageBubble(
            message: message,
            onLongPress: _onReport(context),
          ),
        ),
      );
    }

    if (mediaType == MediaType.video) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChatVideoBubble(
            message: message,
            onLongPress: _onReport(context),
          ),
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
    Widget bubble = Container(
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
          color: isMine
              ? TreinoButtonTokens.foreground(context)
              : palette.textPrimary,
          fontSize: 14,
        ),
      ),
    );

    bubble = _reportable(context, bubble);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: bubble,
      ),
    );
  }

  /// Acción de reporte del long-press, o `null` si el mensaje es propio.
  ///
  /// La consumen las TRES ramas de [build] —texto, imagen y video—, no sólo la
  /// de texto. Mientras el long-press vivió inline al final del método, las
  /// ramas de `MediaType.image` y `MediaType.video` retornaban ANTES de llegar
  /// a él: el contenido de más riesgo del chat —una foto o un video que manda
  /// otra persona— era justamente el único sin forma de reportarse, que es lo
  /// primero que mira la Guideline 1.2 de App Store.
  ///
  /// `null` en los mensajes propios (moderacion-reporte-y-bloqueo): reportarse
  /// a uno mismo no tiene sentido, mismo criterio que el gate `isOwner` de
  /// `PostCard`. Cada burbuja decide CÓMO registrarlo —`ChatImageBubble` por el
  /// `onLongPress` de su `TreinoTappable`, las otras dos con un
  /// `GestureDetector` propio— porque envolver desde afuera un widget que ya
  /// maneja taps hace competir a los recognizers.
  VoidCallback? _onReport(BuildContext context) {
    if (isMine) return null;
    return () => reportContent(
          context,
          ref,
          targetKind: ReportTargetKind.message,
          targetId: message.id,
          targetOwnerUid: message.senderId,
        );
  }

  /// Envuelve la burbuja de TEXTO con el long-press de [_onReport].
  Widget _reportable(BuildContext context, Widget child) {
    final onReport = _onReport(context);
    if (onReport == null) return child;
    return GestureDetector(onLongPress: onReport, child: child);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.canWrite,
    required this.onSend,
    required this.onAttach,
    required this.palette,
  });

  final TextEditingController controller;
  final bool sending;

  /// Espejo de `senderMayPost` en las rules. Se compone con [sending]: el
  /// composer se apaga si hay un envío en vuelo O si no hay permiso.
  final bool canWrite;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final disabled = sending || !canWrite;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button.
          IconButton(
            onPressed: disabled ? null : onAttach,
            tooltip: l10n.chatAttachMediaLabel,
            icon: Icon(TreinoIcon.attach, color: palette.textMuted),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.lg),
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
                enabled: !disabled,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: disabled ? null : onSend,
            // Swap instantáneo (sin TreinoStateSwitcher): enviar es la acción
            // más frecuente del chat — 240ms de cross-fade para una
            // micro-acción rutinaria es más lento que el escalón que le
            // corresponde. Mismo patrón que AuthPillButton.isLoading
            // (auth_pill_button.dart), el hermano del sistema para este
            // mismo gesto de "swap icono ↔ spinner".
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

/// Aviso PERSISTENTE que reemplaza al composer cuando no se puede escribir.
///
/// Persistente y no un snackbar a propósito: el estado dura hasta que la otra
/// persona vuelva a seguirte, así que un aviso que se desvanece dejaría la
/// pantalla mostrando un composer inexistente sin explicación.
///
/// Copy confirmado por el dueño en 4.7. Se eligió el que EXPLICA de qué depende
/// —"esta persona tiene que seguirte"— por sobre las alternativas neutras: es
/// el único que le dice al usuario qué destrabaría la situación. No expone nada
/// que no se vea ya en el perfil de la otra persona.
class _BlockedComposerNotice extends StatelessWidget {
  const _BlockedComposerNotice({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.infoCircle, size: 18, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppL10n.of(context).chatBlockedComposerNotice,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
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
