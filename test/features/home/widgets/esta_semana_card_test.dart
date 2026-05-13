import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('EstaSemanaCard', () {
    testWidgets('REQ-HOME-SEMANA-001: renders title "ESTA SEMANA"',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();
      expect(find.text('ESTA SEMANA'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SEMANA-001: renders placeholder body, no streak, no SVG',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();

      expect(
        find.text('Todavía no entrenaste esta semana.'),
        findsOneWidget,
      );
      // No streak number (e.g. "5 DÍAS")
      expect(find.textContaining(RegExp(r'\d+ DÍAS')), findsNothing);
      // No muscle map SVG
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('REQ-HOME-SEMANA-002: card decoration — bgCard, r=20, border',
        (tester) async {
      await tester.pumpWidget(_wrap(const EstaSemanaCard()));
      await tester.pump();

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(
        decoration.borderRadius,
        equals(BorderRadius.circular(20)),
      );
      expect(decoration.color, equals(AppPalette.mintMagenta.bgCard));
      expect(decoration.border, isNotNull);
    });
  });
}
