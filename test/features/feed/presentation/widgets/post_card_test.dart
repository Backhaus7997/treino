import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';

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
    );

Widget _wrap(Widget w) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

Widget _wrapRouter(Widget w, {List<Override> overrides = const []}) {
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
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
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

    // SCENARIO-173: stats row present with em-dashes
    testWidgets('SCENARIO-173: stats row contains em-dash text',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final dashFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.contains('—'),
      );
      expect(dashFinder, findsAtLeastNWidgets(1));
    });

    // SCENARIO-174: stats row contains no real numeric data
    testWidgets('SCENARIO-174: stats row has no real numeric values',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final numericStatsFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'\d+ kg|\d+ min|\d+ ej').hasMatch(w.data!),
      );
      expect(numericStatsFinder, findsNothing);
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

    // SCENARIO-176: dotsThree icon present
    testWidgets('SCENARIO-176: dotsThree icon is present', (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsOneWidget);
    });

    // SCENARIO-177: tapping dotsThree does nothing (no crash, no navigation)
    testWidgets('SCENARIO-177: tapping dotsThree does not throw',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      // IconButton with onPressed: null — tap is safe no-op
      final iconButtons = find.byType(IconButton);
      expect(iconButtons, findsAtLeastNWidgets(1));
      // Tapping a disabled IconButton should not throw
      await tester.tap(iconButtons.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      // No exception means pass
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
  });
}
