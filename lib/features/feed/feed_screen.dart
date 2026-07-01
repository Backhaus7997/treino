import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../chat/application/chat_providers.dart';
import '../check_in/application/check_in_providers.dart';
import '../check_in/presentation/check_in_dialog.dart';
import '../gyms/application/gym_providers.dart';
import '../gyms/domain/gym_display_name.dart';
import '../profile/application/user_providers.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/feed_screen_providers.dart';
import 'application/friendship_providers.dart';
import 'application/post_providers.dart';
import 'domain/feed_segment.dart';
import 'domain/post.dart';
import 'presentation/widgets/feed_empty_state.dart';
import 'presentation/widgets/feed_segment_pills.dart';
import 'presentation/widgets/post_card.dart';

/// Session-scoped flag — once the dialog fires during this process lifetime,
/// it should not reappear even on tab switches (ADR-WRS-16).
///
/// Defined at top level (process-lifetime provider) so it persists across
/// multiple `FeedScreen` instances in the same session.
final _checkInDialogShownThisSessionProvider =
    StateProvider<bool>((_) => false);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to after first frame so we have a valid BuildContext for showDialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowCheckIn());
  }

  Future<void> _maybeShowCheckIn() async {
    if (!mounted) return;

    // Session guard: do not show more than once per process lifetime.
    if (ref.read(_checkInDialogShownThisSessionProvider)) return;

    // Auth guard: no uid → skip (unauthenticated users do not get the dialog).
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Fetch today's check-in; provider is already auth-gated.
    final today = await ref.read(todayCheckInProvider.future);

    if (!mounted) return;

    // Check-in guard: already checked in today → do not show.
    if (today != null) return;

    // Mark shown BEFORE awaiting showDialog to prevent race on rapid remounts.
    ref.read(_checkInDialogShownThisSessionProvider.notifier).state = true;

    // Resolve gym info from the user's profile for the dialog copy.
    // DETAIL context (self) — UserProfile has no denormalized gymName, so
    // resolve live via gymByIdProvider. gyms-foundation Phase 3.
    final profile = ref.read(userProfileProvider).valueOrNull;
    final gymId = profile?.gymId;
    final gymName = gymId == null
        ? null
        : gymDisplayNameFromGym(
            await ref.read(gymByIdProvider(gymId).future).catchError(
                  (_) => null,
                ),
          );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => CheckInDialog(
        gymId: gymId,
        gymName: gymName?.isNotEmpty == true ? gymName : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segment = ref.watch(feedSegmentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FeedHeader(),
        const SizedBox(height: 14),
        const FeedSegmentPills(),
        const SizedBox(height: 18),
        Expanded(
          child: switch (segment) {
            FeedSegment.amigos => const _AmigosBody(),
            FeedSegment.gym => const _MiGymBody(),
            FeedSegment.public => const _PublicoBody(),
          },
        ),
      ],
    );
  }
}

