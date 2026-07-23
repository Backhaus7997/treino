import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_motion.dart';
import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../chat/application/chat_providers.dart';
import '../../../../../chat/domain/chat.dart';
import '../../../../../profile/application/user_public_profile_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../widgets/coach_hub_widgets.dart';
import '../chat_section_screen.dart' show selectedChatIdProvider;

/// Panel izquierdo del split-pane: lista de conversaciones del PF.
///
/// Reusa 100% el data layer mobile (`chatsForCurrentUserProvider` +
/// `userPublicProfileProvider`) — el PF logueado en web ve sus mismos chats
/// que en mobile porque la query Firestore es `chats where members array-
/// contains uid`. La búsqueda es puramente de cliente: filtra la lista ya
/// cargada por el stream, sin ninguna query nueva a Firestore.
class ChatListPane extends ConsumerStatefulWidget {
  const ChatListPane({super.key, required this.selectedChatId});

  /// chatId actualmente seleccionado, para resaltar la row activa.
  final String? selectedChatId;

  @override
  ConsumerState<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends ConsumerState<ChatListPane> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);
    final chatsAsync = ref.watch(chatsForCurrentUserProvider);

    return Container(
      color: palette.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s18,
              AppSpacing.s20,
              AppSpacing.s12,
            ),
            child: TextField(
              key: const Key('chat_search_field'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: AppFonts.w400,
                fontSize: 13,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar conversación', // i18n: Fase W2
                hintStyle: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontWeight: AppFonts.w400,
                  fontSize: 13,
                  color: palette.textMuted,
                ),
                prefixIcon: Icon(
                  TreinoIcon.search,
                  size: 18,
                  color: palette.textMuted,
                ),
                filled: true,
                fillColor: palette.bg,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.s12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TreinoStateSwitcher(
              childKey: ValueKey(_stateKey(chatsAsync)),
              child: chatsAsync.when(
                loading: () => const _ChatListSkeleton(),
                error: (_, __) => const TreinoEmptyState(
                  icon: TreinoIcon.errorState,
                  title: 'No pudimos cargar tus chats.', // i18n: Fase W2
                ),
                data: (chats) {
                  if (chats.isEmpty) {
                    return const TreinoEmptyState(
                      icon: TreinoIcon.chatEmpty,
                      title:
                          'Todavía no tenés conversaciones.', // i18n: Fase W2
                      description:
                          'Los chats aparecen cuando un alumno te escribe.', // i18n: Fase W2
                    );
                  }
                  if (uid == null) return const SizedBox.shrink();

                  final filtered = _filterChats(chats, _query, uid);
                  if (filtered.isEmpty) {
                    return const TreinoEmptyState(
                      icon: TreinoIcon.chatEmpty,
                      title: 'Sin resultados', // i18n: Fase W2
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final chat = filtered[index];
                      return _ChatRow(
                        chat: chat,
                        currentUid: uid,
                        isSelected: chat.chatId == widget.selectedChatId,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Filtro de cliente sobre la lista ya cargada por el stream: sin nueva
  /// query Firestore ni provider de backend nuevo. Matchea por el
  /// `displayName` resuelto del otro miembro (ya cacheado por
  /// `userPublicProfileProvider`, el mismo provider que consume `_ChatRow`)
  /// o por el texto del último mensaje, case-insensitive.
  List<Chat> _filterChats(List<Chat> chats, String query, String currentUid) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return chats;

    return chats.where((chat) {
      final preview = (chat.lastMessageText ?? '').toLowerCase();
      if (preview.contains(normalized)) return true;

      final otherUid = _resolveOtherUid(chat, currentUid);
      final pub = ref.watch(userPublicProfileProvider(otherUid));
      final displayName = (pub.valueOrNull?.displayName ?? '').toLowerCase();
      return displayName.contains(normalized);
    }).toList();
  }

  /// Discrimina el estado actual del stream para [TreinoStateSwitcher].
  static String _stateKey(AsyncValue<List<Chat>> chatsAsync) {
    if (chatsAsync.hasError) return 'error';
    if (chatsAsync.isLoading && !chatsAsync.hasValue) return 'loading';
    return 'data';
  }
}

/// Resuelve el otro miembro del chat 1:1. Defensivo: si por algún motivo el
/// chat tiene > 2 members (group chat futuro, no soportado hoy) o solo 1
/// (self-chat por bug), devolvemos el primer no-self con fallback al primer
/// member para nunca crashear el render.
String _resolveOtherUid(Chat chat, String selfUid) {
  final others = chat.members.where((m) => m != selfUid).toList();
  if (others.isNotEmpty) return others.first;
  return chat.members.isNotEmpty ? chat.members.first : '';
}

/// Skeleton de carga de la lista de chats — columna de rows placeholder
/// (avatar circular + 2 barras de texto) envuelta en [TreinoShimmer], en vez
/// del `CircularProgressIndicator` seco anterior.
class _ChatListSkeleton extends StatelessWidget {
  const _ChatListSkeleton();

  static const _placeholderCount = 7;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: ListView.builder(
        key: const Key('chat_list_skeleton'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        itemCount: _placeholderCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s18,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: palette.bg),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 12,
                      decoration: BoxDecoration(
                        color: palette.bg,
                        borderRadius: BorderRadius.circular(AppRadius.sm / 3),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.hairline),
                    Container(
                      width: 180,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.bg,
                        borderRadius: BorderRadius.circular(AppRadius.sm / 3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  const _ChatRow({
    required this.chat,
    required this.currentUid,
    required this.isSelected,
  });

  final Chat chat;
  final String currentUid;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final focusTokens = TreinoFocusTokens.of(context);
    final otherUid = _resolveOtherUid(chat, currentUid);
    final pubAsync = ref.watch(userPublicProfileProvider(otherUid));
    final hasUnread = chatHasUnread(chat, currentUid);
    final transparent = palette.bgCard.withValues(alpha: 0);

    return TreinoInteractiveState(
      key: Key('chat_row_${chat.chatId}'),
      onTap: () {
        ref.read(selectedChatIdProvider.notifier).state = chat.chatId;
      },
      builder: (ctx, states) {
        // Selección gana sobre hover/pressed; hover reusa `borderHover`
        // (token ya pensado para overlays sutiles de interacción).
        final Color bg;
        if (isSelected) {
          bg = palette.bg;
        } else if (states.hovered || states.pressed) {
          bg = palette.borderHover;
        } else {
          bg = transparent;
        }

        return AnimatedContainer(
          key: Key('chat_row_container_${chat.chatId}'),
          duration: AppMotion.resolve(ctx, AppMotion.fast),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: isSelected ? palette.accent : transparent,
                width: 3,
              ),
            ),
            // Anillo de foco de teclado — mismo patrón que
            // filter_chips.dart (ADR-SH-002, remediación CRITICAL-2 verify
            // ronda 2): sin esto la row no da feedback visual al navegar
            // con Tab, rompiendo accesibilidad de teclado.
            boxShadow: states.focused
                ? [
                    BoxShadow(
                      color: focusTokens.ring.withValues(alpha: 0.5),
                      spreadRadius: TreinoFocusTokens.ringWidth,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s18,
            vertical: AppSpacing.s14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: palette.bgCard,
                backgroundImage: pubAsync.maybeWhen(
                  data: (p) =>
                      (p?.avatarUrl != null && p!.avatarUrl!.isNotEmpty)
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
                              style: TextStyle(
                                fontFamily: AppFonts.barlowCondensed,
                                fontWeight: AppFonts.w700,
                                fontSize: 16,
                                color: palette.textMuted,
                              ),
                            )
                          : null,
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pubAsync.maybeWhen(
                              data: (p) =>
                                  p?.displayName ?? 'Usuario eliminado',
                              orElse: () => '…',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.barlow,
                              fontWeight:
                                  hasUnread ? AppFonts.w700 : AppFonts.w600,
                              fontSize: 14,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (chat.lastMessageAt != null) ...[
                          const SizedBox(width: AppSpacing.hairline),
                          Text(
                            _formatTimestamp(chat.lastMessageAt!),
                            style: TextStyle(
                              fontFamily: AppFonts.barlow,
                              fontWeight: AppFonts.w400,
                              fontSize: 11,
                              color: hasUnread
                                  ? palette.accent
                                  : palette.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.hairline),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (chat.lastMessageText ?? '').isEmpty
                                ? 'Sin mensajes todavía' // i18n: Fase W2
                                : chat.lastMessageText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.barlow,
                              fontWeight:
                                  hasUnread ? AppFonts.w600 : AppFonts.w400,
                              fontSize: 12,
                              color: hasUnread
                                  ? palette.textPrimary
                                  : palette.textMuted,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: AppSpacing.hairline),
                          Container(
                            key: Key('chat_row_unread_badge_${chat.chatId}'),
                            width: AppSpacing.s8,
                            height: AppSpacing.s8,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Hoy → solo hora `HH:mm`. Esta semana → día abreviado `lun/mar/...`.
  /// Más viejo → `dd/MM`. Sin años porque cabe siempre en ~5 chars.
  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return DateFormat('HH:mm').format(local);
    final daysAgo = now.difference(local).inDays;
    if (daysAgo < 7) return DateFormat('E', 'es').format(local).toLowerCase();
    return DateFormat('dd/MM').format(local);
  }
}
