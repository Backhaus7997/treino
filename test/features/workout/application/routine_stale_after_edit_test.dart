// Regression tests for "agrego un ejercicio, EMPEZAR no lo muestra".
//
// The routine detail screen watches `routineByIdStreamProvider` (live), so an
// edit shows up there instantly. The session, however, is built by
// `SessionNotifier._buildFresh`, which reads [routineByIdProvider] — a one-shot
// Future that holds a `ref.keepAlive()` link for as long as the fetch SUCCEEDED
// (#497's cache-on-success contract). Nothing released that link on a write, so
// the player kept composing the workout from the PRE-edit copy of the routine
// and only an app restart — a fresh ProviderContainer — reconciled the two.
//
// [invalidateRoutineById] is the release valve every write path must pull.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';

import 'stub_factories.dart';

class MockRoutineRepository extends Mock implements RoutineRepository {}

void main() {
  group('routine cache invalidation after an edit', () {
    test(
        'SCENARIO-STALE-001: without invalidation the one-shot read replays '
        'the pre-edit routine — this is the bug', () async {
      final repo = MockRoutineRepository();
      final before = makeRoutine(days: [makeDay(slots: [makeSlot()])]);
      final after = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(), makeSlot(exerciseId: 'e-nuevo')]),
        ],
      );

      var edited = false;
      when(() => repo.getById(before.id))
          .thenAnswer((_) async => edited ? after : before);

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final first = await container.read(routineByIdProvider(before.id).future);
      expect(first!.days.first.slots, hasLength(1));

      // The athlete saves a new exercise. The detail screen's stream would
      // reflect it; the cached Future does not, on its own.
      edited = true;
      await container.pump();

      final replayed =
          await container.read(routineByIdProvider(before.id).future);
      expect(replayed!.days.first.slots, hasLength(1),
          reason: 'keepAlive holds the success forever until something drops it');
    });

    test(
        'SCENARIO-STALE-002: invalidateRoutineById drops the cache so the next '
        'session build sees the added exercise', () async {
      final repo = MockRoutineRepository();
      final before = makeRoutine(days: [makeDay(slots: [makeSlot()])]);
      final after = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(), makeSlot(exerciseId: 'e-nuevo')]),
        ],
      );

      var edited = false;
      when(() => repo.getById(before.id))
          .thenAnswer((_) async => edited ? after : before);
      when(() => repo.getByIdIfVisible(before.id))
          .thenAnswer((_) async => edited ? after : before);

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(routineByIdProvider(before.id).future);
      await container.read(visibleRoutineByIdProvider(before.id).future);

      edited = true;
      invalidateRoutineById(container, before.id);
      await container.pump();

      final fresh = await container.read(routineByIdProvider(before.id).future);
      expect(fresh!.days.first.slots, hasLength(2));
      expect(fresh.days.first.slots.last.exerciseId, 'e-nuevo');

      final freshVisible =
          await container.read(visibleRoutineByIdProvider(before.id).future);
      expect(freshVisible!.days.first.slots, hasLength(2),
          reason: 'the insights radars read the visible variant of the cache');
    });
  });
}
