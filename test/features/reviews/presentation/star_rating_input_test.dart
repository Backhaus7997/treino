import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_input.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('StarRatingInput', () {
    testWidgets('SCENARIO-600: renders exactly 5 star icons', (tester) async {
      int? received;
      await tester.pumpWidget(_wrap(
        StarRatingInput(rating: 0, onRatingChanged: (v) => received = v),
      ));

      // 5 Icon widgets with star-related IconData
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final starIcons = icons
          .where((i) =>
              i.icon == TreinoIcon.starFill || i.icon == TreinoIcon.starOutline)
          .toList();
      expect(starIcons.length, equals(5));
    });

    testWidgets('SCENARIO-600: tapping star 3 calls onRatingChanged(3)',
        (tester) async {
      int? received;
      await tester.pumpWidget(_wrap(
        StarRatingInput(rating: 0, onRatingChanged: (v) => received = v),
      ));

      // Stars are GestureDetector children — find all GestureDetectors under StarRatingInput
      final gestures = find.descendant(
        of: find.byType(StarRatingInput),
        matching: find.byType(GestureDetector),
      );
      // Tap the 3rd gesture detector (index 2)
      await tester.tap(gestures.at(2));
      await tester.pump();

      expect(received, equals(3));
    });

    testWidgets('SCENARIO-600: rating==0 → all 5 stars are outline',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StarRatingInput(rating: 0, onRatingChanged: (_) {}),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final fillCount = icons.where((i) => i.icon == TreinoIcon.starFill).length;
      expect(fillCount, equals(0));
    });

    testWidgets('SCENARIO-600: rating==4 → 4 filled + 1 outline',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StarRatingInput(rating: 4, onRatingChanged: (_) {}),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final fillCount = icons.where((i) => i.icon == TreinoIcon.starFill).length;
      final outlineCount =
          icons.where((i) => i.icon == TreinoIcon.starOutline).length;
      expect(fillCount, equals(4));
      expect(outlineCount, equals(1));
    });

    testWidgets(
        'SCENARIO-600: icons are TreinoIcon.starFill/starOutline — no PhosphorIcons direct',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StarRatingInput(rating: 2, onRatingChanged: (_) {}),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final starIcons = icons
          .where((i) =>
              i.icon == TreinoIcon.starFill || i.icon == TreinoIcon.starOutline)
          .toList();
      // All 5 stars should use TreinoIcon constants
      expect(starIcons.length, equals(5));
    });
  });
}
