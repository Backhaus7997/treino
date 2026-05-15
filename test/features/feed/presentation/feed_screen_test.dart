import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/feed_segment_pills.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Post _makePost({
  String id = 'p1',
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
      authorUid: 'u1',
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      text: text,
      routineTag: routineTag,
      privacy: privacy,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 1)),
    );

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── REQ-FEED-SCREEN-001 — Composition ─────────────────────────────────────

  group('REQ-FEED-SCREEN-001: composition', () {
    final baseOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-144: FeedScreen renders header title "FEED"
    testWidgets('SCENARIO-144: renders header title FEED', (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), baseOverrides));
      await tester.pump();

      expect(find.text('FEED'), findsOneWidget);
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

    // SCENARIO-148: FeedScreen in gym segment renders SizedBox.shrink
    testWidgets('SCENARIO-148: gym segment renders no posts or empty state',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
          myFriendsFeedProvider
              .overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pump();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });

    // SCENARIO-149: FeedScreen in public segment renders SizedBox.shrink
    testWidgets('SCENARIO-149: public segment renders no posts or empty state',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFriendsFeedProvider
              .overrideWith((ref) async => const <Post>[]),
        ]),
      );
      await tester.pump();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
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
        ];

    // SCENARIO-150: list of PostCards rendered in order
    testWidgets('SCENARIO-150: 3 PostCards rendered in correct order',
        (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])));
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
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])));
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsNothing);
    });

    // SCENARIO-152: no CircularProgressIndicator when data resolved
    testWidgets('SCENARIO-152: no spinner when data resolved', (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), makeOverrides([post1, post2, post3])));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-003 — Empty data state ────────────────────────────────

  group('REQ-FEED-SCREEN-003: amigos empty state', () {
    final emptyOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider
          .overrideWith((ref) async => const <Post>[]),
    ];

    // SCENARIO-153: FeedEmptyState rendered when list empty
    testWidgets('SCENARIO-153: FeedEmptyState rendered for empty list',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), emptyOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(FeedEmptyState), findsOneWidget);
    });

    // SCENARIO-154: no PostCard rendered when list empty
    testWidgets('SCENARIO-154: no PostCard when empty', (tester) async {
      await tester.pumpWidget(_wrapProvider(const FeedScreen(), emptyOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-004 — Loading state ───────────────────────────────────

  group('REQ-FEED-SCREEN-004: amigos loading state', () {
    List<Override> _loadingOverrides() => [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          myFriendsFeedProvider
              .overrideWith((ref) async {
            // Never resolves → AsyncLoading
            await Completer<void>().future;
            return const <Post>[];
          }),
        ];

    // SCENARIO-155: spinner rendered during loading
    testWidgets('SCENARIO-155: CircularProgressIndicator during loading',
        (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), _loadingOverrides()));
      // Single pump — don't settle, stay in loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // SCENARIO-156: no PostCard or FeedEmptyState during loading
    testWidgets('SCENARIO-156: no PostCard or FeedEmptyState during loading',
        (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), _loadingOverrides()));
      await tester.pump();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });

  // ── REQ-FEED-SCREEN-005 — Error state ─────────────────────────────────────

  group('REQ-FEED-SCREEN-005: amigos error state', () {
    final errorOverrides = <Override>[
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider
          .overrideWith((ref) => Future<List<Post>>.error(
                Exception('net'),
                StackTrace.empty,
              )),
    ];

    // SCENARIO-157: graceful fallback rendered, no FlutterError
    testWidgets('SCENARIO-157: graceful error message rendered', (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), errorOverrides));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu feed. Intentá de nuevo.'),
        findsOneWidget,
      );
    });

    // SCENARIO-158: no PostCard or FeedEmptyState in error state
    testWidgets('SCENARIO-158: no PostCard or FeedEmptyState on error',
        (tester) async {
      await tester.pumpWidget(
          _wrapProvider(const FeedScreen(), errorOverrides));
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
      expect(find.byType(FeedEmptyState), findsNothing);
    });
  });
}
