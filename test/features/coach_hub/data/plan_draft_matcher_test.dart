// matchDraft no depende del Excel: matchea un plan armado a mano (como el
// que sale del JSON del PDF) con la misma política que el import de Excel.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/plan_draft_matcher.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

class _MockExerciseRepo extends Mock implements ExerciseRepository {}

void main() {
  test('plan sin Excel: exacto se asigna, aproximado sólo sugiere', () async {
    final repo = _MockExerciseRepo();
    when(() => repo.listAll()).thenAnswer((_) async => [
          const Exercise(
            id: 'press',
            name: 'Press de banca',
            muscleGroup: 'chest',
            category: 'compound',
          ),
          const Exercise(
            id: 'remo',
            name: 'Remo con barra',
            muscleGroup: 'back',
            category: 'compound',
          ),
        ]);
    PeriodizedExercise ex(String name) => PeriodizedExercise(
          component: 0,
          rawName: name,
          weeks: const [
            [SetSpec(reps: 8)],
          ],
        );
    final plan = PeriodizedPlan(numWeeks: 1, days: [
      PeriodizedDay(dayNumber: 1, headerRow: 0, rows: [
        PeriodizedRow(
            excelRow: 1,
            number: 1,
            restSeconds: 60,
            exercises: [ex('Press de banca')]),
        PeriodizedRow(
            excelRow: 2,
            number: 2,
            restSeconds: 60,
            exercises: [ex('Remo pendlay con barra')]),
      ]),
    ]);

    final draft = await PlanDraftMatcher(exerciseRepository: repo)
        .matchDraft(plan: plan, warnings: const [], name: 'Plan PDF');

    expect(draft.name, 'Plan PDF');
    expect(draft.assignments.values.map((e) => e.id), ['press']);
    expect(draft.suggestions.values.map((e) => e.id), ['remo']);
    expect(draft.unresolved, hasLength(1));
  });
}
