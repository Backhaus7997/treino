import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';

class MockUser extends Mock implements User {}

ProviderContainer makeContainer({
  required Stream<User?> authStream,
  required ExerciseRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => authStream),
      exerciseRepositoryProvider.overrideWithValue(repo),
    ],
  );
  // Keep [exercisesProvider] (and its auth dependency) subscribed for the life
  // of the container. Since PR #209 the provider watches the auth AsyncValue and
  // only `await`s `authStateChangesProvider.future` while it is loading; without
  // an active listener the auth StreamProvider never drives its first emission
  // during a bare `read(...future)`, so the future hangs and the provider is
  // disposed mid-loading. A real widget is always listening — this mirrors that.
  container.listen(exercisesProvider, (_, __) {});
  return container;
}

void main() {
  group('exercise providers', () {
    test('SCENARIO-035: unauthenticated returns empty list', () async {
      final firestore = FakeFirebaseFirestore();
      // Seed one exercise to prove the provider isn't reading it
      await firestore.collection('exercises').doc('ex-1').set({
        'id': 'ex-1',
        'name': 'Test',
        'muscleGroup': 'chest',
        'category': 'compound',
      });

      final container = makeContainer(
        authStream: Stream.value(null),
        repo: ExerciseRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(exercisesProvider.future);
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-036: authenticated with 3 seeded exercises returns list of 3',
        () async {
      final firestore = FakeFirebaseFirestore();
      for (var i = 1; i <= 3; i++) {
        await firestore.collection('exercises').doc('ex-$i').set({
          'id': 'ex-$i',
          'name': 'Exercise $i',
          'muscleGroup': 'back',
          'category': 'compound',
        });
      }

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: ExerciseRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(exercisesProvider.future);
      expect(result, hasLength(3));
    });

    test(
        'SCENARIO-037: exerciseByIdProvider returns correct exercise for known id',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('exercises').doc('deadlift').set({
        'id': 'deadlift',
        'name': 'Deadlift',
        'muscleGroup': 'back',
        'category': 'compound',
      });

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: ExerciseRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(exerciseByIdProvider('deadlift').future);
      expect(result, isNotNull);
      expect(result!.id, equals('deadlift'));
    });

    test('SCENARIO-038: exerciseByIdProvider returns null for unknown id',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('exercises').doc('squat').set({
        'id': 'squat',
        'name': 'Back Squat',
        'muscleGroup': 'quads',
        'category': 'compound',
      });

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: ExerciseRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(exerciseByIdProvider('ghost').future);
      expect(result, isNull);
    });
  });
}
