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

  // #1701: una sesión sin carga no tiene tile de volumen, así que la tarjeta
  // se arma con 3. El tercero no puede dejar una celda vacía al lado.
  group('SessionStatsCard con 3 tiles', () {
    final threeTiles = [_tiles[0], _tiles[2], _tiles[3]];

    testWidgets(
        'dibuja los 3 tiles y sólo UN divisor vertical (el de la fila 1)',
        (tester) async {
      await tester.pumpWidget(_wrap(SessionStatsCard(tiles: threeTiles)));

      expect(find.byType(StatTile), findsNWidgets(3));
      expect(find.text('DURACIÓN'), findsOneWidget);
      expect(find.text('SETS'), findsOneWidget);
      expect(find.text('PRS HOY'), findsOneWidget);
      // La fila de abajo es de una sola celda: sin divisor vertical, o se
      // leería como un tile que no cargó.
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('el tercer tile ocupa el ancho entero de la tarjeta',
        (tester) async {
      await tester.pumpWidget(_wrap(SessionStatsCard(tiles: threeTiles)));

      final cardWidth = tester.getSize(find.byType(SessionStatsCard)).width;
      final lastCell = find.ancestor(
        of: find.text('PRS HOY'),
        matching: find.byType(Expanded),
      );
      // Un único Expanded envuelve al tile de la fila de abajo, y llena la
      // tarjeta menos el borde de 1px a cada lado.
      expect(tester.getSize(lastCell.first).width, cardWidth - 2);
    });

    testWidgets('el stagger de entrada sigue el orden visual de los 3',
        (tester) async {
      await tester.pumpWidget(
        _wrap(SessionStatsCard(animateTiles: true, tiles: threeTiles)),
      );

      final entries = tester.widgetList<TreinoFadeSlideIn>(
        find.descendant(
          of: find.byType(SessionStatsCard),
          matching: find.byType(TreinoFadeSlideIn),
        ),
      );
      expect(entries.map((e) => e.delay), [
        Duration.zero + AppMotion.stagger(0),
        Duration.zero + AppMotion.stagger(1),
        Duration.zero + AppMotion.stagger(2),
      ]);
    });

    test('con 2 o 5 tiles sigue asertando', () {
      expect(
        () => SessionStatsCard(tiles: _tiles.take(2).toList()),
        throwsAssertionError,
      );
      expect(
        () => SessionStatsCard(tiles: [..._tiles, _tiles.first]),
        throwsAssertionError,
      );
    });
  });
}
