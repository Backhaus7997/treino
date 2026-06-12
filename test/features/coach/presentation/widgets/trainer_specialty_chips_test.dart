import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_specialty_chips.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

void main() {
  group('TrainerSpecialtyChips — SCENARIO-430/431 T28/T29 (multi-select)', () {
    testWidgets('SCENARIO-430: renders 11 chips (Todos + 10 specialties)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const <TrainerSpecialty>{},
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

    testWidgets('"Todos" chip is selected when set is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const <TrainerSpecialty>{},
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

    testWidgets('specialty chip is selected when in the set', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const {TrainerSpecialty.crossfit},
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

    testWidgets('multiple specialty chips can be selected at once',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const {
            TrainerSpecialty.crossfit,
            TrainerSpecialty.funcional,
          },
          onChanged: (_) {},
        ),
      ));

      final crossfit = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('CrossFit'),
          matching: find.byType(ChoiceChip),
        ),
      );
      final funcional = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Funcional'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(crossfit.selected, isTrue);
      expect(funcional.selected, isTrue);
    });

    testWidgets('SCENARIO-431: tapping "Todos" fires onChanged(empty set)',
        (tester) async {
      Set<TrainerSpecialty>? received;

      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const {TrainerSpecialty.yoga},
          onChanged: (set) => received = set,
        ),
      ));

      await tester.tap(find.text('Todos'));
      await tester.pump();

      expect(received, isNotNull);
      expect(received!.isEmpty, isTrue);
    });

    testWidgets('tapping unselected specialty adds it to the set (toggle ON)',
        (tester) async {
      Set<TrainerSpecialty>? received;

      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const <TrainerSpecialty>{},
          onChanged: (set) => received = set,
        ),
      ));

      await tester.ensureVisible(find.text('Running'));
      await tester.pump();
      await tester.tap(find.text('Running'));
      await tester.pump();

      expect(received, {TrainerSpecialty.running});
    });

    testWidgets(
        'tapping selected specialty removes it from the set (toggle OFF)',
        (tester) async {
      Set<TrainerSpecialty>? received;

      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const {
            TrainerSpecialty.running,
            TrainerSpecialty.crossfit,
          },
          onChanged: (set) => received = set,
        ),
      ));

      await tester.ensureVisible(find.text('Running'));
      await tester.pump();
      await tester.tap(find.text('Running'));
      await tester.pump();

      // Running toggled OFF, CrossFit stays in the set
      expect(received, {TrainerSpecialty.crossfit});
    });

    testWidgets('widget is scrollable horizontally (SingleChildScrollView)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerSpecialtyChips(
          selected: const <TrainerSpecialty>{},
          onChanged: (_) {},
        ),
      ));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
