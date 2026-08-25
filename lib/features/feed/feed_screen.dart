import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../core/analytics/analytics_service.dart';
import '../../core/analytics/sub_tab_analytics.dart';
import '../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../core/widgets/motion/treino_state_switcher.dart';
import '../../core/widgets/motion/treino_tappable.dart';
import '../../core/widgets/treino_segmented_pill.dart';
import '../../core/widgets/treino_bottom_bar.dart';
import '../../core/widgets/treino_glass_surface.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../chat/application/chat_providers.dart';
import '../gym_rankings/presentation/rankings_screen.dart' show RankingsBody;
import '../gyms/domain/gym.dart' show kNoGymId;
import '../notifications/application/notification_history_providers.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_public_profile.dart';
import '../profile/domain/user_role.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/feed_screen_providers.dart';
import 'application/feed_pagination_notifier.dart';
import 'application/post_providers.dart';
import 'application/suggested_users_providers.dart';
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

/// Área tapeable mínima de cada acción del header.
///
/// 44 y no menos: es el piso de la HIG de Apple y queda apenas por debajo de
/// los 48 de Material. La fila llegó a bajarlo a 36 en pantallas angostas y
/// era plata tirada — con las acciones pegadas al margen derecho sobra lugar
/// incluso en un iPhone de 393pt.
const double _kFeedActionTapTarget = 44;

/// Ancho a partir del cual la fila del header entra holgada: el toggle en su
/// tope (176) + la separación mínima (8) + las cuatro acciones con su aire
/// (4 × 44 + 3 × 4). Por debajo de esto los íconos se juntan, pero conservan
/// su área tapeable completa.
const double _kFeedHeaderRoomyWidth =
    176 + 8 + (4 * _kFeedActionTapTarget + 3 * 4);

/// Athlete Feed — segmented pill + swipeable [TabBarView].
class _AthleteFeed extends StatelessWidget {
  const _AthleteFeed({this.initialTab});

  final String? initialTab;

  static const _labels = <String>['FEED', 'RANKINGS'];

  /// Slugs de analytics — estables, en el orden del [TabBarView]. No son los
  /// labels: esos cambian con el copy y con el idioma.
  static const _analyticsSurface = 'feed';
  static const _analyticsTabs = <String>['feed', 'rankings'];

  static const _pages = TabBarView(
    children: [_FeedPage(showTitle: false), _RankingsPage()],
  );

