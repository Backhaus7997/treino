import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../core/widgets/motion/treino_state_switcher.dart';
import '../../core/widgets/motion/treino_tappable.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../chat/application/chat_providers.dart';
import '../gym_rankings/presentation/rankings_screen.dart' show RankingsBody;
import '../notifications/application/notification_history_providers.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/feed_screen_providers.dart';
import 'application/feed_pagination_notifier.dart';
import 'application/post_providers.dart';
import 'domain/feed_segment.dart';
import 'domain/post.dart';
import 'presentation/widgets/feed_empty_state.dart';
import 'presentation/widgets/feed_segment_pills.dart';
import 'presentation/widgets/post_card.dart';
import 'presentation/widgets/suggested_users_section.dart';

/// Role-aware Feed tab.
///
/// - Athlete → 2-page swipeable surface: "Feed" (page 0, the social feed) +
///   "Rankings" (page 1). Page 0 keeps its provider subscriptions alive via
///   [AutomaticKeepAliveClientMixin] while swiped away; page 1's Firestore
///   leaderboard listeners are `autoDispose` and release on swipe-away.
/// - Trainer → the feed body ALONE, no pill and no rankings page. Rankings
///   are per-gym ATHLETE leaderboards (streaks, volume, main lifts) and a
///   trainer is not a competitor in them. Trainers never saw this surface
///   while it lived on the Entrenar tab (TrainerWorkoutView bypassed it);
///   moving it to the role-shared Feed tab exposed it by accident, and this
///   gate restores the original scope.
/// - Loading → athlete layout, same rationale as [HomeScreen] /
///   [WorkoutScreen]: athletes dominate, and rendering early avoids a
///   skeleton stall. A trainer may see the pill for one frame before their
///   role resolves — acceptable, and [RankingsBody] self-gates anyway.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key, this.initialTab});

  /// Optional initial sub-tab — accepts `'rankings'`. Read from the `?tab=`
  /// query param by the `/feed` route builder (mirrors `CoachScreen.initialTab`).
  /// Ignored for the trainer view, which has no second page to land on.
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Two SEPARATE subtrees, not one DefaultTabController with a varying
    // `length`: flipping 2 → 1 on an existing controller throws on the
    // length/index mismatch. Swapping the whole subtree sidesteps it.
    return role == UserRole.trainer
        ? const _FeedPage()
        : _AthleteFeed(initialTab: initialTab);
  }
}

/// Athlete Feed — segmented pill + swipeable [TabBarView].
class _AthleteFeed extends StatelessWidget {
  const _AthleteFeed({this.initialTab});

  final String? initialTab;

  static const _labels = <String>['FEED', 'RANKINGS'];

