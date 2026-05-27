import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/assigned_routines_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _myUid = 'athlete-uid-123';

Routine _routine({required String id, required String name}) {
  return Routine(
    id: id,
    name: name,
    split: 'Full Body',
    level: ExperienceLevel.beginner,
    days: const [],
    source: RoutineSource.trainerAssigned,
    assignedBy: 'trainer-uid',
    assignedTo: _myUid,
    visibility: RoutineVisibility.private,
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-519, SCENARIO-520, assignedRoutinesCountProvider
// ---------------------------------------------------------------------------

void main() {
  group('assignedRoutinesCountProvider', () {
    // SCENARIO-520: count provider returns list.length on data
    test(
        'SCENARIO-520: returns list.length when assignedRoutinesProvider resolves with data',
        () async {
      final routines = [
        _routine(id: 'r1', name: 'Plan A'),
        _routine(id: 'r2', name: 'Plan B'),
      ];

      final container = ProviderContainer(
        overrides: [
          assignedRoutinesProvider(_myUid).overrideWith(
            (_) async => routines,
          ),
        ],
      );
      addTearDown(container.dispose);

      // Trigger the future to resolve.
      await container.read(assignedRoutinesProvider(_myUid).future);

      final count = container.read(assignedRoutinesCountProvider(_myUid));
      expect(count, equals(2));
    });

    // SCENARIO-519: returns 0 during loading state
    test('SCENARIO-519: returns 0 during loading state', () {
      // Use a never-completing Future to stay in loading state.
      final container = ProviderContainer(
        overrides: [
          assignedRoutinesProvider(_myUid).overrideWith(
            (_) => Future<List<Routine>>(() async {
              await Future<void>.delayed(const Duration(seconds: 60));
              return [];
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Read BEFORE the future completes → loading state → count = 0.
      final count = container.read(assignedRoutinesCountProvider(_myUid));
      expect(count, equals(0));
    });

    // error → 0
    test('returns 0 on error from assignedRoutinesProvider', () async {
      final container = ProviderContainer(
        overrides: [
          assignedRoutinesProvider(_myUid).overrideWith(
            (_) => Future<List<Routine>>.error(
              Exception('Firestore unavailable'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Let the error propagate.
      await expectLater(
        container.read(assignedRoutinesProvider(_myUid).future),
        throwsA(isA<Exception>()),
      );

      final count = container.read(assignedRoutinesCountProvider(_myUid));
      expect(count, equals(0));
    });
  });
}
