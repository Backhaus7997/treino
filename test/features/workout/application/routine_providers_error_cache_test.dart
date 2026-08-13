// Regression tests for #497 — the single-doc routine providers used to cache
// their `AsyncError` for the whole lifetime of the ProviderContainer.
//
// [routineByIdProvider] was a plain (NON-autoDispose) `FutureProvider.family`
// that nothing ever invalidated. One transient `getById` failure — a gym with
// bad signal timing out, or a `permission-denied` on a trainer-template the
// trainer just un-shared — poisoned every consumer PERMANENTLY: starting a
// session, resuming one, and `planProgressProvider` (which powers the periodized
// CTA) all kept reading the same cached error until the app was restarted.
// `ref.invalidate` on a WRAPPER does not cascade to its dependencies, so the
// screens' own retry paths could never recover it either.
//
// The fix keeps the cache-on-success contract (one-shot readers rely on it) but
// releases the cache when the fetch FAILS: `ref.keepAlive()` held only on the
// success path, `link.close()` in the error path.
//
// Same defect, same fix for [visibleRoutineByIdProvider]: it swallows
// `not-found`/`permission-denied` into `null`, but a transient backend failure
// (`unavailable`, `deadline-exceeded`) deliberately RETHROWS — and that error
// was being cached forever too, breaking the insights radars' retry.

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';

import 'stub_factories.dart';

class MockRoutineRepository extends Mock implements RoutineRepository {}

FirebaseException _transient() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

void main() {
  group('routineByIdProvider error caching (#497)', () {
    test(
        'SCENARIO-497-001: a transient failure is NOT cached — the next read '
        'refetches and recovers', () async {
      final repo = MockRoutineRepository();
      final routine = makeRoutine();

      // First fetch blows up (bad signal), second one succeeds.
      var calls = 0;
      when(() => repo.getById(routine.id)).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw _transient();
        return routine;
      });

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(routineByIdProvider(routine.id).future),
        throwsA(isA<FirebaseException>()),
      );

      // The screen that triggered the failed fetch goes away — no listeners
      // left, so the failed element must be released instead of retained.
      await container.pump();

      final recovered =
          await container.read(routineByIdProvider(routine.id).future);
      expect(recovered, isNotNull);
      expect(recovered!.id, routine.id);
      expect(calls, 2,
          reason: 'the failed fetch must be retried, not replayed');
    });

    test(
        'SCENARIO-497-002: a SUCCESSFUL fetch stays cached — the one-shot '
        'contract is preserved', () async {
      final repo = MockRoutineRepository();
      final routine = makeRoutine();
      when(() => repo.getById(routine.id)).thenAnswer((_) async => routine);

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(routineByIdProvider(routine.id).future);
      await container.pump();
      await container.read(routineByIdProvider(routine.id).future);

      // Guards against "fix" it by making the provider plainly autoDispose:
      // that would re-hit Firestore on every mount of every consumer.
      verify(() => repo.getById(routine.id)).called(1);
    });

    test(
        'SCENARIO-497-003: a null result (unknown id) stays cached — absence '
        'is an answer, not a failure', () async {
      final repo = MockRoutineRepository();
      when(() => repo.getById('missing')).thenAnswer((_) async => null);

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      expect(await container.read(routineByIdProvider('missing').future), null);
      await container.pump();
      expect(await container.read(routineByIdProvider('missing').future), null);

      verify(() => repo.getById('missing')).called(1);
    });
  });

  group('visibleRoutineByIdProvider error caching (#497)', () {
    test(
        'SCENARIO-497-004: a transient failure is NOT cached — the next read '
        'refetches and recovers', () async {
      final repo = MockRoutineRepository();
      final routine = makeRoutine();

      var calls = 0;
      when(() => repo.getByIdIfVisible(routine.id)).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw _transient();
        return routine;
      });

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(visibleRoutineByIdProvider(routine.id).future),
        throwsA(isA<FirebaseException>()),
      );
      await container.pump();

      final recovered =
          await container.read(visibleRoutineByIdProvider(routine.id).future);
      expect(recovered, isNotNull);
      expect(calls, 2);
    });

    test(
        'SCENARIO-497-005: a null result (routine gone / access revoked) stays '
        'cached — it is the documented answer, not a failure', () async {
      final repo = MockRoutineRepository();
      when(() => repo.getByIdIfVisible('r-gone')).thenAnswer((_) async => null);

      final container = ProviderContainer(
        overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(visibleRoutineByIdProvider('r-gone').future),
        null,
      );
      await container.pump();
      expect(
        await container.read(visibleRoutineByIdProvider('r-gone').future),
        null,
      );

      verify(() => repo.getByIdIfVisible('r-gone')).called(1);
    });
  });
}