  static int _resolveInitialIndex(String? tab) => tab == 'rankings' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: _labels.length,
      initialIndex: _resolveInitialIndex(initialTab),
      child: Column(
        children: [
          // Segmented pill control — same sub-tab language as the Entrenar
          // tab's former pill and TrainerCoachView's week tabs.
          Container(
            margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: palette.textMuted.withValues(alpha: 0.12),
              ),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              splashBorderRadius: BorderRadius.circular(20),
              labelColor: palette.bg,
              unselectedLabelColor: palette.textMuted,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              tabs: [for (final l in _labels) Tab(text: l, height: 40)],
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(
            child: TabBarView(
              // showTitle: false — the pill above already reads "FEED".
              children: [_FeedPage(showTitle: false), _RankingsPage()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 0 — the original feed body (header + segment pills + posts), wrapped
/// with [AutomaticKeepAliveClientMixin] so its feed providers are NOT rebuilt
/// when swiping to Rankings and back.
class _FeedPage extends ConsumerStatefulWidget {
  const _FeedPage({this.showTitle = true});

  /// Whether the header renders its "FEED" title.
  ///
  /// `false` under [_AthleteFeed], where the segmented pill ALREADY reads
  /// "FEED" one row above — printing it twice was pure redundancy. `true`
  /// (default) for the trainer view, which has no pill and would otherwise
  /// lose every label identifying the screen.
  final bool showTitle;

  @override
  ConsumerState<_FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<_FeedPage>
    with AutomaticKeepAliveClientMixin<_FeedPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final segment = ref.watch(feedSegmentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FeedHeader(showTitle: widget.showTitle),
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

/// Page 1 — thin host for the self-contained rankings surface. Owns its own
/// slim `RANKINGS` header and all state-branching (no-gym / opted-out /
/// leaderboards). NOT kept alive — its leaderboard listeners are
/// `autoDispose` and release on swipe-away.
class _RankingsPage extends StatelessWidget {
  const _RankingsPage();

  @override
  Widget build(BuildContext context) {
    return const RankingsBody();
  }
}

class _FeedHeader extends ConsumerWidget {
  const _FeedHeader({required this.showTitle});

  /// See [_FeedPage.showTitle]. When `false` only the action icons render,
  /// still right-aligned — the Spacer takes over the room the title had.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final uid = ref.watch(currentUidProvider);
    final notificationBadge =
        uid == null ? 0 : ref.watch(notificationHeaderBadgeProvider(uid));
    // REQ-CHATUNREAD-005: count of chats with unread messages for the badge.
    // Only user↔user (social) chats feed this badge — messages from the
    // athlete's coach live under the COACH tab badge. See
    // `unreadFromCoachProvider` / `unreadFromFriendsProvider`.
    final unreadChats = ref.watch(unreadFromFriendsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          if (showTitle)
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
            label: notificationBadge > 0
                ? l10n.notificationBellWithCountA11y(notificationBadge)
                : l10n.notificationBellA11y,
            child: TreinoTappable(
              onTap: () => context.push('/feed/notifications'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(TreinoIcon.bell, size: 20, color: palette.textMuted),
                      if (notificationBadge > 0)
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
                              notificationBadge > 9
                                  ? '9+'
                                  : '$notificationBadge',
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
            child: TreinoTappable(
              onTap: () => context.push('/feed/messages'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(TreinoIcon.chat, size: 20, color: palette.textMuted),
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
            child: TreinoTappable(
              onTap: () => context.push('/feed/search'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
            child: TreinoTappable(
              onTap: () => context.push('/feed/create'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
///
/// StatefulWidget (no función suelta): [TreinoFadeSlideIn] está PROHIBIDO en
/// builders lazy porque los ítems reciclados re-montan su State al re-entrar
/// al viewport y la entrada re-animaría en cada scroll — el cap `i >= 8` NO
/// alcanza porque el problema es el re-mount, no el índice. `_animatedIds`
/// vive en el State de este widget (sobrevive al scroll, que solo
/// monta/desmonta los Elements hijos del `ListView.separated`, no este
/// State) y recuerda qué posts YA corrieron su entrada, así un post
/// reciclado que vuelve a construirse nunca vuelve a animar.
class _FeedPostList extends StatefulWidget {
  const _FeedPostList({
    required this.posts,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final List<Post> posts;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  State<_FeedPostList> createState() => _FeedPostListState();
}

class _FeedPostListState extends State<_FeedPostList> {
  static const _loadMoreThreshold = 400.0;

  final Set<String> _animatedIds = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter <= _loadMoreThreshold) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: widget.posts.length + (widget.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        if (i == widget.posts.length) {
          final palette = AppPalette.of(context);
          return Padding(
            key: const ValueKey('feed-loading-more-indicator'),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: palette.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }

        final post = widget.posts[i];
        void onAuthorTap() => context.go('/feed/profile/${post.authorUid}');

        // La card tiene estado local (el detalle del entreno expandido), así
        // que la reconciliación POR POSICIÓN del ListView la corrompe: si
        // entra un post nuevo arriba (refresh, o el propio usuario
        // compartiendo), el Element de esa posición se reusa para OTRO post y
        // muestra su detalle expandido. La key ata el estado al post — vive en
        // PostCard (invariante que un test cubre explícitamente) Y en
        // cualquier wrapper que se interponga como raíz del builder, para que
        // la reconciliación del ListView tampoco se confunda en esa capa.
        final card = PostCard(
            key: ValueKey(post.id), post: post, onAuthorTap: onAuthorTap);

        // `add` devuelve false si el id ya estaba — ya animó una vez, no
        // importa si el Element se recicló y se está reconstruyendo ahora.
        final alreadyAnimated = !_animatedIds.add(post.id);
        // Stagger sutil SOLO para los primeros 8 posts que entran sin haber
        // animado antes (lo que se ve en cada carga/refresh) — cap explícito
        // para no costear memoria/perf en listas largas ni generar una
        // cascada interminable de delays.
        if (i >= 8 || alreadyAnimated) return card;
        return TreinoFadeSlideIn(
          key: ValueKey(post.id),
          delay: AppMotion.stagger(i),
          child: card,
        );
      },
    );
  }
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
/// providers do NOT self-heal, so the retry invalidates [onRetry]'s provider
/// to force a refetch.
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

    return TreinoStateSwitcher(
      childKey: ValueKey(
        async.when(
          data: (_) => 'data',
          loading: () => 'loading',
          error: (_, __) => 'error',
        ),
      ),
      child: async.when(
        data: (data) => Semantics(
          label: l10n.feedPullToRefreshA11y,
          child: RefreshIndicator(
            color: palette.accent,
            onRefresh: onRefresh,
            child: dataBuilder(context, data),
          ),
        ),
        loading: () =>
            Center(child: CircularProgressIndicator(color: palette.accent)),
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
      onRetry: () {
        ref.invalidate(feedPaginationProvider);
        ref.invalidate(feedForFriendsProvider);
        ref.invalidate(myFriendsFeedProvider);
      },
      onRefresh: () async {
        final paginationKey =
            ref.read(myFriendsFeedPaginationKeyProvider).valueOrNull;
        if (paginationKey == null) {
          ref.invalidate(myFriendsFeedPaginationKeyProvider);
          await ref.read(myFriendsFeedPaginationKeyProvider.future);
          return;
        }
        await ref
            .read(feedPaginationProvider(paginationKey).notifier)
            .refresh();
        ref.invalidate(feedForFriendsProvider);
        ref.invalidate(myFriendsFeedProvider);
      },
      dataBuilder: (context, posts) {
        if (posts.isEmpty) {
          final gymId = ref.watch(
            userProfileProvider.select(
              (profile) => profile.valueOrNull?.gymId,
            ),
          );
          return _scrollableEmptyState(
            context,
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FeedEmptyState(
                  message: 'Aún no hay posts de tus amigos',
                ),
                SuggestedUsersSection(gymId: gymId),
              ],
            ),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedPostList(
          posts: posts,
          isLoadingMore: pagination?.isLoadingMore ?? false,
          onLoadMore: () async {
            final paginationKey =
                ref.read(myFriendsFeedPaginationKeyProvider).valueOrNull;
            if (paginationKey == null || !(pagination?.hasMore ?? false)) {
              return;
            }
            await ref
                .read(feedPaginationProvider(paginationKey).notifier)
                .loadMore();
            ref.invalidate(feedForFriendsProvider);
            ref.invalidate(myFriendsFeedProvider);
          },
        );
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
      onRetry: () {
        ref.invalidate(feedPaginationProvider);
        ref.invalidate(feedForGymProvider);
        ref.invalidate(myGymFeedProvider);
      },
      onRefresh: () async {
        final paginationKey =
            ref.read(myGymFeedPaginationKeyProvider).valueOrNull;
        if (paginationKey == null) {
          ref.invalidate(myGymFeedPaginationKeyProvider);
          await ref.read(myGymFeedPaginationKeyProvider.future);
          return;
        }
        await ref
            .read(feedPaginationProvider(paginationKey).notifier)
            .refresh();
        ref.invalidate(feedForGymProvider);
        ref.invalidate(myGymFeedProvider);
      },
      dataBuilder: (context, posts) {
        if (posts == null) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(message: 'Todavía no estás en un gym'),
          );
        }
        if (posts.isEmpty) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(message: 'Tu gym todavía no tiene posts'),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedPostList(
          posts: posts,
          isLoadingMore: pagination?.isLoadingMore ?? false,
          onLoadMore: () async {
            final paginationKey =
                ref.read(myGymFeedPaginationKeyProvider).valueOrNull;
            if (paginationKey == null || !(pagination?.hasMore ?? false)) {
              return;
            }
            await ref
                .read(feedPaginationProvider(paginationKey).notifier)
                .loadMore();
            ref.invalidate(feedForGymProvider);
            ref.invalidate(myGymFeedProvider);
          },
        );
      },
    );
  }
}

class _PublicoBody extends ConsumerWidget {
  const _PublicoBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = feedPaginationProvider(publicFeedPaginationKey);
    return _FeedAsyncBody<List<Post>>(
      async: ref.watch(feedPublicProvider),
      onRetry: () {
        ref.invalidate(provider);
        ref.invalidate(feedPublicProvider);
      },
      onRefresh: () async {
        await ref.read(provider.notifier).refresh();
        ref.invalidate(feedPublicProvider);
      },
      dataBuilder: (context, posts) {
        if (posts.isEmpty) {
          return _scrollableEmptyState(
            context,
            const FeedEmptyState(message: 'Aún no hay posts públicos'),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedPostList(
          posts: posts,
          isLoadingMore: pagination?.isLoadingMore ?? false,
          onLoadMore: () async {
            if (!(pagination?.hasMore ?? false)) return;
            await ref.read(provider.notifier).loadMore();
            ref.invalidate(feedPublicProvider);
          },
        );
      },
    );
  }
}
