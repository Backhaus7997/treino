import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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
        find.byKey(const ValueKey('reaction-like-icon')),
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
      expect(
        find.byKey(const ValueKey('reaction-strong-icon')),
        findsNothing,
      );
    });

    testWidgets('hides counters whose value is zero', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          counts: const {
            ReactionType.like: 0,
            ReactionType.fire: 0,
            ReactionType.clap: 0,
          },
        ),
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reaction-like-count')),
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
            ReactionType.like: 3,
            ReactionType.fire: 1,
          },
        ),
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reaction-like-count')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reaction-clap-count')),
        findsNothing,
      );
    });

    for (final selectedType in ReactionType.values) {
      testWidgets('${selectedType.name} uses its dedicated active color',
          (tester) async {
        await tester.pumpWidget(_wrap(
          overrides: _reactionOverrides(
            counts: {selectedType: 1},
            myReaction: Reaction(
              uid: 'user-1',
              type: selectedType,
              createdAt: DateTime.utc(2026, 7, 30),
            ),
          ),
        ));
        await tester.pump();

        final context = tester.element(find.byType(PostReactionsRow));
        final palette = AppPalette.of(context);
        final expected = switch (selectedType) {
          ReactionType.like => palette.reactionLike,
          ReactionType.fire => palette.reactionFire,
          ReactionType.clap => palette.reactionClap,
        };
        final icon = tester.widget<Icon>(
          find.byKey(ValueKey('reaction-${selectedType.name}-icon')),
        );
        final count = tester.widget<Text>(
          find.byKey(ValueKey('reaction-${selectedType.name}-count')),
        );

        final expectedFilledIcon = switch (selectedType) {
          ReactionType.like => TreinoIcon.reactionLikeFill,
          ReactionType.fire => TreinoIcon.reactionFireFill,
          ReactionType.clap => TreinoIcon.reactionClapFill,
        };

        expect(icon.color, expected);
        expect(icon.color, isNot(palette.accent));
        expect(count.style?.color, expected);
        // La reacción propia va RELLENA, no solo teñida: un ícono de contorno
        // pintado se lee como un borde de color, no como reacción activa.
        expect(icon.icon, expectedFilledIcon);
      });
    }

    testWidgets('inactive reactions use the muted palette color',
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

      final palette = AppPalette.of(
        tester.element(find.byType(PostReactionsRow)),
      );
      for (final type in [ReactionType.like, ReactionType.clap]) {
        final icon = tester.widget<Icon>(
          find.byKey(ValueKey('reaction-${type.name}-icon')),
        );
        final expectedOutlineIcon = switch (type) {
          ReactionType.like => TreinoIcon.reactionLike,
          ReactionType.fire => TreinoIcon.reactionFire,
          ReactionType.clap => TreinoIcon.reactionClap,
        };
        expect(icon.color, palette.textMuted);
        // Las que no puso el usuario quedan en contorno: si todas fueran
        // rellenas, la fila competiría con el contenido del post.
        expect(icon.icon, expectedOutlineIcon);
      }
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
        find.byKey(const ValueKey('reaction-like-count')),
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

    test('contains no literal HEX colors', () {
      final source = File(
        'lib/features/feed/presentation/widgets/post_reactions_row.dart',
      ).readAsStringSync();

      expect(RegExp(r'0x[0-9A-Fa-f]{6,8}').hasMatch(source), isFalse);
    });

    testWidgets('exposes descriptive button semantics', (tester) async {
      // El handle se libera al final del cuerpo del test, NO con addTearDown:
      // los tearDowns corren después de _endOfTestVerifications, así que
      // Flutter todavía ve el handle activo y falla el test.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        overrides: _reactionOverrides(
          counts: const {ReactionType.like: 1},
        ),
      ));
      await tester.pump();

      final like = tester.getSemantics(
        find.byKey(const ValueKey('reaction-like-semantics')),
      );
      final fire = tester.getSemantics(
        find.byKey(const ValueKey('reaction-fire-semantics')),
      );
      final clap = tester.getSemantics(
        find.byKey(const ValueKey('reaction-clap-semantics')),
      );

      expect(like.label, contains('Me gusta, 1 reacción'));
      expect(fire.label, contains('Fuego, sin reacciones'));
      expect(clap.label, contains('Aplausos, sin reacciones'));

      handle.dispose();
    });
  });
}
