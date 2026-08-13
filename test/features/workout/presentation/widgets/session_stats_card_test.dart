import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/workout/presentation/widgets/session_stats_card.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';

const _tiles = [
  StatTile(label: 'DURACIÓN', value: '52'),
  StatTile(label: 'VOLUMEN', value: '3200'),
  StatTile(label: 'SETS', value: '22'),
  StatTile(label: 'PRS HOY', value: '1'),
];

Widget _wrap(SessionStatsCard card) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: card),
    );

void main() {
  group('SessionStatsCard tile entry', () {
    testWidgets('does not wrap tiles when animation is disabled by default',
        (tester) async {
      await tester.pumpWidget(
        _wrap(SessionStatsCard(tiles: _tiles)),
      );

      final card = find.byType(SessionStatsCard);
      expect(
        find.descendant(
          of: card,
          matching: find.byType(TreinoFadeSlideIn),
        ),
        findsNothing,
      );
    });

    testWidgets('wraps exactly four tiles when animation is enabled',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SessionStatsCard(
            animateTiles: true,
            tiles: _tiles,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SessionStatsCard),
          matching: find.byType(TreinoFadeSlideIn),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('applies entry delay plus visual-order stagger to each tile',
        (tester) async {
      final entryDelay = AppMotion.stagger(2);
      await tester.pumpWidget(
        _wrap(
          SessionStatsCard(
            animateTiles: true,
            entryDelay: entryDelay,
            tiles: _tiles,
          ),
        ),
      );

      final entries = tester
          .widgetList<TreinoFadeSlideIn>(
            find.descendant(
              of: find.byType(SessionStatsCard),
              matching: find.byType(TreinoFadeSlideIn),
            ),
          )
          .toList();

      expect(
        entries.map((entry) => entry.delay),
        List.generate(
          4,
          (index) => entryDelay + AppMotion.stagger(index),
        ),
      );
      expect(
        entries.map((entry) => entry.child),
        orderedEquals(_tiles),
      );
    });
  });
}