  static int _resolveInitialIndex(String? tab) => tab == 'rankings' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _labels.length,
      initialIndex: _resolveInitialIndex(initialTab),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Con menos que esto los íconos pierden su separación, pero
                // NO su área tapeable: ver [_FeedActions.compact].
                final compactActions =
                    constraints.maxWidth < _kFeedHeaderRoomyWidth;
                return Row(
                  key: const ValueKey('feed-fixed-navigation-row'),
                  // Las acciones tienen que morir contra el margen derecho.
                  // Sin esto el `Row` alinea al inicio y todo el sobrante
                  // —25pt en un iPhone de 393— quedaba como un hueco muerto
                  // entre el botón `+` y el borde de la pantalla.
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 176),
                        // La key va en el componente: los tests de layout de
                        // esta fila la usan para medir el centrado contra las
                        // acciones.
                        child: const TreinoSegmentedPill(
                          key: ValueKey('feed-rankings-toggle'),
                          labels: _labels,
                        ),
                      ),
                    ),
                    // La separación mínima va como padding de las acciones y
                    // no como un `SizedBox` suelto: con `spaceBetween`, un
                    // tercer hijo invisible se comería uno de los dos huecos.
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _FeedActions(compact: compactActions),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // FEED y RANKINGS son las dos la ruta `/feed`: el observer de rutas
          // las ve como una sola pantalla, así que este wrapper es el único
          // que puede distinguirlas. Envuelve las PÁGINAS y no el pill a
          // propósito — el pill sigue siendo presentación pura, y así el
          // evento tampoco depende de qué widget dibuje el control (#646 lo
          // está reemplazando).
          const Expanded(
            child: SubTabAnalytics(
              surface: _analyticsSurface,
              tabs: _analyticsTabs,
              child: _pages,
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

  /// Slug estable por segmento. Se mapea a mano en vez de usar `.name` para
  /// que renombrar el enum no renombre el evento y parta la serie histórica.
  /// Además `FeedSegment.public` se reporta como `publico`, que es como se
  /// llama el segmento en la UI.
  static const _segmentSlugs = <FeedSegment, String>{
    FeedSegment.amigos: 'amigos',
    FeedSegment.gym: 'gym',
    FeedSegment.public: 'publico',
  };

  void _logSegment(FeedSegment segment) {
    ref.read(analyticsServiceProvider).logSubTabViewed(
          surface: 'feed_segments',
          tab: _segmentSlugs[segment]!,
        );
  }

  @override
  void initState() {
    super.initState();
    // El segmento inicial también cuenta: sin esto `amigos` (el default)
    // quedaría sistemáticamente subcontado contra `gym` y `publico`, que sólo
    // se alcanzan tapeando.
    _logSegment(ref.read(feedSegmentProvider));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Los segmentos no son un TabController sino un StateProvider, así que
    // acá se escucha el provider. Escuchar el estado y no el `onTap` de los
    // pills mantiene el evento correcto si mañana el segmento se cambia desde
    // otro lado (deep-link, restaurar preferencia).
    ref.listen<FeedSegment>(feedSegmentProvider, (previous, next) {
      if (previous == next) return;
      _logSegment(next);
    });
    final segment = ref.watch(feedSegmentProvider);

    return switch (segment) {
      FeedSegment.amigos => _AmigosBody(showTitle: widget.showTitle),
      FeedSegment.gym => _MiGymBody(showTitle: widget.showTitle),
      FeedSegment.public => _PublicoBody(showTitle: widget.showTitle),
    };
  }
}

SliverAppBar _feedAppBar(
  BuildContext context, {
  required bool showTitle,
}) {
  final palette = AppPalette.of(context);

  return SliverAppBar(
    key: const ValueKey('feed-collapsible-header'),
    floating: true,
    snap: true,
    automaticallyImplyLeading: false,
    backgroundColor: palette.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 80,
    titleSpacing: 0,
    title: _FeedHeader(showTitle: showTitle),
  );
}

/// La fila de segmentos, como un sliver común que scrollea con el feed.
///
/// Era un [SliverPersistentHeader] con `pinned: true`, y eso lo obligaba a
/// pintarse un `ColoredBox(palette.bg)` opaco: al quedar fijo, tapaba los
/// posts que le pasaban por detrás. El problema es que `palette.bg` es solo la
/// base sólida de [AppBackground] — le faltan los dos glows radiales. El
/// header quedaba entonces como una franja plana recortada contra el fondo, y
/// justo ahí arriba a la izquierda es donde el glow del accent está más
/// presente, así que el corte saltaba a la vista.
///
/// Scrolleando con el contenido no se superpone con nada, así que no necesita
/// fondo: se ve el [AppBackground] real, glow incluido. Tampoco es `floating`
/// a propósito — floating lo haría reaparecer ENCIMA del contenido al
/// scrollear hacia arriba, y volveríamos a necesitar el fondo opaco.
class _FeedSegmentSliver extends StatelessWidget {
  const _FeedSegmentSliver();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: FeedSegmentPills(),
      ),
    );
  }
}

/// Page 1 — thin host for the self-contained rankings surface. The shared
/// fixed navigation row lives above the [TabBarView]. NOT kept alive — its
/// leaderboard listeners are `autoDispose` and release on swipe-away.
class _RankingsPage extends StatelessWidget {
  const _RankingsPage();

  @override
  Widget build(BuildContext context) {
    return const RankingsBody();
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.showTitle});

  /// See [_FeedPage.showTitle].
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

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
          const _FeedActions(),
        ],
      ),
    );
  }
}

class _FeedActions extends ConsumerWidget {
  const _FeedActions({this.compact = false});

  /// Cuando es `true` los íconos pierden la separación entre sí, y solo eso.
  /// El área tapeable NO se toca: se queda en [_kFeedActionTapTarget] siempre.
  final bool compact;

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
    // `compact` junta los íconos, y NADA más. El área tapeable se queda
    // siempre en el mínimo de la HIG: achicarla a 36 en pantallas angostas
    // era una regresión de accesibilidad, y encima innecesaria.
    final spacing = compact ? 0.0 : 4.0;

