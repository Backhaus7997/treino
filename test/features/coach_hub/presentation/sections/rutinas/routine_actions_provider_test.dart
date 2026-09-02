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
import 'package:treino/features/profile/domain/experience_level.dart';
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

    test(
        'invalida también routineByIdProvider — la rutina archivada dejaba de '
        'aparecer en el listado pero seguía siendo arrancable', () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});

      // El doc "vivo" antes de archivar, y el archivado después. Sin la
      // invalidación, `routineByIdProvider` sigue devolviendo el primero para
      // toda la vida del proceso: su keepAlive sólo se suelta si el fetch tira.
      var archived = false;
      var getByIdCalls = 0;
      when(() => mockRepo.getById('r1')).thenAnswer((_) async {
        getByIdCalls++;
        return archived ? null : _makeRoutine('r1');
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      final before = await container.read(routineByIdProvider('r1').future);
      expect(before, isNotNull);
      expect(getByIdCalls, 1);

      archived = true;
      await container
          .read(routineActionsProvider.notifier)
          .archive(routineId: 'r1', athleteId: _athleteId);

      final after = await container.read(routineByIdProvider('r1').future);
      expect(after, isNull);
      expect(getByIdCalls, 2,
          reason: 'la caché single-doc tiene que refetchear tras el archive');
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

Routine _makeRoutine(String id) => Routine(
      id: id,
      name: 'Plan',
      level: ExperienceLevel.intermediate,
      days: const [],
    );
