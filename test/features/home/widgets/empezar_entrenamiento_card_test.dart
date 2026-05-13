import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/home/widgets/empezar_entrenamiento_card.dart';
import 'package:treino/features/home/widgets/home_cta_button.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: w)),
    );

void main() {
  group('EmpezarEntrenamientoCard', () {
    testWidgets('REQ-HOME-EMPEZAR-001: all 6 hardcoded strings present',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmpezarEntrenamientoCard()));
      await tester.pump();

      expect(find.text('HOY · JUEVES'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('Pecho · Hombros · Tríceps'), findsOneWidget);
      expect(find.text('6 ejercicios'), findsOneWidget);
      expect(find.text('~55 min'), findsOneWidget);
      expect(find.text('EMPEZAR ENTRENAMIENTO'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-002: stat row uses TreinoIcon.tabWorkout and TreinoIcon.clock',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmpezarEntrenamientoCard()));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.tabWorkout), findsAtLeastNWidgets(1));
      expect(find.byIcon(TreinoIcon.clock), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-003: card decoration — bgCard, r=20, border non-null',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmpezarEntrenamientoCard()));
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

    testWidgets('REQ-HOME-EMPEZAR-004: tap no-op — no exception, no navigation',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmpezarEntrenamientoCard()));
      await tester.pump();

      await tester.tap(find.byType(HomeCTAButton));
      await tester.pumpAndSettle();
      // No exception = pass
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-001: HomeCTAButton found with label + TreinoIcon.play leading',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmpezarEntrenamientoCard()));
      await tester.pump();

      expect(find.byType(HomeCTAButton), findsOneWidget);
      final btn = tester.widget<HomeCTAButton>(find.byType(HomeCTAButton));
      expect(btn.label, equals('EMPEZAR ENTRENAMIENTO'));
      expect(btn.leadingIcon, equals(TreinoIcon.play));
    });
  });
}
