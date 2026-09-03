import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/feed/application/feed_pagination_notifier.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/application/suggested_users_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_page.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/feed_segment_pills.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/features/gym_rankings/application/ranking_providers.dart';
import 'package:treino/features/notifications/application/notification_history_providers.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/ranking_optin_controller_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import '../../../helpers/onboarding_test_helpers.dart';

class _MockUser extends Mock implements User {}

User _fakeUser(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

class _FakeRankingOptInController implements RankingOptInControllerBase {
  final List<String> enabledCalls = [];
  final List<String> disabledCalls = [];

  @override
  Future<void> enableRankingOptIn(String uid) async {
    enabledCalls.add(uid);
  }

  @override
  Future<void> disableRankingOptIn(String uid) async {
    disabledCalls.add(uid);
  }

  @override
  Future<void> syncGymIfDesynced(String uid) async {}
}

class _CountingPublicPostRepository extends Fake implements PostRepository {
  _CountingPublicPostRepository(this.initialPosts);

  final List<Post> initialPosts;
  int pageRequests = 0;

  @override
  Future<PostPage> feedPublic({int limit = 20, DateTime? after}) async {
    pageRequests++;
    return PostPage(
      posts: after == null ? initialPosts : const <Post>[],
      nextCursor: after == null ? DateTime.utc(2026, 8, 1) : null,
      hasMore: after == null,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Post _makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  String text = 'Buena sesión',
  RoutineTag? routineTag,
  PostPrivacy privacy = PostPrivacy.followers,
  DateTime? createdAt,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      text: text,
      routineTag: routineTag,
      privacy: privacy,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 1)),
    );

UserProfile _makeProfile({String? gymId, UserRole role = UserRole.athlete}) =>
    UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
      // These tests are about the feed, not onboarding (#627). Without this the
      // FEED card renders above the pill tabs and pushes content out of the
      // test viewport.
      onboardingSeen: allSurfacesSeen(),
    );

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

