import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_motion.dart';
import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
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
/// contains uid`.
class ChatListPane extends ConsumerWidget {
  const ChatListPane({super.key, required this.selectedChatId});

  /// chatId actualmente seleccionado, para resaltar la row activa.
  final String? selectedChatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);
    final chatsAsync = ref.watch(chatsForCurrentUserProvider);

    return Container(
      color: palette.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              'CHAT', // i18n: Fase W2
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.4,
                color: palette.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: chatsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _ErrorState(),
              data: (chats) {
                if (chats.isEmpty) return const _EmptyListState();
                if (uid == null) return const SizedBox.shrink();
                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return _ChatRow(
                      chat: chat,
                      currentUid: uid,
                      isSelected: chat.chatId == selectedChatId,
                    );
                  },
                );
              },
            ),
          ),
        ],
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

  /// Resuelve el otro miembro del chat 1:1. Defensivo: si por algún motivo
  /// el chat tiene > 2 members (group chat futuro, no soportado hoy) o solo
  /// 1 (self-chat por bug), devolvemos el primer no-self con fallback al
  /// primer member para nunca crashear el render.
  String _otherUidOf(Chat c, String selfUid) {
    final others = c.members.where((m) => m != selfUid).toList();
    if (others.isNotEmpty) return others.first;
    return c.members.isNotEmpty ? c.members.first : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final otherUid = _otherUidOf(chat, currentUid);
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

class _EmptyListState extends StatelessWidget {
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Todavía no tenés conversaciones.\nLos chats aparecen cuando un alumno te escribe.', // i18n: Fase W2
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
}

class _ErrorState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        'No pudimos cargar tus chats.', // i18n: Fase W2
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
