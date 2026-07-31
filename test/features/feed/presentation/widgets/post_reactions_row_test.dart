import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/feed/application/reaction_providers.dart';
import 'package:treino/features/feed/domain/reaction.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';
import 'package:treino/features/feed/presentation/widgets/post_reactions_row.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockReactionActionsNotifier extends Mock
    implements ReactionActionsNotifier {}

Widget _wrap({
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(
          body: PostReactionsRow(postId: 'post-1'),
        ),
      ),
    );

List<Override> _reactionOverrides({
  Map<ReactionType, int> counts = const {},
  Reaction? myReaction,
  ReactionActionsNotifier? actions,
}) =>
    [
      reactionCountsProvider('post-1').overrideWith(
        (ref) => Stream.value(counts),
      ),
      myReactionProvider('post-1').overrideWith(
        (ref) => Stream.value(myReaction),
      ),
      if (actions != null) reactionActionsProvider.overrideWithValue(actions),
    ];

void main() {
  group('PostReactionsRow', () {
    testWidgets('renders all three reaction types', (tester) async {
      await tester.pumpWidget(_wrap(overrides: _reactionOverrides()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reaction-strong-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reaction-fire-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reaction-clap-icon')),
        findsOneWidget,
      );
    });

    testWidgets('hides counters whose value is zero', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          counts: const {
            ReactionType.strong: 0,
            ReactionType.fire: 0,
            ReactionType.clap: 0,
          },
        ),
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reaction-strong-count')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reaction-fire-count')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reaction-clap-count')),
        findsNothing,
      );
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows counters whose value is greater than zero',
        (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          counts: const {
            ReactionType.strong: 3,
            ReactionType.fire: 1,
          },
        ),
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reaction-strong-count')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reaction-clap-count')),
        findsNothing,
      );
    });

    testWidgets('uses accent only for the current user reaction',
        (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          myReaction: Reaction(
            uid: 'user-1',
            type: ReactionType.fire,
            createdAt: DateTime.utc(2026, 7, 30),
          ),
        ),
      ));
      await tester.pump();

      final context = tester.element(find.byType(PostReactionsRow));
      final palette = AppPalette.of(context);
      final strong = tester.widget<Icon>(
        find.byKey(const ValueKey('reaction-strong-icon')),
      );
      final fire = tester.widget<Icon>(
        find.byKey(const ValueKey('reaction-fire-icon')),
      );
      final clap = tester.widget<Icon>(
        find.byKey(const ValueKey('reaction-clap-icon')),
      );

      expect(fire.color, palette.accent);
      expect(strong.color, palette.textMuted);
      expect(clap.color, palette.textMuted);
      expect(strong.color, isNot(palette.accent));
      expect(clap.color, isNot(palette.accent));
    });

    testWidgets('tapping a reaction delegates the post id and type',
        (tester) async {
      final actions = MockReactionActionsNotifier();
      when(
        () => actions.toggle(
          postId: 'post-1',
          type: ReactionType.fire,
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(actions: actions),
      ));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('reaction-fire-icon')),
      );
      await tester.pump();

      verify(
        () => actions.toggle(
          postId: 'post-1',
          type: ReactionType.fire,
        ),
      ).called(1);
    });

    testWidgets('loading renders icons without counters or spinners',
        (tester) async {
      final counts = StreamController<Map<ReactionType, int>>();
      final mine = StreamController<Reaction?>();
      addTearDown(counts.close);
      addTearDown(mine.close);

      await tester.pumpWidget(_wrap(
        overrides: [
          reactionCountsProvider('post-1').overrideWith(
            (ref) => counts.stream,
          ),
          myReactionProvider('post-1').overrideWith(
            (ref) => mine.stream,
          ),
        ],
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('post-reactions-row')),
        findsOneWidget,
      );
      expect(find.byType(Icon), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('reaction-strong-count')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not use entry animation inside the reactions row',
        (tester) async {
      await tester.pumpWidget(_wrap(overrides: _reactionOverrides()));
      await tester.pump();

      final row = find.byKey(const ValueKey('post-reactions-row'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.byType(TreinoFadeSlideIn),
        ),
        findsNothing,
      );
    });

    testWidgets('exposes descriptive button semantics', (tester) async {
      // El handle se libera al final del cuerpo del test, NO con addTearDown:
      // los tearDowns corren después de _endOfTestVerifications, así que
      // Flutter todavía ve el handle activo y falla el test.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          counts: const {ReactionType.strong: 1},
        ),
      ));
      await tester.pump();

      final strong = tester.getSemantics(
        find.byKey(const ValueKey('reaction-strong-semantics')),
      );
      final fire = tester.getSemantics(
        find.byKey(const ValueKey('reaction-fire-semantics')),
      );
      final clap = tester.getSemantics(
        find.byKey(const ValueKey('reaction-clap-semantics')),
      );

      expect(strong.label, contains('Fuerza, 1 reacción'));
      expect(fire.label, contains('Fuego, sin reacciones'));
      expect(clap.label, contains('Aplausos, sin reacciones'));

      handle.dispose();
    });
  });
}
