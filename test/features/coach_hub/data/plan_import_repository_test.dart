// El catálogo del matcher incluye los ejercicios PROPIOS del PF: re-importar
// una hoja con un ejercicio ya creado como propio se asigna solo (y no invita
// a duplicarlo). Si el stream de propios falla, se importa sólo con la
// biblioteca.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/plan_import_repository.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import 'periodized_test_helpers.dart';

class _MockExerciseRepo extends Mock implements ExerciseRepository {}

CustomExercise _custom(String id, String name) => CustomExercise(
      id: id,
      ownerId: 'trainer-1',
      name: name,
      muscleGroup: 'legs',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late _MockExerciseRepo exerciseRepo;

  final bytes = programa([
    header1(weeks: 3),
    [1, 'Sentadilla con banda', 60, '3x8', '3x8', '3x8'],
    [2, 'Press de banca', 60, '3x8', '3x8', '3x8'],
  ]);

  setUp(() {
    exerciseRepo = _MockExerciseRepo();
    when(() => exerciseRepo.listAll()).thenAnswer((_) async => [
          const Exercise(
            id: 'lib-press',
            name: 'Press de banca',
            muscleGroup: 'chest',
            category: 'compound',
          ),
        ]);
  });

  test(
      'un ejercicio propio con el mismo nombre se asigna solo, con su id crudo',
      () async {
    final repo = PlanImportRepository(
      exerciseRepository: exerciseRepo,
      customExercises: () async =>
          [_custom('custom-7', 'Sentadilla con banda')],
    );

    final outcome = await repo.parseAndMatch(bytes: bytes);
    final draft = outcome.draft!;

    expect(draft.unresolved, isEmpty,
        reason: 'nada en rojo: no hay "Crear como propio" que ofrecer');
    final ids = draft.assignments.values.map((e) => e.id).toSet();
    expect(ids, {'custom-7', 'lib-press'});
  });

  test('si el stream de propios falla, el import sigue con la biblioteca',
      () async {
    final repo = PlanImportRepository(
      exerciseRepository: exerciseRepo,
      customExercises: () async => throw Exception('permission-denied'),
    );

    final outcome = await repo.parseAndMatch(bytes: bytes);
    final draft = outcome.draft!;

    expect(draft.assignments.values.map((e) => e.id), ['lib-press']);
    expect(draft.unresolved, hasLength(1));
  });

  test('sin lector de propios (null) se comporta como antes', () async {
    final repo = PlanImportRepository(exerciseRepository: exerciseRepo);

    final draft = (await repo.parseAndMatch(bytes: bytes)).draft!;

    expect(draft.assignments.values.map((e) => e.id), ['lib-press']);
  });
}
