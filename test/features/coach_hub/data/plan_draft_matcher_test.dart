// matchDraft no depende del Excel: matchea un plan armado a mano (como el
// que sale del JSON del PDF) con la misma política que el import de Excel.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
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
      PeriodizedDay(dayNumber: 1, rows: [
        PeriodizedRow(
            position: 1,
            number: 1,
            restSeconds: 60,
            exercises: [ex('Press de banca')]),
        PeriodizedRow(
            position: 2,
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

  group('candidatos del extractor del PDF (sólo sugerencias)', () {
    late _MockExerciseRepo repo;
    setUp(() {
      repo = _MockExerciseRepo();
      Exercise e(String id, String name) => Exercise(
          id: id, name: name, muscleGroup: 'back', category: 'compound');
      when(() => repo.listAll()).thenAnswer((_) async => [
            e('press', 'Press de banca'),
            e('remo', 'Remo con barra'),
            e('remo-polea', 'Remo en polea baja'),
            e('pendlay-alto', 'Remo pendlay alto'),
            e('press-manc', 'Press banca con mancuernas'),
            e('bulgara', 'Estocada búlgara'),
          ]);
    });

    const key = (dayNumber: 1, row: 1, component: 0);

    Future<PeriodizedImportDraft> draftFor(
      String rawName, {
      String? candidate,
      double? confidence,
    }) {
      final plan = PeriodizedPlan(numWeeks: 1, days: [
        PeriodizedDay(dayNumber: 1, rows: [
          PeriodizedRow(position: 1, number: 1, restSeconds: 60, exercises: [
            PeriodizedExercise(
              component: 0,
              rawName: rawName,
              weeks: const [
                [SetSpec(reps: 8)],
              ],
              candidateExerciseId: candidate,
              candidateConfidence: confidence,
            ),
          ]),
        ]),
      ]);
      return PlanDraftMatcher(exerciseRepository: repo)
          .matchDraft(plan: plan, warnings: const [], name: 'PDF');
    }

    test('sin candidato el fuzzy no encuentra nada (base de los demás)',
        () async {
      final draft = await draftFor('Split squat búlgaro');

      expect(draft.suggestions, isEmpty);
    });

    test('pasa el veto y no hay fuzzy: queda como sugerencia', () async {
      final draft = await draftFor('Split squat búlgaro', candidate: 'bulgara');

      expect(draft.suggestions[key]!.id, 'bulgara');
      expect(draft.isResolved(key), isFalse);
    });

    test('vetado (otro equipo): se descarta aunque la confianza sea alta',
        () async {
      final draft = await draftFor('Press banca con barra',
          candidate: 'press-manc', confidence: 0.99);

      expect(draft.suggestions, isEmpty);
      expect(draft.alternatives, isEmpty);
      expect(draft.unresolved, [key]);
    });

    test('id que no está en el catálogo: se descarta', () async {
      final draft =
          await draftFor('Split squat búlgaro', candidate: 'no-existe');

      expect(draft.suggestions, isEmpty);
    });

    test(
        'fuzzy y LLM distintos: queda el del LLM, el fuzzy es alternativa '
        '(el modelo lee el plan; el fuzzy sólo cuenta palabras)', () async {
      final draft = await draftFor('Remo pendlay', candidate: 'remo');

      expect(draft.suggestions[key]!.id, 'remo');
      expect(draft.alternatives[key]!.id, 'pendlay-alto');
      // Resolver el componente conserva la alternativa: después de confirmar
      // (sobre todo en bloque) el PF todavía puede corregir con ella.
      final resolved = draft.resolve(key, draft.suggestions[key]!);
      expect(resolved.suggestions, isEmpty);
      expect(resolved.alternatives[key]!.id, 'pendlay-alto');
    });

    test('LLM vetado junto a un fuzzy válido: no queda como alternativa',
        () async {
      final draft =
          await draftFor('Remo pendlay con barra', candidate: 'remo-polea');

      expect(draft.suggestions[key]!.id, 'remo');
      expect(draft.alternatives, isEmpty);
    });

    test('el exacto gana sobre el candidato', () async {
      final draft = await draftFor('Press de banca', candidate: 'remo');

      expect(draft.assignments[key]!.id, 'press');
      expect(draft.suggestions, isEmpty);
    });

    test('CONTROL NEGATIVO: confianza 1.0 tampoco autoasigna', () async {
      final draft = await draftFor('Split squat búlgaro',
          candidate: 'bulgara', confidence: 1.0);

      expect(draft.assignments, isEmpty);
      expect(draft.unresolved, [key]);
    });
  });
}