class _FeedHeader extends ConsumerWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final uid = ref.watch(currentUidProvider);
    final pendingRequests =
        uid == null ? 0 : ref.watch(pendingRequestCountProvider(uid));
    // REQ-CHATUNREAD-005: count of chats with unread messages for the badge.
    final unreadChats = ref.watch(totalUnreadCountProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Text(
            'FEED',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: pendingRequests > 0
                ? l10n.feedFriendRequestsWithCountA11y(pendingRequests)
                : l10n.feedFriendRequestsA11y,
            child: GestureDetector(
              onTap: () => context.push('/profile/friend-requests'),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        TreinoIcon.bell,
                        size: 20,
                        color: palette.textMuted,
                      ),
                      if (pendingRequests > 0)
                        Positioned(
                          top: -4,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pendingRequests > 9 ? '9+' : '$pendingRequests',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.barlow(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: palette.bg,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: unreadChats > 0
                ? l10n.feedMessagesWithUnreadA11y(unreadChats)
                : l10n.feedMessagesA11y,
            child: GestureDetector(
              onTap: () => context.push('/feed/messages'),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        TreinoIcon.chat,
                        size: 20,
                        color: palette.textMuted,
                      ),
                      if (unreadChats > 0)
                        Positioned(
                          top: -4,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              unreadChats > 99 ? '99+' : '$unreadChats',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.barlow(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: palette.bg,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: l10n.feedSearchA11y,
            child: GestureDetector(
              onTap: () => context.push('/feed/search'),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Center(
                  child: Icon(
                    TreinoIcon.search,
                    size: 20,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: l10n.feedCreatePostA11y,
            child: GestureDetector(
              onTap: () => context.push('/feed/create'),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(TreinoIcon.plus, size: 20, color: palette.bg),
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

/// A scrollable list of [PostCard]s sharing the common feed layout.
Widget _feedPostList(BuildContext context, List<Post> posts) {
  // TODO(pagination): cursor-based pagination deferred (see explore §9)
  return ListView.separated(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.paddingOf(context).bottom,
    ),
    itemCount: posts.length,
    separatorBuilder: (_, __) => const SizedBox(height: 14),
    itemBuilder: (_, i) => PostCard(
      post: posts[i],
      onAuthorTap: () => context.go('/feed/profile/${posts[i].authorUid}'),
    ),
  );
}

/// Wraps an empty/placeholder state in a scrollable so it can still be
/// pulled-to-refresh even when there is nothing to scroll.
Widget _scrollableEmptyState(BuildContext context, Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );
}

/// Shared async resolver for the three feed segments.
///
/// Renders a consistent loading spinner and — critically — an error state
/// that pairs the localized message with a Reintentar CTA. Because the feed
/// providers are [FutureProvider]s they do NOT self-heal, so the retry
/// invalidates [onRetry]'s provider to force a refetch.
class _FeedAsyncBody<T> extends StatelessWidget {
  const _FeedAsyncBody({
    required this.async,
    required this.onRetry,
    required this.onRefresh,
    required this.dataBuilder,
  });

  final AsyncValue<T> async;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, T data) dataBuilder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return async.when(
      data: (data) => Semantics(
        label: l10n.feedPullToRefreshA11y,
        child: RefreshIndicator(
          color: palette.accent,
          onRefresh: onRefresh,
          child: dataBuilder(context, data),
        ),
      ),
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.feedLoadError,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: palette.accent),
                child: Text(l10n.coachRetryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmigosBody extends ConsumerWidget {
  const _AmigosBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FeedAsyncBody<List<Post>>(
      async: ref.watch(myFriendsFeedProvider),
      onRetry: () => ref.invalidate(myFriendsFeedProvider),
      onRefresh: () => ref.refresh(myFriendsFeedProvider.future),
      dataBuilder: (context, posts) {
        if (posts.isEmpty) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(
              message: 'Aún no hay posts de tus amigos',
            ),
          );
        }
        return _feedPostList(context, posts);
      },
    );
  }
}

class _MiGymBody extends ConsumerWidget {
  const _MiGymBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FeedAsyncBody<List<Post>?>(
      async: ref.watch(myGymFeedProvider),
      onRetry: () => ref.invalidate(myGymFeedProvider),
      onRefresh: () => ref.refresh(myGymFeedProvider.future),
      dataBuilder: (context, posts) {
        if (posts == null) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(
              message: 'Todavía no estás en un gym',
            ),
          );
        }
        if (posts.isEmpty) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(
              message: 'Tu gym todavía no tiene posts',
            ),
          );
        }
        return _feedPostList(context, posts);
      },
    );
  }
}

class _PublicoBody extends ConsumerWidget {
  const _PublicoBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _FeedAsyncBody<List<Post>>(
      async: ref.watch(feedPublicProvider),
      onRetry: () => ref.invalidate(feedPublicProvider),
      onRefresh: () => ref.refresh(feedPublicProvider.future),
      dataBuilder: (context, posts) {
        if (posts.isEmpty) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(
              message: 'Aún no hay posts públicos',
            ),
          );
        }
        return _feedPostList(context, posts);
      },
    );
  }
}
