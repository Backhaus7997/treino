import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';

class MockUser extends Mock implements User {}

ProviderContainer makeContainer({
  required Stream<User?> authStream,
  required RoutineRepository repo,
}) =>
    ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => authStream),
        routineRepositoryProvider.overrideWithValue(repo),
      ],
    );

void main() {
  group('routine providers', () {
    test('SCENARIO-067: unauthenticated returns empty list', () async {
      final firestore = FakeFirebaseFirestore();
      // Seed one routine to prove the provider isn't reading it
      await firestore.collection('routines').doc('r-1').set({
        'id': 'r-1',
        'name': 'Test Routine',
        'split': 'PPL',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
      });

      final container = makeContainer(
        authStream: Stream.value(null),
        repo: RoutineRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(routinesProvider.future);
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-068: authenticated with 2 seeded routines returns list of 2',
        () async {
      final firestore = FakeFirebaseFirestore();
      for (var i = 1; i <= 2; i++) {
        await firestore.collection('routines').doc('r-$i').set({
          'id': 'r-$i',
          'name': 'Routine $i',
          'split': 'Full Body',
          'level': 'intermediate',
          'days': <dynamic>[],
          'estimatedMinutesPerDay': null,
          'imageUrl': null,
        });
      }

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: RoutineRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(routinesProvider.future);
      expect(result, hasLength(2));
    });

    test(
        'SCENARIO-069: routineByIdProvider returns correct routine for known id',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('routines').doc('full-body-beginner').set({
        'id': 'full-body-beginner',
        'name': 'Full Body Principiante',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
      });

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: RoutineRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(routineByIdProvider('full-body-beginner').future);
      expect(result, isNotNull);
      expect(result!.id, equals('full-body-beginner'));
    });

    test('SCENARIO-070: routineByIdProvider returns null for unknown id',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('routines').doc('ppl-advanced').set({
        'id': 'ppl-advanced',
        'name': 'PPL Avanzado',
        'split': 'PPL',
        'level': 'advanced',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
      });

      final mockUser = MockUser();
      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: RoutineRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(routineByIdProvider('missing').future);
      expect(result, isNull);
    });
  });
}
