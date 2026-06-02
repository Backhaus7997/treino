import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_display.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('StarRatingDisplay', () {
    testWidgets('SCENARIO-612: renders exactly 5 star icons', (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: 3.0),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final starIcons = icons
          .where((i) =>
              i.icon == TreinoIcon.starFill || i.icon == TreinoIcon.starOutline)
          .toList();
      expect(starIcons.length, equals(5));
    });

    testWidgets('SCENARIO-612: rating==4.7 → 4 filled + 1 outline',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: 4.7),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final fillCount =
          icons.where((i) => i.icon == TreinoIcon.starFill).length;
      final outlineCount =
          icons.where((i) => i.icon == TreinoIcon.starOutline).length;
      expect(fillCount, equals(4));
      expect(outlineCount, equals(1));
    });

    testWidgets('SCENARIO-612: rating==null → all 5 stars are outline',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: null),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final fillCount =
          icons.where((i) => i.icon == TreinoIcon.starFill).length;
      expect(fillCount, equals(0));
    });

    testWidgets('SCENARIO-612: rating==5.0 → all 5 stars are filled',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: 5.0),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final fillCount =
          icons.where((i) => i.icon == TreinoIcon.starFill).length;
      expect(fillCount, equals(5));
    });

    testWidgets(
        'SCENARIO-612: no GestureDetector present (read-only, not interactive)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: 3.0),
      ));

      // StarRatingDisplay must NOT have GestureDetectors (read-only)
      expect(
        find.descendant(
          of: find.byType(StarRatingDisplay),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'SCENARIO-612: icons are TreinoIcon.starFill/starOutline — no PhosphorIcons direct',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StarRatingDisplay(rating: 2.0),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final starIcons = icons
          .where((i) =>
              i.icon == TreinoIcon.starFill || i.icon == TreinoIcon.starOutline)
          .toList();
      expect(starIcons.length, equals(5));
    });
  });
}
