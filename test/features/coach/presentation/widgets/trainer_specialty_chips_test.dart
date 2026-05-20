import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_specialty_chips.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('TrainerSpecialtyChips — SCENARIO-430/431 T28/T29', () {
    testWidgets('SCENARIO-430: renders 11 chips (Todos + 10 specialties)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: null,
          onChanged: (_) {},
        ),
      ));

      // 11 chips total: "Todos" + 10 specialty labels
      expect(find.byType(ChoiceChip), findsNWidgets(11));
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Powerlifting'), findsOneWidget);
      expect(find.text('CrossFit'), findsOneWidget);
      expect(find.text('Bodybuilding'), findsOneWidget);
      expect(find.text('Hipertrofia'), findsOneWidget);
      expect(find.text('Wellness'), findsOneWidget);
      expect(find.text('Kinesiología'), findsOneWidget);
      expect(find.text('Funcional'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('Calistenia'), findsOneWidget);
    });

    testWidgets('"Todos" chip is selected when selected is null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: null,
          onChanged: (_) {},
        ),
      ));

      final todosChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Todos'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(todosChip.selected, isTrue);
    });

    testWidgets('specialty chip is selected when matching selected param',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: TrainerSpecialty.crossfit,
          onChanged: (_) {},
        ),
      ));

      final crossfitChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('CrossFit'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(crossfitChip.selected, isTrue);

      final todosChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Todos'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(todosChip.selected, isFalse);
    });

    testWidgets('SCENARIO-431: tapping "Todos" fires onChanged(null)',
        (tester) async {
      TrainerSpecialty? received = TrainerSpecialty.yoga;

      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: TrainerSpecialty.yoga,
          onChanged: (s) => received = s,
        ),
      ));

      await tester.tap(find.text('Todos'));
      await tester.pump();

      expect(received, isNull);
    });

    testWidgets('tapping specialty chip fires onChanged with that specialty',
        (tester) async {
      TrainerSpecialty? received;

      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: null,
          onChanged: (s) => received = s,
        ),
      ));

      // Scroll to make the chip visible then tap
      await tester.ensureVisible(find.text('Running'));
      await tester.pump();
      await tester.tap(find.text('Running'));
      await tester.pump();

      expect(received, TrainerSpecialty.running);
    });

    testWidgets('widget is scrollable horizontally (SingleChildScrollView)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: null,
          onChanged: (_) {},
        ),
      ));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
