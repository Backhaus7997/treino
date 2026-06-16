import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // Sets logged against a trainer custom exercise (absent from the public
  // catalogue) must still count toward the weekly group totals, resolved via
  // the routine slot's denormalized muscleGroup. Before the fix the catalogue
  // lookup returned null and these sets were silently dropped.
  test(
      'SCENARIO-407: setLogs de ejercicio custom cuentan vía muscleGroup del slot',
      () async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: now,
            status: SessionStatus.finished,
            routineId: 'r1',
          ),
        ]);
    // 2 sets de 'e-custom' — NO está en el catálogo público.
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l1', exerciseId: 'e-custom', setNumber: 1),
              makeSetLog(id: 'l2', exerciseId: 'e-custom', setNumber: 2),
            ]);

    final routine = makeRoutine(
      id: 'r1',
      days: [
        makeDay(slots: [
          // El slot lleva el muscleGroup denormalizado del ejercicio custom.
          makeSlot(
              exerciseId: 'e-custom', muscleGroup: 'back', targetSets: 3),
        ]),
      ],
    );

    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      // Catálogo público vacío → 'e-custom' sólo resoluble por el slot.
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      routineByIdProvider('r1').overrideWith((ref) async => routine),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(weeklyInsightsProvider.future);
    // setsByGroup: los 2 sets custom se contabilizan en espalda.
    expect(result!.setsByGroup[MuscleGroupDisplay.espalda], 2);
    // targetByGroup: el slot custom aporta sus targetSets vía slot.muscleGroup.
    expect(result.targetByGroup[MuscleGroupDisplay.espalda], 3);
  });
}
