import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_shimmer.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/chat_providers.dart'
    show chatsForCurrentUserProvider, chatHasUnread;
import '../domain/chat.dart';

/// Pantalla que lista todos los chats del usuario actual.
///
/// Empty state cuando el usuario todavía no tiene ningún chat creado.
/// Cada row navega al ChatScreen del chat correspondiente.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final chatsAsync = ref.watch(chatsForCurrentUserProvider);
    final currentUid = ref.watch(currentUidProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n.chatListTitle,
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: chatsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(chatsForCurrentUserProvider),
        ),
        data: (chats) {
          if (chats.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: palette.border,
              indent: 76,
            ),
            itemBuilder: (_, i) => _ChatRow(
              chat: chats[i],
              currentUid: currentUid ?? '',
            ),
          );
        },
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

class _ChatRow extends ConsumerWidget {
  const _ChatRow({required this.chat, required this.currentUid});

  final Chat chat;
  final String currentUid;

  String _otherUidOf(Chat c, String selfUid) {
    return c.members.firstWhere((m) => m != selfUid, orElse: () => '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final otherUid = _otherUidOf(chat, currentUid);
    final pubAsync = ref.watch(userPublicProfileProvider(otherUid));
    final hasUnread = currentUid.isNotEmpty && chatHasUnread(chat, currentUid);

    return InkWell(
      onTap: () {
        // Open the chat via the top-level go_router route so it renders
        // full-screen (no nav bar) with a proper background — the same route
        // the athlete-detail MENSAJE button uses.
        context.push('/coach/chat/${chat.chatId}?other=$otherUid');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: pubAsync.when(
          loading: () => _RowSkeleton(palette: palette),
          // Error NO shimmerea: offline → stream error → un barrido infinito
          // quemaría batería y mentiría ("sigue cargando" cuando ya falló).
          error: (_, __) => _RowSkeleton(palette: palette, shimmer: false),
          data: (pub) {
            // When userPublicProfiles/{uid} is deleted (account deletion cascade),
            // pub is null → show "Usuario eliminado" per ADR-ACCDEL-005.
            final name = pub?.displayName ?? l10n.chatListDeletedUser;
            final avatarUrl = pub?.avatarUrl;
            return Row(
              children: [
                PostAvatar(
                  authorDisplayName: name,
                  authorAvatarUrl: avatarUrl,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chat.lastMessageText ?? l10n.chatListStartConversation,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (chat.lastMessageAt != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    _relativeTime(chat.lastMessageAt!, l10n),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (hasUnread) ...[
                  const SizedBox(width: 10),
                  Semantics(
                    label: l10n.chatUnreadA11y,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton({required this.palette, this.shimmer = true});
  final AppPalette palette;

  /// `false` cuando el skeleton se muestra por un estado de error (nada
  /// está cargando) — se propaga a [TreinoShimmer.enabled].
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      enabled: shimmer,
      child: Row(
        children: [
          CircleAvatar(radius: 24, backgroundColor: palette.bgCard),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 14, color: palette.bgCard),
                const SizedBox(height: 8),
                Container(width: 200, height: 12, color: palette.bgCard),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.chatEmpty, color: palette.textMuted, size: 64),
            const SizedBox(height: 18),
            Text(
              l10n.chatListEmptyTitle,
              style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.chatListEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.chatListError,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.chatListRetryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _relativeTime(DateTime createdAt, AppL10n l10n) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return l10n.chatRelativeJustNow;
  if (delta.inHours < 1) return l10n.chatRelativeMinutes(delta.inMinutes);
  if (delta.inDays < 1) return l10n.chatRelativeHours(delta.inHours);
  if (delta.inDays < 7) return l10n.chatRelativeDays(delta.inDays);
  // createdAt is stored in UTC; format the absolute date in the user's local
  // zone so negative-offset regions (e.g. Argentina, UTC-3) don't show the
  // next day for late-evening messages.
  final local = createdAt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m';
}
