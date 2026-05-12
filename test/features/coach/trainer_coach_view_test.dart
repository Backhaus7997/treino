import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';

void main() {
  group('TrainerCoachView', () {
    Widget buildSubject() => MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: TrainerCoachView()),
        );

    testWidgets('renders 4 sub-tab labels in a TabBar', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsWidgets);
      expect(find.text('ALUMNOS'), findsWidgets);
      expect(find.text('AGENDA'), findsWidgets);
      expect(find.text('COMUNIDADES'), findsWidgets);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('DASHBOARD tab body shows PRÓXIMAMENTE on initial render',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('PRÓXIMAMENTE'), findsOneWidget);
    });

    testWidgets('tapping ALUMNOS tab reveals its placeholder body',
        (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Tap the ALUMNOS label in the TabBar
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      // Body inside TabBarView should now show ALUMNOS label
      expect(
        find.descendant(
          of: find.byType(TabBarView),
          matching: find.text('ALUMNOS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('contains exactly one TabBar', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsOneWidget);
    });
  });
}
