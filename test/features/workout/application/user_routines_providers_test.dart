import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';

/// Creates a [ProviderContainer] with [routineRepositoryProvider] overridden
/// to use the given [repo].
ProviderContainer makeContainer(RoutineRepository repo) {
  return ProviderContainer(
    overrides: [
      routineRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// Seeds a user-created routine document directly in fake Firestore.
Future<void> seedUserCreated({
  required FakeFirebaseFirestore firestore,
  required String id,
  required String createdBy,
  String status = 'active',
  DateTime? createdAt,
}) async {
  await firestore.collection('routines').doc(id).set({
    'id': id,
    'name': 'Mi rutina',
    'split': 'Full Body',
    'level': 'beginner',
    'days': <dynamic>[],
    'estimatedMinutesPerDay': null,
    'imageUrl': null,
    'source': 'user-created',
    'visibility': 'private',
    'createdBy': createdBy,
    'status': status,
    if (createdAt != null) 'createdAt': createdAt,
  });
}

void main() {
  group('userCreatedRoutinesProvider', () {
    test('emits empty list when uid is empty', () async {
      final firestore = FakeFirebaseFirestore();
      // Seed a routine — it must NOT be returned for empty uid.
      await seedUserCreated(
        firestore: firestore,
        id: 'r-1',
        createdBy: 'athlete-a',
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result =
          await container.read(userCreatedRoutinesProvider('').future);

      expect(result, isEmpty);
    });

    test('emits routines from repo stream for a valid uid', () async {
      final firestore = FakeFirebaseFirestore();
      final now = DateTime.now();

      await seedUserCreated(
        firestore: firestore,
        id: 'r-athlete-a',
        createdBy: 'athlete-a',
        createdAt: now,
      );
      // Another user's routine — must NOT appear.
      await seedUserCreated(
        firestore: firestore,
        id: 'r-athlete-b',
        createdBy: 'athlete-b',
        createdAt: now,
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result =
          await container.read(userCreatedRoutinesProvider('athlete-a').future);

      expect(result, hasLength(1));
      expect(result[0].id, equals('r-athlete-a'));
    });

    test('does not include archived routines', () async {
      final firestore = FakeFirebaseFirestore();

      await seedUserCreated(
        firestore: firestore,
        id: 'r-active',
        createdBy: 'athlete-a',
        status: 'active',
      );
      await seedUserCreated(
        firestore: firestore,
        id: 'r-archived',
        createdBy: 'athlete-a',
        status: 'archived',
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result =
          await container.read(userCreatedRoutinesProvider('athlete-a').future);

      expect(result, hasLength(1));
      expect(result.single.id, equals('r-active'));
    });

    test('two different uids use separate provider instances (autoDispose)',
        () async {
      final firestore = FakeFirebaseFirestore();

      for (final uid in ['athlete-a', 'athlete-b']) {
        await seedUserCreated(
          firestore: firestore,
          id: 'r-$uid',
          createdBy: uid,
        );
      }

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final results = await Future.wait([
        container.read(userCreatedRoutinesProvider('athlete-a').future),
        container.read(userCreatedRoutinesProvider('athlete-b').future),
      ]);

      expect(results[0], hasLength(1));
      expect(results[0][0].id, equals('r-athlete-a'));

      expect(results[1], hasLength(1));
      expect(results[1][0].id, equals('r-athlete-b'));
    });
  });

  // ── publicRoutinesByUserProvider ─────────────────────────────────────────
  //
  // Derived from `userCreatedRoutinesProvider`; keeps only routines the user
  // explicitly marked `visibility: public`. Powers the "RUTINAS PÚBLICAS"
  // tab on someone else's public profile.

  group('publicRoutinesByUserProvider', () {
    Future<void> seedWithVisibility({
      required FakeFirebaseFirestore firestore,
      required String id,
      required String createdBy,
      required String visibility,
      DateTime? createdAt,
    }) async {
      await firestore.collection('routines').doc(id).set({
        'id': id,
        'name': 'Rutina $id',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'user-created',
        'visibility': visibility,
        'createdBy': createdBy,
        'status': 'active',
        if (createdAt != null) 'createdAt': createdAt,
      });
    }

    test('empty when uid is empty', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      // Prime source stream before reading derived provider.
      final sub = container.listen(userCreatedRoutinesProvider(''), (_, __) {});
      await container.read(userCreatedRoutinesProvider('').future);
      expect(container.read(publicRoutinesByUserProvider('')), isEmpty);
      sub.close();
    });

    test('mixed visibilities → only public rows survive', () async {
      final firestore = FakeFirebaseFirestore();
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-priv',
        createdBy: 'me',
        visibility: 'private',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-pub-1',
        createdBy: 'me',
        visibility: 'public',
        createdAt: DateTime.utc(2026, 1, 2),
      );
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-shared',
        createdBy: 'me',
        visibility: 'shared',
        createdAt: DateTime.utc(2026, 1, 3),
      );
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-pub-2',
        createdBy: 'me',
        visibility: 'public',
        createdAt: DateTime.utc(2026, 1, 4),
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final sub =
          container.listen(userCreatedRoutinesProvider('me'), (_, __) {});
      await container.read(userCreatedRoutinesProvider('me').future);

      final public = container.read(publicRoutinesByUserProvider('me'));
      expect(public.map((r) => r.id), unorderedEquals(['r-pub-1', 'r-pub-2']));
      sub.close();
    });

    test('no public routines → empty', () async {
      final firestore = FakeFirebaseFirestore();
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-priv',
        createdBy: 'me',
        visibility: 'private',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final sub =
          container.listen(userCreatedRoutinesProvider('me'), (_, __) {});
      await container.read(userCreatedRoutinesProvider('me').future);

      expect(container.read(publicRoutinesByUserProvider('me')), isEmpty);
      sub.close();
    });

    test(
        'per-user isolation: routines created by another uid are excluded',
        () async {
      // Regression guard: filter must respect `createdBy`, not just visibility.
      final firestore = FakeFirebaseFirestore();
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-mine',
        createdBy: 'me',
        visibility: 'public',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await seedWithVisibility(
        firestore: firestore,
        id: 'r-theirs',
        createdBy: 'other',
        visibility: 'public',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final repo = RoutineRepository(firestore: firestore);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final sub =
          container.listen(userCreatedRoutinesProvider('me'), (_, __) {});
      await container.read(userCreatedRoutinesProvider('me').future);

      final mine = container.read(publicRoutinesByUserProvider('me'));
      expect(mine.map((r) => r.id), ['r-mine']);
      sub.close();
    });
  });
}
