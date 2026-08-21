import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../feed/application/follow_providers.dart';
import '../../feed/presentation/widgets/feed_empty_state.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/notification_history_providers.dart';
import '../application/notification_router.dart';
import '../domain/notification_history_item.dart';

class NotificationHistoryScreen extends ConsumerStatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  ConsumerState<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends ConsumerState<NotificationHistoryScreen> {
  bool _markScheduled = false;

  void _scheduleMarkSeen(String uid) {
    if (_markScheduled) return;
    _markScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationHistoryRepositoryProvider).markSeen(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid != null) _scheduleMarkSeen(uid);

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final notifications = ref.watch(notificationHistoryProvider);
    final lastSeenAt = ref.watch(notificationLastSeenAtProvider).valueOrNull;
    final pending =
        uid == null ? 0 : ref.watch(pendingFollowRequestCountProvider(uid));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
        ),
        title: Text(
          l10n.notificationHistoryTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: _PendingRequestsBlock(count: pending),
            ),
          Expanded(
            child: notifications.when(
              loading: () => Center(
                key: const Key('notificationHistoryLoading'),
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _NotificationError(
                onRetry: () => ref.invalidate(notificationHistoryProvider),
              ),
              data: (items) => items.isEmpty
                  ? FeedEmptyState(
                      key: const Key('notificationHistoryEmpty'),
                      icon: TreinoIcon.bell,
                      message: l10n.notificationHistoryEmpty,
                    )
                  : ListView.separated(
                      key: const Key('notificationHistoryList'),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _NotificationItem(
                        notification: items[index],
                        unread: notificationIsUnread(
                          items[index],
                          lastSeenAt,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRequestsBlock extends StatelessWidget {
  const _PendingRequestsBlock({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final label = l10n.notificationPendingRequests(count);
    return Semantics(
      key: const Key('notificationPendingRequests'),
      container: true,
      button: true,
      label: label,
      child: TreinoTappable(
        onTap: () => context.go('/feed/friend-requests'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.users, color: palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Icon(TreinoIcon.forward, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationItem extends ConsumerWidget {
  const _NotificationItem({required this.notification, required this.unread});

  final NotificationHistoryItem notification;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final actorUid = notification.actorUid;
    final actor = actorUid == null
        ? null
        : ref.watch(userPublicProfileProvider(actorUid)).valueOrNull;
    final semanticsLabel = '${notification.title}. ${notification.body}';

    return Semantics(
      key: Key('notificationItem-${notification.id}'),
      container: true,
      button: true,
      label: semanticsLabel,
      child: TreinoTappable(
        onTap: () => goDeepLink(context, notification.deepLink),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread
                ? palette.accent.withValues(alpha: 0.08)
                : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: unread
                  ? palette.accent.withValues(alpha: 0.3)
                  : palette.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (actorUid != null) ...[
                PostAvatar(
                  authorDisplayName: actor?.displayName ?? '',
                  authorAvatarUrl: actor?.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(TreinoIcon.bell, color: palette.textMuted, size: 40),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: GoogleFonts.barlow(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.body,
                      style: GoogleFonts.barlow(color: palette.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relativeTime(
                          notification.createdAt, AppL10n.of(context)),
                      style: GoogleFonts.barlow(
                        fontSize: 11,
                        color: palette.textMuted,
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

class _NotificationError extends StatelessWidget {
  const _NotificationError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      key: const Key('notificationHistoryError'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.notificationHistoryError,
            style: GoogleFonts.barlow(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: palette.accent),
            child: Text(l10n.coachRetryLabel),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime createdAt, AppL10n l10n) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return l10n.chatRelativeJustNow;
  if (delta.inHours < 1) return l10n.chatRelativeMinutes(delta.inMinutes);
  if (delta.inDays < 1) return l10n.chatRelativeHours(delta.inHours);
  if (delta.inDays < 7) return l10n.chatRelativeDays(delta.inDays);
  final local = createdAt.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month';
}