    return Row(
      key: const ValueKey('feed-header-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: notificationBadge > 0
              ? l10n.notificationBellWithCountA11y(notificationBadge)
              : l10n.notificationBellA11y,
          child: TreinoTappable(
            onTap: () => context.push('/feed/notifications'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _kFeedActionTapTarget,
                minHeight: _kFeedActionTapTarget,
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const _FeedIconBubble(icon: TreinoIcon.bell),
                    if (notificationBadge > 0)
                      Positioned(
                        top: -2,
                        right: -3,
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
                            notificationBadge > 9 ? '9+' : '$notificationBadge',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.barlow(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: TreinoButtonTokens.foreground(context),
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
        SizedBox(width: spacing),
        Semantics(
          button: true,
          label: unreadChats > 0
              ? l10n.feedMessagesWithUnreadA11y(unreadChats)
              : l10n.feedMessagesA11y,
          child: TreinoTappable(
            onTap: () => context.push('/feed/messages'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _kFeedActionTapTarget,
                minHeight: _kFeedActionTapTarget,
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const _FeedIconBubble(icon: TreinoIcon.chat),
                    if (unreadChats > 0)
                      Positioned(
                        top: -2,
                        right: -3,
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
                              color: TreinoButtonTokens.foreground(context),
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
        SizedBox(width: spacing),
        Semantics(
          button: true,
          label: l10n.feedSearchA11y,
          child: TreinoTappable(
            onTap: () => context.push('/feed/search'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _kFeedActionTapTarget,
                minHeight: _kFeedActionTapTarget,
              ),
              child: const Center(
                child: _FeedIconBubble(icon: TreinoIcon.search),
              ),
            ),
          ),
        ),
        SizedBox(width: spacing),
        Semantics(
          button: true,
          label: l10n.feedCreatePostA11y,
          child: TreinoTappable(
            onTap: () => context.push('/feed/create'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _kFeedActionTapTarget,
                minHeight: _kFeedActionTapTarget,
              ),
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(TreinoIcon.plus,
                      size: 20, color: TreinoButtonTokens.foreground(context)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Burbuja de vidrio de los accesos del header (campana, chat, búsqueda).
///
/// Mismo acabado que la barra de navegación —relleno translúcido + reflejo
/// especular, ver [TreinoGlassSurface]— para que las dos superficies flotantes
/// de la app hablen el mismo idioma. El botón de crear post NO lo usa a
/// propósito: es el CTA primario y va lleno de accent, sin competencia.
class _FeedIconBubble extends StatelessWidget {
  const _FeedIconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: TreinoGlassSurface(
        shape: BoxShape.circle,
        fillOpacity: TreinoGlassSurface.bubbleFillOpacity,
        borderColor: palette.textMuted.withValues(alpha: 0.12),
        child: Icon(icon, size: 20, color: palette.textMuted),
      ),
    );
  }
}

class _FeedContent {
  const _FeedContent.posts({
    required this.posts,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.suggestions = const [],
  }) : emptyState = null;

  const _FeedContent.empty(this.emptyState)
      : posts = null,
        isLoadingMore = false,
        onLoadMore = null,
        suggestions = const [];

  final List<Post>? posts;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;
  final Widget? emptyState;
  final List<UserPublicProfile> suggestions;
}

sealed class _FeedSlot {
  const _FeedSlot();
}

class _PostSlot extends _FeedSlot {
  const _PostSlot(this.post, this.postIndex);

  final Post post;
  final int postIndex;
}

class _SuggestionsSlot extends _FeedSlot {
  const _SuggestionsSlot(this.profiles);

  final List<UserPublicProfile> profiles;
}

class _LoaderSlot extends _FeedSlot {
  const _LoaderSlot();
}

class _SeparatorSlot extends _FeedSlot {
  const _SeparatorSlot();
}

/// The feed's single vertical scroll surface: collapsible app bar, pinned
/// navigation pills, and lazy post sliver.
///
/// `_animatedIds` belongs to the scroll surface rather than a lazy child. A
/// recycled post can therefore be rebuilt without replaying its entrance.
class _FeedScrollView extends StatefulWidget {
  const _FeedScrollView({
    super.key,
    required this.showTitle,
    required this.content,
  });

  final bool showTitle;
  final _FeedContent content;

  @override
  State<_FeedScrollView> createState() => _FeedScrollViewState();
}

class _FeedScrollViewState extends State<_FeedScrollView> {
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
    final onLoadMore = widget.content.onLoadMore;
    if (onLoadMore != null &&
        _scrollController.position.extentAfter <= _loadMoreThreshold) {
      onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomInset =
        MediaQuery.paddingOf(context).bottom + TreinoBottomBar.minHeight;

    return CustomScrollView(
      // Restaura el offset aunque el widget se reconstruya. Hace falta porque
      // este scroll vive dentro del AnimatedSwitcher de TreinoStateSwitcher, y
      // la primera página extra cambia la forma de la lista (hasMore true →
      // false), lo que dispara un reemplazo del subtree: se monta un scroll
      // nuevo y muere el que tenía la posición. Sin esto, la primera vez que
      // entraban posts extra el feed volvía al principio.
      //
      // No alcanza con darle una key al widget: el switcher decide el
      // reemplazo más arriba en el árbol. PageStorageKey resuelve el síntoma
      // donde importa — la posición sobrevive a la reconstrucción.
      key: const PageStorageKey<String>('feed-scroll-position'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (widget.showTitle) _feedAppBar(context, showTitle: true),
        const _FeedSegmentSliver(),
        if (widget.content.posts case final posts?)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset),
            sliver: _buildPostList(palette, posts),
          )
        else
          SliverPadding(
            padding: EdgeInsets.only(bottom: bottomInset),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: widget.content.emptyState,
            ),
          ),
      ],
    );
  }

  Widget _buildPostList(AppPalette palette, List<Post> posts) {
    final contentSlots = <_FeedSlot>[];
    for (var postIndex = 0; postIndex < posts.length; postIndex++) {
      contentSlots.add(_PostSlot(posts[postIndex], postIndex));
      final page = suggestedUsersAfterPost(
        widget.content.suggestions,
        postIndex,
      );
      if (page.isNotEmpty) contentSlots.add(_SuggestionsSlot(page));
    }
    if (widget.content.isLoadingMore) {
      contentSlots.add(const _LoaderSlot());
    }

    final slots = <_FeedSlot>[];
    for (final slot in contentSlots) {
      if (slots.isNotEmpty) slots.add(const _SeparatorSlot());
      slots.add(slot);
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final slot = slots[index];
          return switch (slot) {
            _SeparatorSlot() => const SizedBox(height: 14),
            _SuggestionsSlot(:final profiles) =>
              SuggestedUsersSection.profiles(profiles: profiles),
            _LoaderSlot() => Padding(
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
              ),
            _PostSlot(:final post, :final postIndex) =>
              _buildPost(context, post, postIndex),
          };
        },
        childCount: slots.length,
      ),
    );
  }

  Widget _buildPost(BuildContext context, Post post, int postIndex) {
    void onAuthorTap() => context.go('/feed/profile/${post.authorUid}');
    final card = PostCard(
      key: ValueKey(post.id),
      post: post,
      onAuthorTap: onAuthorTap,
    );

    final alreadyAnimated = !_animatedIds.add(post.id);
    if (postIndex >= 8 || alreadyAnimated) return card;
    return TreinoFadeSlideIn(
      key: ValueKey(post.id),
      delay: AppMotion.stagger(postIndex),
      child: card,
    );
  }
}

class _FeedStaticScrollView extends StatelessWidget {
  const _FeedStaticScrollView({
    required this.showTitle,
    required this.child,
  });

  final bool showTitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (showTitle) _feedAppBar(context, showTitle: true),
        const _FeedSegmentSliver(),
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }
}

/// Shared async resolver for the three feed segments.
///
/// Renders a consistent loading spinner and — critically — an error state
/// that pairs the localized message with a Reintentar CTA. Because the feed
/// providers do NOT self-heal, so the retry invalidates [onRetry]'s provider
/// to force a refetch.
class _FeedAsyncBody<T> extends StatelessWidget {
  const _FeedAsyncBody({
    required this.showTitle,
    required this.async,
    required this.onRetry,
    required this.onRefresh,
    required this.dataBuilder,
  });

  final bool showTitle;
  final AsyncValue<T> async;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final _FeedContent Function(BuildContext context, T data) dataBuilder;

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
        data: (data) {
          final content = dataBuilder(context, data);
          return Semantics(
            label: l10n.feedPullToRefreshA11y,
            child: RefreshIndicator(
              color: palette.accent,
              onRefresh: onRefresh,
              // Key estable: sin ella, el AnimatedSwitcher de
              // TreinoStateSwitcher trata cada página nueva de posts como un
              // CAMBIO DE ESTADO y hace cross-fade — monta un scroll nuevo y
              // destruye el que tenía la posición. El resultado era volver al
              // principio del feed cada vez que entraba una página.
              child: _FeedScrollView(
                key: const ValueKey('feed-scroll-view'),
                showTitle: showTitle,
                content: content,
              ),
            ),
          );
        },
        loading: () => _FeedStaticScrollView(
          showTitle: showTitle,
          child: Center(
            child: CircularProgressIndicator(color: palette.accent),
          ),
        ),
        error: (_, __) => _FeedStaticScrollView(
          showTitle: showTitle,
          child: Center(
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
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accent,
                    ),
                    child: Text(l10n.coachRetryLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmigosBody extends ConsumerWidget {
  const _AmigosBody({required this.showTitle});

  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymId = ref.watch(
      userProfileProvider.select((p) => p.valueOrNull?.gymId),
    );
    final suggestions = (gymId == null || gymId.isEmpty || gymId == kNoGymId)
        ? const <UserPublicProfile>[]
        : ref.watch(suggestedUsersProvider(gymId)).valueOrNull ?? const [];

    return _FeedAsyncBody<List<Post>>(
      showTitle: showTitle,
      async: ref.watch(myFollowingFeedProvider),
      onRetry: () {
        ref.invalidate(feedPaginationProvider);
        ref.invalidate(feedForFriendsProvider);
        ref.invalidate(myFollowingFeedProvider);
      },
      onRefresh: () async {
        final paginationKey =
            ref.read(myFollowingFeedPaginationKeyProvider).valueOrNull;
        if (paginationKey == null) {
          ref.invalidate(myFollowingFeedPaginationKeyProvider);
          await ref.read(myFollowingFeedPaginationKeyProvider.future);
          return;
        }
        await ref
            .read(feedPaginationProvider(paginationKey).notifier)
            .refresh();
        ref.invalidate(feedForFriendsProvider);
        ref.invalidate(myFollowingFeedProvider);
      },
      dataBuilder: (context, posts) {
        if (posts.isEmpty) {
          return _FeedContent.empty(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FeedEmptyState(
                  message: AppL10n.of(context).feedEmptyFollowing,
                ),
                SuggestedUsersSection(gymId: gymId),
              ],
            ),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedContent.posts(
          posts: posts,
          suggestions: suggestions,
          isLoadingMore: pagination?.isLoadingMore ?? false,
          onLoadMore: () async {
            final paginationKey =
                ref.read(myFollowingFeedPaginationKeyProvider).valueOrNull;
            if (paginationKey == null || !(pagination?.hasMore ?? false)) {
              return;
            }
            await ref
                .read(feedPaginationProvider(paginationKey).notifier)
                .loadMore();
            ref.invalidate(feedForFriendsProvider);
            ref.invalidate(myFollowingFeedProvider);
          },
        );
      },
    );
  }
}

class _MiGymBody extends ConsumerWidget {
  const _MiGymBody({required this.showTitle});

  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymId = ref.watch(
      userProfileProvider.select((p) => p.valueOrNull?.gymId),
    );
    final suggestions = (gymId == null || gymId.isEmpty || gymId == kNoGymId)
        ? const <UserPublicProfile>[]
        : ref.watch(suggestedUsersProvider(gymId)).valueOrNull ?? const [];

    return _FeedAsyncBody<List<Post>?>(
      showTitle: showTitle,
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
          return const _FeedContent.empty(
            FeedEmptyState(message: 'Todavía no estás en un gym'),
          );
        }
        if (posts.isEmpty) {
          return const _FeedContent.empty(
            FeedEmptyState(message: 'Tu gym todavía no tiene posts'),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedContent.posts(
          posts: posts,
          suggestions: suggestions,
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
  const _PublicoBody({required this.showTitle});

  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = feedPaginationProvider(publicFeedPaginationKey);
    final gymId = ref.watch(
      userProfileProvider.select((p) => p.valueOrNull?.gymId),
    );
    final suggestions = (gymId == null || gymId.isEmpty || gymId == kNoGymId)
        ? const <UserPublicProfile>[]
        : ref.watch(suggestedUsersProvider(gymId)).valueOrNull ?? const [];
    return _FeedAsyncBody<List<Post>>(
      showTitle: showTitle,
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
          return const _FeedContent.empty(
            FeedEmptyState(message: 'Aún no hay posts públicos'),
          );
        }
        final pagination = posts is PaginatedPostList ? posts : null;
        return _FeedContent.posts(
          posts: posts,
          suggestions: suggestions,
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
