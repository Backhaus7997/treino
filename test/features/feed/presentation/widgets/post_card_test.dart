import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/domain/workout_stats.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockPostRepository extends Mock implements PostRepository {}

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

Post makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  String text = 'Gran sesión hoy',
  RoutineTag? routineTag,
  PostPrivacy privacy = PostPrivacy.friends,
  DateTime? createdAt,
  WorkoutStats? workoutStats,
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
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 2)),
      workoutStats: workoutStats,
    );

/// Wraps [PostCard] with a viewer identity ([viewerUid], `null` = signed out)
/// so ownership-gated UI (the overflow menu) can be exercised.
Widget _wrap(
  Widget w, {
  String? viewerUid = 'u1',
  MockPostRepository? mockRepo,
}) {
  final user = viewerUid == null ? null : _MockUser(uid: viewerUid);
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
      if (mockRepo != null) postRepositoryProvider.overrideWithValue(mockRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: w),
    ),
  );
}

Widget _wrapRouter(
  Widget w, {
  String? viewerUid = 'u1',
  MockPostRepository? mockRepo,
  List<Override> overrides = const [],
}) {
  final user = viewerUid == null ? null : _MockUser(uid: viewerUid);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: w),
      ),
      GoRoute(
        path: '/workout/routine/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/feed/create',
        builder: (_, state) => const Scaffold(body: Text('create-screen')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
      if (mockRepo != null) postRepositoryProvider.overrideWithValue(mockRepo),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('PostCard', () {
    // SCENARIO-166: author display name is rendered
    testWidgets('SCENARIO-166: renders authorDisplayName', (tester) async {
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Tincho'), findsOneWidget);
    });

    // SCENARIO-167: gym ID rendered when non-null
    testWidgets('SCENARIO-167: renders gymId when non-null', (tester) async {
      final post = makePost(authorGymId: 'gym-la-fuerza');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      // gymId uppercased in meta row — case-insensitive search
      final gymFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            w.data!.toLowerCase().contains('gym-la-fuerza'),
      );
      expect(gymFinder, findsAtLeastNWidgets(1));
    });

    // SCENARIO-168: timestamp rendered as relative string
    testWidgets('SCENARIO-168: renders relative timestamp', (tester) async {
      final post = makePost(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final timestampFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'[Hh]ace\s+\d+\s*h').hasMatch(w.data!),
      );
      expect(timestampFinder, findsAtLeastNWidgets(1));
    });

    // SCENARIO-169: body text rendered
    testWidgets('SCENARIO-169: renders post body text', (tester) async {
      final post = makePost(text: 'Gran sesión hoy');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Gran sesión hoy'), findsOneWidget);
    });

    // SCENARIO-170: routine tag chip rendered when routineTag present
    testWidgets('SCENARIO-170: renders routine tag chip when routineTag is set',
        (tester) async {
      final post = makePost(
        routineTag:
            const RoutineTag(routineId: 'r1', routineName: 'Push · Día 4'),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Push · Día 4'), findsOneWidget);
    });

    // SCENARIO-171: tapping routine tag chip navigates to /workout/routine/:id
    testWidgets(
        'SCENARIO-171: tapping routine chip navigates to /workout/routine/:id',
        (tester) async {
      final post = makePost(
        routineTag:
            const RoutineTag(routineId: 'r1', routineName: 'Push · Día 4'),
      );
      await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
      await tester.pump();

      await tester.tap(find.text('Push · Día 4'));
      await tester.pumpAndSettle();

      expect(find.text('detail-r1'), findsOneWidget);
    });

    // SCENARIO-172: no chip rendered when routineTag is null
    testWidgets('SCENARIO-172: no chip rendered when routineTag is null',
        (tester) async {
      final post = makePost(routineTag: null);
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Push · Día 4'), findsNothing);
      // No chip-like widget containing routine name text
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              RegExp(r'Push|Día|routine').hasMatch(w.data!),
        ),
        findsNothing,
      );
    });

    // QA-FEED-364/389: the old always-empty "— kg / — min / — ej." stub is
    // gone. A post with no workout behind it (manual/legacy → workoutStats
    // null) shows NO stats row at all — not a permanent em-dash placeholder.
    testWidgets(
        'QA-FEED-364/389: no stats row (no em-dash stub) when workoutStats is null',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('— kg'), findsNothing);
      expect(find.text('— min'), findsNothing);
      expect(find.text('— ej.'), findsNothing);
      // "ej." is unique to the stats row → its absence proves the row is gone.
      expect(find.textContaining('ej.'), findsNothing);
    });

    // QA-FEED-364/389: a share-a-workout post (workoutStats present) shows the
    // REAL volume / duration / exercise numbers instead of the em-dash stub.
    testWidgets(
        'QA-FEED-364/389: renders real volume/duration/exercise stats when '
        'workoutStats is present', (tester) async {
      final post = makePost(
        workoutStats: const WorkoutStats(
          volumeKg: 3.2,
          durationMin: 52,
          exerciseCount: 6,
        ),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('3.2 kg'), findsOneWidget);
      expect(find.text('52 min'), findsOneWidget);
      expect(find.text('6 ej.'), findsOneWidget);
      // And never the old em-dash stub.
      expect(find.text('— kg'), findsNothing);
    });

    // SCENARIO-175: card container decoration — borderRadius, bgCard color, border
    testWidgets('SCENARIO-175: card has correct decoration', (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      const palette = AppPalette.mintMagenta;

      final containers = tester.widgetList<Container>(find.byType(Container));
      bool foundCard = false;
      for (final container in containers) {
        final dec = container.decoration;
        if (dec is BoxDecoration) {
          if (dec.color == palette.bgCard &&
              dec.borderRadius == BorderRadius.circular(20) &&
              dec.border != null) {
            foundCard = true;
            break;
          }
        }
      }
      expect(foundCard, isTrue,
          reason:
              'Expected a Container with bgCard color, r-20 borderRadius and non-null border');
    });

    // SCENARIO-176: dotsThree icon present for the post's own author (owner)
    testWidgets('SCENARIO-176: dotsThree icon is present for the owner',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: 'u1'));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsOneWidget);
    });

    // SCENARIO-177: menu button is absent for a non-owner viewer
    testWidgets('SCENARIO-177: overflow menu hidden when viewer is not owner',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: 'u2'));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsNothing);
    });

    testWidgets('overflow menu hidden when viewer is unauthenticated',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: null));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsNothing);
    });

    // SCENARIO-178: author tap no-op when onAuthorTap is null
    testWidgets('SCENARIO-178: author tap is no-op when onAuthorTap is null',
        (tester) async {
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(_wrap(PostCard(post: post, onAuthorTap: null)));
      await tester.pump();

      await tester.tap(find.text('Tincho'));
      await tester.pumpAndSettle();
      // No exception means pass
    });

    // SCENARIO-179: onAuthorTap callback fires when provided
    testWidgets('SCENARIO-179: onAuthorTap fires when tapped', (tester) async {
      var tapped = false;
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(
        _wrap(PostCard(post: post, onAuthorTap: () => tapped = true)),
      );
      await tester.pump();

      await tester.tap(find.text('Tincho'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    // ── Owner overflow menu: Editar/Eliminar ──────────────────────────────

    group('overflow menu (owner)', () {
      testWidgets('tapping dotsThree opens a menu with Editar and Eliminar',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('Eliminar'), findsOneWidget);
      });

      testWidgets('tapping Editar navigates to the create/edit route',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();

        expect(find.text('create-screen'), findsOneWidget);
      });

      testWidgets('tapping Eliminar shows a confirmation dialog',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('¿Eliminar este post?'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
      });

      testWidgets('confirming delete calls repository.delete with post.id',
          (tester) async {
        final repo = MockPostRepository();
        when(() => repo.delete(any())).thenAnswer((_) async {});
        final post = makePost(id: 'p-to-delete', authorUid: 'u1');

        await tester.pumpWidget(
          _wrapRouter(PostCard(post: post), mockRepo: repo),
        );
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        // Dialog shows "Eliminar" as the confirm button too — tap the one
        // inside the AlertDialog specifically.
        final confirmButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Eliminar'),
        );
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        verify(() => repo.delete('p-to-delete')).called(1);
      });

      testWidgets(
          'cancelling the delete dialog does not call repository.delete',
          (tester) async {
        final repo = MockPostRepository();
        final post = makePost(id: 'p1', authorUid: 'u1');

        await tester.pumpWidget(
          _wrapRouter(PostCard(post: post), mockRepo: repo),
        );
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        verifyNever(() => repo.delete(any()));
        expect(find.byType(AlertDialog), findsNothing);
      });
    });
  });
}
