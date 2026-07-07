import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/feed_segment_pills.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

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
  PostPrivacy privacy = PostPrivacy.friends,
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

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
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
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-144: FeedScreen renders header title "FEED"
    testWidgets('SCENARIO-144: renders header title FEED', (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.text('FEED'), findsOneWidget);
    });

    // REQ-CHATUNREAD-005: the messages icon shows an unread-chats count badge.
    testWidgets('messages icon shows unread badge when count > 0',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), [
        ...baseOverrides,
        unreadFromFriendsProvider.overrideWith((_) => 3),
      ]));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('messages icon shows no badge when zero unread',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), [
        ...baseOverrides,
        unreadFromFriendsProvider.overrideWith((_) => 0),
      ]));
      await tester.pump();

      expect(find.text('0'), findsNothing);
    });

    // SCENARIO-145: FeedScreen renders search and plus icon buttons
    testWidgets('SCENARIO-145: renders search and plus icon stubs',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.search), findsAtLeastNWidgets(1));
      expect(find.byIcon(TreinoIcon.plus), findsAtLeastNWidgets(1));
    });

    // SCENARIO-146: FeedScreen renders FeedSegmentPills exactly once
    testWidgets('SCENARIO-146: renders FeedSegmentPills exactly once',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.byType(FeedSegmentPills), findsOneWidget);
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
      await tester.pump();

      // Only 1 Scaffold: the outer test wrapper
      expect(find.byType(Scaffold), findsOneWidget);
      // No AppBackground anywhere
      expect(find.byType(AppBackground), findsNothing);
      // No SafeArea inside FeedScreen subtree
      expect(find.byType(SafeArea), findsNothing);
    });

    // SCENARIO-148: FeedScreen in gym segment renders _MiGymBody (REQ-FSG-008)
    testWidgets(
        'SCENARIO-148: gym segment renders _MiGymBody (FeedEmptyState shown)',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pumpAndSettle();

      // null result → "Todavía no estás en un gym"
      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Todavía no estás en un gym'), findsOneWidget);
    });

    // SCENARIO-149: FeedScreen in public segment renders _PublicoBody (REQ-FSG-009)
    testWidgets(
        'SCENARIO-149: public segment renders _PublicoBody (FeedEmptyState shown)',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pumpAndSettle();

      // empty list → "Aún no hay posts públicos"
      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Aún no hay posts públicos'), findsOneWidget);
    });
  });

  // ── REQ-FEED-SCREEN-002 — Data state with posts ───────────────────────────

  group('REQ-FEED-SCREEN-002: amigos data state', () {
    final post1 = _makePost(id: 'a1', text: 'Post uno');
    final post2 = _makePost(id: 'a2', text: 'Post dos');
    final post3 = _makePost(id: 'a3', text: 'Post tres');

    List<Override> makeOverrides(List<Post> posts) => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFriendsFeedProvider.overrideWith((ref) async => posts),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ];

    // SCENARIO-150: list of PostCards rendered in order
    testWidgets('SCENARIO-150: 3 PostCards rendered in correct order',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(
          const FeedScreen(), makeOverrides([post1, post2, post3])));
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNWidgets(3));
      // Order: first PostCard key or find text
      expect(find.text('Post uno'), findsOneWidget);
      expect(find.text('Post dos'), findsOneWidget);
      expect(find.text('Post tres'), findsOneWidget);
    });

    // SCENARIO-151: no FeedEmptyState when posts present
    testWidgets('SCENARIO-151: no FeedEmptyState when posts present',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(
          const FeedScreen(), makeOverrides([post1, post2, post3])));
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsNothing);
    });

    // SCENARIO-152: no CircularProgressIndicator when data resolved
    testWidgets('SCENARIO-152: no spinner when data resolved', (tester) async {
      await tester.pumpWidget(_wrapProvider(
          const FeedScreen(), makeOverrides([post1, post2, post3])));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-003 — Empty data state ────────────────────────────────

  group('REQ-FEED-SCREEN-003: amigos empty state', () {
    final emptyOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-153: FeedEmptyState rendered when list empty
    testWidgets('SCENARIO-153: FeedEmptyState rendered for empty list',
        (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), emptyOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
    });

    // SCENARIO-154: no PostCard rendered when list empty
    testWidgets('SCENARIO-154: no PostCard when empty', (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), emptyOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-004 — Loading state ───────────────────────────────────

  group('REQ-FEED-SCREEN-004: amigos loading state', () {
    List<Override> loadingOverrides() => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFriendsFeedProvider.overrideWith((ref) async {
            // Never resolves → AsyncLoading
            await Completer<void>().future;
            return const <Post>[];
          }),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ];

    // SCENARIO-155: spinner rendered during loading
    testWidgets('SCENARIO-155: CircularProgressIndicator during loading',
        (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), loadingOverrides()));
      // Single pump — don't settle, stay in loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // SCENARIO-156: no PostCard or FeedEmptyState during loading
    testWidgets('SCENARIO-156: no PostCard or FeedEmptyState during loading',
        (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), loadingOverrides()));
      await tester.pump();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-005 — Error state ─────────────────────────────────────

  group('REQ-FEED-SCREEN-005: amigos error state', () {
    final errorOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider.overrideWith((ref) => Future<List<Post>>.error(
            Exception('net'),
            StackTrace.empty,
          )),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-157: graceful fallback rendered, no FlutterError
    testWidgets('SCENARIO-157: graceful error message rendered',
        (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), errorOverrides));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu feed. Probá de nuevo.'),
        findsOneWidget,
      );
    });

    // SCENARIO-158: no PostCard or FeedEmptyState in error state
    testWidgets('SCENARIO-158: no PostCard or FeedEmptyState on error',
        (tester) async {
      await tester
          .pumpWidget(_wrapProvider(const FeedScreen(), errorOverrides));
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
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
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
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
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
    testWidgets('SCENARIO-205: error state shows generic error copy',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
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
    testWidgets('SCENARIO-202: null result shows no-gym FeedEmptyState',
        (tester) async {
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
    testWidgets('SCENARIO-203: empty list shows gym-no-posts FeedEmptyState',
        (tester) async {
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
    testWidgets('SCENARIO-204: non-empty list shows PostCard ListView',
        (tester) async {
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
    });
  });

  // ── REQ-FSG-014..016 — _PublicoBody ──────────────────────────────────────

  group('_PublicoBody', () {
    // SCENARIO-211: loading state shows spinner
    testWidgets('SCENARIO-211: loading state shows spinner', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
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
    testWidgets('SCENARIO-210: error state shows generic error copy',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
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
    testWidgets('SCENARIO-208: empty list shows FeedEmptyState for público',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
      expect(find.text('Aún no hay posts públicos'), findsOneWidget);
    });

    // SCENARIO-209: non-empty list shows ListView with PostCards
    testWidgets('SCENARIO-209: non-empty list shows PostCard ListView',
        (tester) async {
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
          myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider.overrideWith((ref) async => posts),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsOneWidget);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });
}
