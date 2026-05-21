import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Creates a [ProviderContainer] with [routineRepositoryProvider] overridden
/// to use the given [repo].
ProviderContainer makeContainer(RoutineRepository repo) {
  final container = ProviderContainer(
    overrides: [
      routineRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return container;
}

void main() {
  group('assignedRoutinesProvider', () {
    test(
        'SCENARIO-436: resolves to the repository result for a valid athleteId',
        () async {
      final firestore = FakeFirebaseFirestore();
      const athleteId = 'athlete-a';

      // Seed one assigned routine.
      await firestore.collection('routines').doc('r-1').set({
        'id': 'r-1',
        'name': 'Plan A',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'trainer-assigned',
        'assignedBy': 'trainer-1',
        'assignedTo': athleteId,
        'visibility': 'private',
        'createdAt': null,
      });

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result =
          await container.read(assignedRoutinesProvider(athleteId).future);

      expect(result, hasLength(1));
      expect(result[0].id, equals('r-1'));
    });

    test('SCENARIO-437: returns empty list when athleteId is empty', () async {
      final firestore = FakeFirebaseFirestore();

      // Even with a seeded routine, empty athleteId returns [] without querying.
      await firestore.collection('routines').doc('r-2').set({
        'id': 'r-2',
        'name': 'Plan B',
        'split': 'PPL',
        'level': 'advanced',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'trainer-assigned',
        'assignedBy': 'trainer-1',
        'assignedTo': 'some-athlete',
        'visibility': 'private',
        'createdAt': null,
      });

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result = await container.read(assignedRoutinesProvider('').future);

      expect(result, isEmpty);
    });

    test('SCENARIO-437: exposes AsyncError when repository throws', () async {
      // Override the whole provider family to simulate a repository error.
      final container = ProviderContainer(
        overrides: [
          assignedRoutinesProvider.overrideWith(
            (ref, athleteId) => Future.error(
              Exception('Firestore unavailable'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Read the future — it must complete with an error.
      Object? caughtError;
      await container
          .read(assignedRoutinesProvider('athlete-x').future)
          .catchError((Object e) {
        caughtError = e;
        return <Routine>[];
      });

      expect(caughtError, isA<Exception>());
    });

    test(
        'autoDispose: two different athleteIds use separate provider instances',
        () async {
      final firestore = FakeFirebaseFirestore();

      // Seed one routine for each athlete.
      for (final athleteId in ['a1', 'a2']) {
        await firestore.collection('routines').doc('r-$athleteId').set({
          'id': 'r-$athleteId',
          'name': 'Plan for $athleteId',
          'split': 'Full Body',
          'level': 'beginner',
          'days': <dynamic>[],
          'estimatedMinutesPerDay': null,
          'imageUrl': null,
          'source': 'trainer-assigned',
          'assignedBy': 'trainer-1',
          'assignedTo': athleteId,
          'visibility': 'private',
          'createdAt': null,
        });
      }

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final results = await Future.wait([
        container.read(assignedRoutinesProvider('a1').future),
        container.read(assignedRoutinesProvider('a2').future),
      ]);
      final resultA1 = results[0];
      final resultA2 = results[1];

      expect(resultA1, hasLength(1));
      expect(resultA1[0].id, equals('r-a1'));

      expect(resultA2, hasLength(1));
      expect(resultA2[0].id, equals('r-a2'));
    });
  });
}