Widget _wrapProviderRouter(Widget w, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: w),
      ),
      GoRoute(
        path: '/feed/profile/:uid',
        builder: (_, state) =>
            Scaffold(body: Text('profile-${state.pathParameters['uid']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── REQ-FEED-SCREEN-001 — Composition ─────────────────────────────────────

  group('REQ-FEED-SCREEN-001: composition', () {
    final baseOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-144: "FEED" is labelled EXACTLY ONCE.
    //
    // For an athlete that label is the segmented pill; the header title is
    // suppressed because printing "FEED" twice, one row apart, was pure
    // redundancy. The trainer case (no pill → the title is the only label)
    // is asserted in the role-gate group.
    testWidgets('SCENARIO-144: labels FEED once — the pill, not a duplicate',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pumpAndSettle();

      expect(find.text('FEED'), findsOneWidget);
    });

    // REQ-CHATUNREAD-005: the messages icon shows an unread-chats count badge.
    testWidgets('messages icon shows unread badge when count > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          ...baseOverrides,
          unreadFromFriendsProvider.overrideWith((_) => 3),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('messages icon shows no badge when zero unread', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          ...baseOverrides,
          unreadFromFriendsProvider.overrideWith((_) => 0),
        ]),
      );
      await tester.pump();

      expect(find.text('0'), findsNothing);
    });

    // SCENARIO-145: FeedScreen renders search and plus icon buttons
    testWidgets('SCENARIO-145: renders search and plus icon stubs', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.search), findsAtLeastNWidgets(1));
      expect(find.byIcon(TreinoIcon.plus), findsAtLeastNWidgets(1));
    });

    // SCENARIO-146: FeedScreen renders FeedSegmentPills exactly once
    testWidgets('SCENARIO-146: renders FeedSegmentPills exactly once', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsOneWidget);
    });

    testWidgets('segment body uses TreinoStateSwitcher for async transitions', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.byType(TreinoStateSwitcher), findsOneWidget);
    });

    // SCENARIO-147: FeedScreen does not introduce Scaffold, AppBackground, SafeArea
    testWidgets(
      'SCENARIO-147: no Scaffold/AppBackground/SafeArea from FeedScreen itself',
      (tester) async {
        // Pump with a plain Scaffold wrapper (no ProviderScope from shell)
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides,
            child: MaterialApp(
              theme: AppTheme.dark(),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              home: const Scaffold(body: FeedScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Only 1 Scaffold: the outer test wrapper
        expect(find.byType(Scaffold), findsOneWidget);
        // No AppBackground anywhere
        expect(find.byType(AppBackground), findsNothing);
        // What the shell contract forbids is FeedScreen wrapping its whole
        // scroll surface in another SafeArea.
        final feedScrollView = find.ancestor(
          of: find.byType(FeedSegmentPills),
          matching: find.byType(CustomScrollView),
        );
        expect(feedScrollView, findsOneWidget);
        expect(
          find.ancestor(
            of: feedScrollView,
            matching: find.byType(SafeArea),
          ),
          findsNothing,
        );
      },
    );

    // SCENARIO-148: FeedScreen in gym segment renders _MiGymBody (REQ-FSG-008)
    testWidgets(
      'SCENARIO-148: gym segment renders _MiGymBody (FeedEmptyState shown)',
      (tester) async {
        await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
            myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
            myGymFeedProvider.overrideWith((ref) async => null),
            feedPublicProvider.overrideWith((ref) async => const <Post>[]),
          ]),
        );
        await tester.pumpAndSettle();

        // null result → "Todavía no estás en un gym"
        expect(find.byType(FeedEmptyState), findsOneWidget);
        expect(find.text('Todavía no estás en un gym'), findsOneWidget);
      },
    );

    // SCENARIO-149: FeedScreen in public segment renders _PublicoBody (REQ-FSG-009)
    testWidgets(
      'SCENARIO-149: public segment renders _PublicoBody (FeedEmptyState shown)',
      (tester) async {
        await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
            myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
            myGymFeedProvider.overrideWith((ref) async => null),
            feedPublicProvider.overrideWith((ref) async => const <Post>[]),
          ]),
        );
        await tester.pumpAndSettle();

        // empty list → "Aún no hay posts públicos"
        expect(find.byType(FeedEmptyState), findsOneWidget);
        expect(find.text('Aún no hay posts públicos'), findsOneWidget);
      },
    );
  });

  // ── REQ-FEED-SCREEN-002 — Data state with posts ───────────────────────────

  group('REQ-FEED-SCREEN-002: amigos data state', () {
    final post1 = _makePost(id: 'a1', text: 'Post uno');
    final post2 = _makePost(id: 'a2', text: 'Post dos');
    final post3 = _makePost(id: 'a3', text: 'Post tres');

    List<Override> makeOverrides(List<Post> posts) => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFollowingFeedProvider.overrideWith((ref) async => posts),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ];

    // SCENARIO-150: list of PostCards rendered in order
    testWidgets('SCENARIO-150: 3 PostCards rendered in correct order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNWidgets(3));
      // Order: first PostCard key or find text
      expect(find.text('Post uno'), findsOneWidget);
      expect(find.text('Post dos'), findsOneWidget);
      expect(find.text('Post tres'), findsOneWidget);
    });

    // Regresión: PostCard tiene estado local (el detalle del entreno
    // expandible), así que la lista DEBE darle una key estable por post. Sin
    // eso, la reconciliación por posición del ListView pega el estado al
    // índice: entra un post nuevo arriba y el detalle expandido salta a otro
    // post. El assert es sobre el call site real, no sobre PostCard aislado.
    testWidgets('cada PostCard lleva una key estable derivada del post.id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])),
      );
      await tester.pumpAndSettle();

      final keys = tester
          .widgetList<PostCard>(find.byType(PostCard))
          .map((card) => card.key)
          .toList();
      expect(keys, [
        const ValueKey('a1'),
        const ValueKey('a2'),
        const ValueKey('a3'),
      ]);
    });

    // SCENARIO-151: no FeedEmptyState when posts present
    testWidgets('SCENARIO-151: no FeedEmptyState when posts present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsNothing);
    });

    // SCENARIO-152: no CircularProgressIndicator when data resolved
    testWidgets('SCENARIO-152: no spinner when data resolved', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-003 — Empty data state ────────────────────────────────

  group('REQ-FEED-SCREEN-003: amigos empty state', () {
    final emptyOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-153: FeedEmptyState rendered when list empty
    testWidgets('SCENARIO-153: FeedEmptyState rendered for empty list', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), emptyOverrides),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
    });

    // SCENARIO-154: no PostCard rendered when list empty
    testWidgets('SCENARIO-154: no PostCard when empty', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), emptyOverrides),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-004 — Loading state ───────────────────────────────────

  group('REQ-FEED-SCREEN-004: amigos loading state', () {
    List<Override> loadingOverrides() => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFollowingFeedProvider.overrideWith((ref) async {
            // Never resolves → AsyncLoading
            await Completer<void>().future;
            return const <Post>[];
          }),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ];

    // SCENARIO-155: spinner rendered during loading
    testWidgets('SCENARIO-155: CircularProgressIndicator during loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), loadingOverrides()),
      );
      // Single pump — don't settle, stay in loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // SCENARIO-156: no PostCard or FeedEmptyState during loading
    testWidgets('SCENARIO-156: no PostCard or FeedEmptyState during loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), loadingOverrides()),
      );
      await tester.pump();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-005 — Error state ─────────────────────────────────────

  group('REQ-FEED-SCREEN-005: amigos error state', () {
    final errorOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFollowingFeedProvider.overrideWith(
        (ref) => Future<List<Post>>.error(Exception('net'), StackTrace.empty),
      ),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-157: graceful fallback rendered, no FlutterError
    testWidgets('SCENARIO-157: graceful error message rendered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), errorOverrides),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu feed. Probá de nuevo.'),
        findsOneWidget,
      );
    });

    // SCENARIO-158: no PostCard or FeedEmptyState in error state
    testWidgets('SCENARIO-158: no PostCard or FeedEmptyState on error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), errorOverrides),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });

  // ── REQ-FSG-010..013, REQ-FSG-016 — _MiGymBody ───────────────────────────

  group('_MiGymBody', () {
    List<Override> gymOverrides({
      required Future<List<Post>?> Function() gymFuture,
    }) =>
        [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) => gymFuture()),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: null)),
          ),
        ];

    // SCENARIO-206: loading state shows spinner
    testWidgets('SCENARIO-206: loading state shows spinner', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async {
            await Completer<void>().future;
            return null;
          }),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // SCENARIO-205: error state shows generic error copy
    testWidgets('SCENARIO-205: error state shows generic error copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith(
            (ref) =>
                Future<List<Post>?>.error(Exception('err'), StackTrace.empty),
          ),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu feed. Probá de nuevo.'),
        findsOneWidget,
      );
    });

    // SCENARIO-202: null result shows no-gym empty state
    testWidgets('SCENARIO-202: null result shows no-gym FeedEmptyState', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedScreen(),
          gymOverrides(gymFuture: () async => null),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Todavía no estás en un gym'), findsOneWidget);
    });

    // SCENARIO-203: empty list shows gym-no-posts empty state
    testWidgets('SCENARIO-203: empty list shows gym-no-posts FeedEmptyState', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedScreen(),
          gymOverrides(gymFuture: () async => const <Post>[]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Tu gym todavía no tiene posts'), findsOneWidget);
    });

    // SCENARIO-204: non-empty list shows ListView with PostCards
    testWidgets('SCENARIO-204: non-empty list shows PostCard ListView', (
      tester,
    ) async {
      final posts = [
        _makePost(id: 'g1', text: 'Post gym 1', authorUid: 'u-gym-1'),
        _makePost(id: 'g2', text: 'Post gym 2', authorUid: 'u-gym-2'),
      ];
      await tester.pumpWidget(
        _wrapProvider(
          const FeedScreen(),
          gymOverrides(gymFuture: () async => posts),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNWidgets(2));
      expect(find.byType(FeedEmptyState), findsNothing);
    });

    // SCENARIO-213/214: PostCard onAuthorTap invoked — navigates to profile
    testWidgets(
      'SCENARIO-213: onAuthorTap callback navigates to /feed/profile/:uid',
      (tester) async {
        final post = _makePost(id: 'g1', text: 'Gym post', authorUid: 'u-xyz');
        await tester.pumpWidget(
          _wrapProviderRouter(
            const FeedScreen(),
            gymOverrides(gymFuture: () async => [post]),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PostCard), findsOneWidget);
        // Tap the author area — PostCard uses GestureDetector internally
        await tester.tap(find.text('Tincho').first);
        await tester.pumpAndSettle();
        // Navigated to profile screen stub
        expect(find.text('profile-u-xyz'), findsOneWidget);
      },
    );
  });

  // ── REQ-FSG-014..016 — _PublicoBody ──────────────────────────────────────

  group('_PublicoBody', () {
    // SCENARIO-211: loading state shows spinner
    testWidgets('SCENARIO-211: loading state shows spinner', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async {
            await Completer<void>().future;
            return const <Post>[];
          }),
        ]),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // SCENARIO-210: error state shows generic error copy
    testWidgets('SCENARIO-210: error state shows generic error copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith(
            (ref) =>
                Future<List<Post>>.error(Exception('err'), StackTrace.empty),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu feed. Probá de nuevo.'),
        findsOneWidget,
      );
    });

    // SCENARIO-208: empty list shows empty-state copy
    testWidgets('SCENARIO-208: empty list shows FeedEmptyState for público', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Aún no hay posts públicos'), findsOneWidget);
    });

    // SCENARIO-209: non-empty list shows ListView with PostCards
    testWidgets('SCENARIO-209: non-empty list shows PostCard ListView', (
      tester,
    ) async {
      final posts = [
        _makePost(
          id: 'pub1',
          text: 'Post público',
          authorUid: 'u-pub-1',
          privacy: PostPrivacy.public,
        ),
      ];
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => posts),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsOneWidget);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });

  // ── Feed | Rankings two-page tab ──────────────────────────────────────────
  //
  // Rankings relocated here from the Entrenar tab: FeedScreen hosts a fixed
  // 2-page DefaultTabController + swipeable TabBarView — "FEED" (page 0, the
  // social feed) and "RANKINGS" (page 1, the self-contained RankingsBody).
  // Gating/body internals are covered by rankings_screen_test.dart; these
  // tests cover the host wiring.
  group('FeedScreen — two-page Feed tab', () {
    const uid = 'athlete-1';
    const gymId = 'gym-a';

    List<Override> tabOverrides({bool rankingOptIn = true}) => [
          // Page 0 (feed) dependencies.
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
          unreadFromFriendsProvider.overrideWith((_) => 0),
          unreadNotificationCountProvider.overrideWith((_) => 0),
          pendingFollowRequestCountProvider(uid).overrideWith((_) => 0),
          // Page 1 (rankings) dependencies — mirrors the override set the
          // Entrenar tab used while it hosted rankings.
          currentUidProvider.overrideWithValue(uid),
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_fakeUser(uid))),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: gymId)),
          ),
          userPublicProfileProvider(uid).overrideWith(
            (_) => Stream.value(
              UserPublicProfile(uid: uid, rankingOptIn: rankingOptIn),
            ),
          ),
          streakLeaderboardProvider(gymId).overrideWith((_) async => []),
          volumeLeaderboardProvider(gymId).overrideWith((_) async => []),
          squatLeaderboardProvider(gymId).overrideWith((_) async => []),
          benchLeaderboardProvider(gymId).overrideWith((_) async => []),
          deadliftLeaderboardProvider(gymId).overrideWith((_) async => []),
          rankingOptInControllerProvider
              .overrideWithValue(_FakeRankingOptInController()),
        ];

    testWidgets('default (initialTab absent) starts on page 0 (Feed)',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), tabOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsOneWidget);
      expect(find.byKey(const Key('rankings_invitation_state')), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
    });

    testWidgets("initialTab: 'rankings' starts on page 1 (Rankings)",
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(initialTab: 'rankings'), tabOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
    });

    testWidgets('swiping the TabBarView switches pages', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), tabOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsOneWidget);

      await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
    });

    testWidgets('invitation state renders on page 1 when opted out',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedScreen(initialTab: 'rankings'),
          tabOverrides(rankingOptIn: false),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
          find.byKey(const Key('rankings_invitation_state')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
    });

    // ── Role gate ───────────────────────────────────────────────────────────
    //
    // Rankings are per-gym ATHLETE leaderboards. Trainers never saw them while
    // the surface lived on the Entrenar tab (TrainerWorkoutView bypassed it);
    // moving it to the role-shared Feed tab exposed it by accident.
    testWidgets('a trainer sees the feed alone — no pill, no rankings page',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          ...tabOverrides(),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(role: UserRole.trainer)),
          ),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
      expect(find.text('RANKINGS'), findsNothing);
      // The feed itself still renders.
      expect(find.byType(FeedSegmentPills), findsOneWidget);
      // And it KEEPS its header title: with no pill, that is the only thing
      // naming the screen, so suppressing it here would leave the trainer
      // with an unlabelled surface.
      expect(find.text('FEED'), findsOneWidget);
    });

    testWidgets(
        "a trainer deep-linking ?tab=rankings still lands on the feed — the "
        'gate wins over initialTab', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(initialTab: 'rankings'), [
          ...tabOverrides(),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(role: UserRole.trainer)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
      expect(find.byKey(const Key('rankings_invitation_state')), findsNothing);
      expect(find.byType(FeedSegmentPills), findsOneWidget);
    });

    testWidgets('an athlete still gets the pill', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          ...tabOverrides(),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(role: UserRole.athlete)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('RANKINGS'), findsOneWidget);
    });

    testWidgets(
        "page 0's feed providers are NOT rebuilt when swiping to page 1 "
        'and back (keep-alive assertion)', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          ...tabOverrides(),
          myFollowingFeedProvider.overrideWith((ref) async {
            buildCount++;
            return const <Post>[];
          }),
        ]),
      );
      await tester.pumpAndSettle();

      expect(buildCount, equals(1));

      // Swipe to page 1 (Rankings) and back to page 0 (Feed).
      await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(TabBarView), const Offset(400, 0), 800);
      await tester.pumpAndSettle();

      expect(find.byType(FeedSegmentPills), findsOneWidget);
      // autoDispose provider would re-fire if page 0 was disposed on swipe
      // away — keep-alive means the FutureProvider result is cached, so the
      // fetch only runs once.
      expect(buildCount, equals(1));
    });
  });

  group('infinite-scroll footer', () {
    List<Override> publicOverrides(List<Post> posts) => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => posts),
        ];

    testWidgets('shows a footer indicator while another page is loading',
        (tester) async {
      final posts = PaginatedPostList(
        FeedPaginationState(
          posts: [_makePost(id: 'loading-more')],
          nextCursor: DateTime.utc(2026, 7, 30),
          hasMore: true,
          isLoadingMore: true,
        ),
      );

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(posts)),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('feed-loading-more-indicator')),
        findsOneWidget,
      );
    });

    testWidgets('shows no footer when the feed has no more pages',
        (tester) async {
      final posts = PaginatedPostList(
        FeedPaginationState(
          posts: [_makePost(id: 'last-page')],
          nextCursor: null,
          hasMore: false,
          isLoadingMore: false,
        ),
      );

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(posts)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('feed-loading-more-indicator')),
        findsNothing,
      );
    });
  });

  group('sliver feed surface', () {
    List<Post> longPosts() => List.generate(
          24,
          (index) => _makePost(
            id: 'sliver-$index',
            authorUid: 'author-$index',
            text: 'Post largo $index ${'contenido ' * 10}',
            privacy: PostPrivacy.public,
          ),
        );

    List<Override> publicOverrides(List<Post> posts) => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => posts),
        ];

    Finder feedScrollView() => find.byType(CustomScrollView);

    testWidgets('FEED/RANKINGS toggle stays visible after scrolling', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final scrollView = feedScrollView();
      await tester.drag(scrollView, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('FEED'), findsOneWidget);
      expect(find.text('RANKINGS'), findsOneWidget);
    });

    testWidgets('renders exactly one FEED/RANKINGS toggle', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabBar, skipOffstage: false), findsOneWidget);
      expect(find.text('FEED', skipOffstage: false), findsOneWidget);
      expect(find.text('RANKINGS', skipOffstage: false), findsOneWidget);
    });

    testWidgets('toggle and action icons share the same fixed row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final toggleRect = tester.getRect(
        find.byKey(const ValueKey('feed-rankings-toggle')),
      );
      final actionsRect = tester.getRect(
        find.byKey(const ValueKey('feed-header-actions')),
      );

      expect(toggleRect.center.dy, closeTo(actionsRect.center.dy, 1));
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('feed-rankings-toggle')),
          matching: find.byKey(const ValueKey('feed-fixed-navigation-row')),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('feed-header-actions')),
          matching: find.byKey(const ValueKey('feed-fixed-navigation-row')),
        ),
        findsOneWidget,
      );
    });

    // Regresión: en un iPhone de 393pt la fila disparaba el modo `compact`
    // (353 < 360), que achicaba las acciones de 44 a 36. Con eso la fila
    // medía 328 sobre 353 disponibles y el `Row`, alineado al inicio, dejaba
    // los 25pt sobrantes como un hueco muerto: el botón `+` moría a 45pt del
    // borde en vez de a los 20 del margen.
    testWidgets('las acciones del header mueren contra el margen derecho', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final actionsRect = tester.getRect(
        find.byKey(const ValueKey('feed-header-actions')),
      );
      // 393 - 20 de margen. La tolerancia es por el `Padding` de separación
      // mínima, que no mueve el borde derecho.
      expect(actionsRect.right, closeTo(373, 1));
    });

    testWidgets('las acciones conservan sus 44pt tapeables en pantalla chica', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      // Cuatro acciones de 44 como piso de la HIG. Cuando bajaban a 36 esto
      // daba 144 — por debajo del mínimo, y encima sin necesidad.
      final actionsRect = tester.getRect(
        find.byKey(const ValueKey('feed-header-actions')),
      );
      expect(actionsRect.width, greaterThanOrEqualTo(4 * 44));
    });

    testWidgets('fixed merged header remains visible when scrolling down', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final scrollView = feedScrollView();
      expect(scrollView, findsOneWidget);
      final chatIcon = find.byIcon(TreinoIcon.chat);
      expect(chatIcon, findsOneWidget);

      await tester.drag(scrollView, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(chatIcon, findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-rankings-toggle')),
        findsOneWidget,
      );
    });

    testWidgets('merged header does not duplicate after reverse scrolling', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final scrollView = feedScrollView();
      final chatIcon = find.byIcon(TreinoIcon.chat);
      await tester.drag(scrollView, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(chatIcon, findsOneWidget);

      await tester.drag(scrollView, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(chatIcon, findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-header-actions')),
        findsOneWidget,
      );
    });

    testWidgets('large text scale does not overflow the merged header', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapProvider(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2.5),
            ),
            child: FeedScreen(),
          ),
          publicOverrides(longPosts()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-header-actions')),
        findsOneWidget,
      );
    });

    // Cambio de comportamiento deliberado: las pills DEJARON de estar fijas.
    //
    // Antes eran un `SliverPersistentHeader(pinned: true)`, y quedar fijas las
    // obligaba a pintarse un fondo opaco `palette.bg` para tapar los posts que
    // les pasaban por detrás. Ese fondo es solo la base sólida de
    // AppBackground, sin sus dos glows radiales, así que la franja se recortaba
    // contra el resto de la pantalla — y encima justo donde el glow del accent
    // está más presente. Scrollean con el contenido, no se superponen con
    // nada, y por eso ya no necesitan fondo.
    testWidgets('las pills scrollean con el feed y se van de pantalla', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final scrollView = feedScrollView();
      final viewportRect = tester.getRect(scrollView);

      // Arrancan a la vista.
      expect(find.byType(FeedSegmentPills), findsOneWidget);
      expect(
        tester.getRect(find.text('PÚBLICO')).bottom,
        greaterThan(viewportRect.top),
      );

      await tester.drag(scrollView, const Offset(0, -700));
      await tester.pumpAndSettle();

      // Y se fueron: o se desmontaron, o quedaron por encima del viewport.
      final gone = find.text('PÚBLICO').evaluate().isEmpty ||
          tester.getRect(find.text('PÚBLICO')).bottom <= viewportRect.top;
      expect(gone, isTrue, reason: 'las pills deberían haberse ido');
    });

    testWidgets('las pills vuelven al scrollear de nuevo hasta arriba', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), publicOverrides(longPosts())),
      );
      await tester.pumpAndSettle();

      final scrollView = feedScrollView();
      await tester.drag(scrollView, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.drag(scrollView, const Offset(0, 900));
      await tester.pumpAndSettle();

      final viewportRect = tester.getRect(scrollView);
      expect(find.byType(FeedSegmentPills), findsOneWidget);
      final pillsRect = tester.getRect(find.text('PÚBLICO'));
      expect(pillsRect.bottom, greaterThan(viewportRect.top));
      expect(pillsRect.top, lessThan(viewportRect.bottom));
    });

    // Acá vivía `post sliver preserves shell-safe bottom padding`, borrado en
    // #830. Leía del `SliverPadding` el mismo
    // `padding.bottom + TreinoBottomBar.minHeight` que escribía la pantalla, o
    // sea que comparaba producción contra una copia de producción: pasaba con
    // el bug adentro. Y encima corría en `_wrapProvider`, un `Scaffold` pelado
    // sin barra, donde `padding.bottom` vale 0 — así que el número que daba
    // por bueno (72) no era el de ninguna pantalla real.
    //
    // Lo reemplaza `shell_bottom_inset_test.dart`, que monta el feed en un
    // shell con `extendBody` y una `TreinoBottomBar` de verdad, scrollea hasta
    // el fondo y mide el hueco EFECTIVO contra la caja medida de la barra.

    testWidgets('loadMore still fires within 400px of the end', (tester) async {
      final posts = longPosts();
      final repository = _CountingPublicPostRepository(posts);

      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          postRepositoryProvider.overrideWithValue(repository),
        ]),
      );
      await tester.pumpAndSettle();
      expect(repository.pageRequests, 1);

      final scrollView = feedScrollView();
      final controller =
          tester.widget<CustomScrollView>(scrollView).controller!;
      controller.jumpTo(controller.position.maxScrollExtent - 399);
      await tester.pumpAndSettle();

      expect(repository.pageRequests, 2);
    });
  });

  // ── Sugerencias intercaladas ────────────────────────────────────────────
  //
  // `suggestedUsersAfterPost` ya tiene tests unitarios, pero probar la función
  // pura contra sí misma no protege la frontera: el feed podría no llamarla
  // nunca y esos tests seguirían verdes. Estos tests scrollean el feed REAL y
  // miran si el carrusel aparece entre los posts.
  group('sugerencias intercaladas en el scroll del feed', () {
    List<Post> manyPosts() => List.generate(
          24,
          (index) => _makePost(
            id: 'inter-$index',
            authorUid: 'author-$index',
            text: 'Post $index',
            privacy: PostPrivacy.public,
          ),
        );

    List<Override> overridesWith({
      required List<UserPublicProfile> candidates,
    }) =>
        [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => manyPosts()),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: 'gym-a')),
          ),
          suggestedUsersProvider('gym-a')
              .overrideWith((ref) async => candidates),
        ];

    List<UserPublicProfile> candidates(int count) => [
          for (var index = 0; index < count; index++)
            UserPublicProfile(
              uid: 'cand-$index',
              displayName: 'Candidato $index',
              gymId: 'gym-a',
            ),
        ];

    /// Baja de a poco hasta encontrar [target]. El `SliverList` es perezoso:
    /// el post 10 no existe en el árbol hasta que el viewport se le acerca.
    Future<bool> scrollUntil(WidgetTester tester, Finder target) async {
      for (var step = 0; step < 40; step++) {
        if (target.evaluate().isNotEmpty) return true;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      return target.evaluate().isNotEmpty;
    }

    testWidgets('con candidatos, el carrusel aparece después del post 10', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(
            const FeedScreen(), overridesWith(candidates: candidates(20))),
      );
      await tester.pumpAndSettle();

      final carousel = find.byKey(const Key('suggested_users_section'));
      expect(await scrollUntil(tester, carousel), isTrue,
          reason: 'el carrusel nunca se renderizó entre los posts');

      // Y está DEBAJO del post 10 (índice 9), no en cualquier lado.
      final post10 = find.byKey(const ValueKey('inter-9'));
      if (post10.evaluate().isNotEmpty) {
        expect(
          tester.getRect(carousel).top,
          greaterThan(tester.getRect(post10).top),
        );
      }
    });

    testWidgets(
        'el carrusel vuelve al principio después de reciclarse (regresión)', (
      tester,
    ) async {
      // Bug visto en device: `Scrollable` guarda su offset en `PageStorage` y
      // el `CustomScrollView` del feed abre ese bucket, así que al alejarse y
      // volver el carrusel reaparecía scrolleado al final —con las primeras
      // sugerencias escondidas—. Ningún test lo veía porque todos lo miraban
      // recién montado.
      await tester.pumpWidget(
        _wrapProvider(
          const FeedScreen(),
          overridesWith(candidates: candidates(20)),
        ),
      );
      await tester.pumpAndSettle();

      final carousel = find.byKey(const Key('suggested_users_section'));
      Finder row() =>
          find.descendant(of: carousel, matching: find.byType(ListView));
      double rowOffset() =>
          tester.widget<ListView>(row()).controller!.position.pixels;

      expect(await scrollUntil(tester, carousel), isTrue);
      // `scrollUntil` corta cuando el carrusel EXISTE, y el cacheExtent lo
      // construye antes de que se vea. Sin este ensureVisible el drag de abajo
      // no impacta y el test pasa sin haber probado nada.
      await tester.ensureVisible(carousel);
      await tester.pumpAndSettle();

      // Lo scrolleamos a mano hasta el fondo…
      await tester.drag(row(), const Offset(-1200, 0));
      await tester.pumpAndSettle();
      expect(rowOffset(), greaterThan(0),
          reason: 'setup del test: el carrusel tiene que haberse movido');

      // …lo sacamos del viewport para que el sliver lo destruya…
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      expect(carousel.evaluate(), isEmpty,
          reason: 'setup del test: el sliver tiene que haberlo reciclado');

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2500));
      await tester.pumpAndSettle();

      // …y al volver tiene que estar en cero otra vez.
      expect(await scrollUntil(tester, carousel), isTrue);
      expect(rowOffset(), 0,
          reason: 'una fila de sugerencias siempre empieza por la primera');
    });

    testWidgets('sin candidatos no se intercala nada en todo el scroll', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), overridesWith(candidates: const [])),
      );
      await tester.pumpAndSettle();

      final carousel = find.byKey(const Key('suggested_users_section'));
      expect(await scrollUntil(tester, carousel), isFalse);
    });
  });
}
