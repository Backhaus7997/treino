// Tests para RoutineActionsNotifier — mutación mínima de rutinas del Coach
// Hub web (Fase 5, WU-04). Sin widgets: aislado a nivel de ProviderContainer
// para verificar la llamada al repo + la invalidación del listado.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routine_actions_provider.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _athleteId = 'athlete-1';

void main() {
  late _MockRoutineRepository mockRepo;
  late int listCalls;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        routineRepositoryProvider.overrideWithValue(mockRepo),
        assignedRoutinesProvider(_athleteId).overrideWith((ref) async {
          listCalls++;
          return const <Routine>[];
        }),
      ],
    );
  }

  setUp(() {
    mockRepo = _MockRoutineRepository();
    listCalls = 0;
  });

  group('RoutineActionsNotifier.archive', () {
    test('llama a repo.archive(routineId) e invalida assignedRoutinesProvider',
        () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});
      final container = makeContainer();
      addTearDown(container.dispose);

      // Mantiene vivo el FutureProvider.autoDispose durante el test.
      final sub =
          container.listen(assignedRoutinesProvider(_athleteId), (_, __) {});
      addTearDown(sub.close);

      await container.read(assignedRoutinesProvider(_athleteId).future);
      expect(listCalls, 1);

      final ok = await container
          .read(routineActionsProvider.notifier)
          .archive(routineId: 'r1', athleteId: _athleteId);

      expect(ok, isTrue);
      verify(() => mockRepo.archive('r1')).called(1);

      // El invalidate dispara un nuevo fetch en la próxima lectura.
      await container.read(assignedRoutinesProvider(_athleteId).future);
      expect(listCalls, 2);
    });

    test('devuelve false y no propaga la excepción cuando repo.archive falla',
        () async {
      when(() => mockRepo.archive(any())).thenThrow(Exception('boom'));
      final container = makeContainer();
      addTearDown(container.dispose);

      final ok = await container
          .read(routineActionsProvider.notifier)
          .archive(routineId: 'r1', athleteId: _athleteId);

      expect(ok, isFalse);
    });
  });
}
