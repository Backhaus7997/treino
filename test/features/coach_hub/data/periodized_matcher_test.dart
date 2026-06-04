import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/excel_parser.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

/// Plan periodizado de 2 semanas × 1 día. "Zancadas búlgaras" no comparte
/// tokens con el catálogo de prueba, así queda genuinamente sin match (el
/// fuzzy del matcher matchea por tokens compartidos de 3+ chars).
RawParsedPeriodizedPlan _rawPlan() {
  List<RawParsedItem> items(int repsMin, int repsMax) => [
        RawParsedItem(
            rowName: 'Sentadilla',
            sets: 4,
            repsMin: repsMin,
            repsMax: repsMax,
            block: 'A'),
        RawParsedItem(
            rowName: 'Dominadas',
            sets: 4,
            repsMin: repsMin,
            repsMax: repsMax,
            block: 'A'),
        RawParsedItem(
            rowName: 'Zancadas búlgaras',
            sets: 3,
            repsMin: repsMin,
            repsMax: repsMax),
      ];
  return RawParsedPeriodizedPlan(
    name: 'Test',
    daysPerWeek: 1,
    durationWeeks: 2,
    level: ExperienceLevel.intermediate,
    weeks: [
      RawParsedWeek(
          weekNumber: 1,
          days: [RawParsedDay(dayNumber: 1, items: items(6, 8))]),
      RawParsedWeek(
          weekNumber: 2,
          days: [RawParsedDay(dayNumber: 1, items: items(8, 10))]),
    ],
  );
}

void main() {
  final catalog = [
    MatcherExercise(id: 'ex_sent', name: 'Sentadilla', muscleGroup: 'Piernas'),
    MatcherExercise(id: 'ex_dom', name: 'Dominadas', muscleGroup: 'Espalda'),
  ];

  group('matchPeriodized', () {
    test('matchea contra el catálogo y deja sin-match lo que no está', () {
      final plan = matchPeriodized(_rawPlan(), catalog);

      // "Zancadas búlgaras" sin match en las 2 semanas → deduplica a un nombre.
      expect(plan.unmatchedNames, ['Zancadas búlgaras']);

      final w1day1 = plan.weeks.first.days.single;
      final sent = w1day1.items.firstWhere((i) => i.rowName == 'Sentadilla');
      expect(sent.exerciseId, 'ex_sent');
      expect(sent.block, 'A'); // conserva la superserie
      final zanc =
          w1day1.items.firstWhere((i) => i.rowName == 'Zancadas búlgaras');
      expect(zanc.isMatched, isFalse);
    });

    test('mapExercise resuelve el ejercicio en TODAS las semanas', () {
      final plan = matchPeriodized(_rawPlan(), catalog);
      expect(plan.hasUnmatched, isTrue);

      final mapped = plan.mapExercise(
        'Zancadas búlgaras',
        exerciseId: 'ex_zanc',
        exerciseName: 'Zancada búlgara',
        muscleGroup: 'Piernas',
      );

      expect(mapped.hasUnmatched, isFalse);
      for (final week in mapped.weeks) {
        final zanc = week.days.single.items
            .firstWhere((i) => i.rowName == 'Zancadas búlgaras');
        expect(zanc.exerciseId, 'ex_zanc');
        expect(zanc.muscleGroup, 'Piernas');
      }
    });
  });
}
