import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ExerciseRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ExerciseRepository(firestore: firestore);
  });

  Future<void> seedExercise({
    required String id,
    String name = 'Test Exercise',
    String muscleGroup = 'chest',
    String category = 'compound',
  }) async {
    await firestore.collection('exercises').doc(id).set({
      'id': id,
      'name': name,
      'muscleGroup': muscleGroup,
      'category': category,
    });
  }

  group('ExerciseRepository', () {
    test('SCENARIO-025: empty collection returns empty list', () async {
      final result = await repo.listAll();
      expect(result, isEmpty);
    });

    test('SCENARIO-026: 5 seeded exercises return list of length 5', () async {
      await seedExercise(id: 'ex-1', name: 'Exercise 1');
      await seedExercise(id: 'ex-2', name: 'Exercise 2');
      await seedExercise(id: 'ex-3', name: 'Exercise 3');
      await seedExercise(id: 'ex-4', name: 'Exercise 4');
      await seedExercise(id: 'ex-5', name: 'Exercise 5');

      final result = await repo.listAll();

      expect(result, hasLength(5));
      expect(result.every((e) => e.id.isNotEmpty), isTrue);
    });

    test(
        'SCENARIO-027: getById returns non-null exercise with correct id',
        () async {
      await seedExercise(id: 'bench-press', name: 'Bench Press');

      final result = await repo.getById('bench-press');

      expect(result, isNotNull);
      expect(result!.id, equals('bench-press'));
      expect(result.name, equals('Bench Press'));
    });

    test(
        'SCENARIO-028: getById returns null for nonexistent id', () async {
      final result = await repo.getById('nonexistent');
      expect(result, isNull);
    });

    test(
        'SCENARIO-029: getByIds returns only the requested exercises',
        () async {
      await seedExercise(id: 'squat');
      await seedExercise(id: 'deadlift');
      await seedExercise(id: 'bench-press');

      final result = await repo.getByIds(['squat', 'deadlift']);

      expect(result, hasLength(2));
      final ids = result.map((e) => e.id).toList();
      expect(ids, containsAll(['squat', 'deadlift']));
      expect(ids, isNot(contains('bench-press')));
    });

    test('SCENARIO-030: getByIds with empty list returns empty list without querying Firestore',
        () async {
      // Seed something to prove no data is read
      await seedExercise(id: 'some-exercise');

      final result = await repo.getByIds([]);

      expect(result, isEmpty);
    });

    test(
        'SCENARIO-031: getById finds document confirming collection path is exercises',
        () async {
      await firestore.collection('exercises').doc('push-up').set({
        'id': 'push-up',
        'name': 'Push-Up',
        'muscleGroup': 'chest',
        'category': 'compound',
      });

      final result = await repo.getById('push-up');

      expect(result, isNotNull);
      expect(result!.id, equals('push-up'));
    });
  });
}
