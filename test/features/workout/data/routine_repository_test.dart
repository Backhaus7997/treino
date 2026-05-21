import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/routine_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RoutineRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RoutineRepository(firestore: firestore);
  });

  /// Seeds a routine document using raw wire-format maps (mimicking Firestore).
  ///
  /// `visibility` defaults to `'public'` so the doc is returned by
  /// `listAll()`, which filters by `visibility == 'public'` after the
  /// coach-plans-mobile rule change (see `routine_repository.dart` for the
  /// rationale). Pass `visibility: 'private'` to seed a trainer-assigned
  /// plan that must NOT appear in the Plantillas screen.
  Future<void> seedRoutine({
    required String id,
    required List<Map<String, dynamic>> days,
    String visibility = 'public',
    String source = 'system',
    String? assignedBy,
    String? assignedTo,
  }) async {
    await firestore.collection('routines').doc(id).set({
      'id': id,
      'name': 'Test Routine',
      'split': 'PPL',
      'level': 'beginner',
      'days': days,
      'estimatedMinutesPerDay': null,
      'imageUrl': null,
      'visibility': visibility,
      'source': source,
      if (assignedBy != null) 'assignedBy': assignedBy,
      if (assignedTo != null) 'assignedTo': assignedTo,
    });
  }

  group('RoutineRepository', () {
    test('SCENARIO-058: empty collection returns empty list', () async {
      final result = await repo.listAll();
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-059: 3 seeded routines return list of 3 with nested deserialization',
        () async {
      final slotMap = <String, dynamic>{
        'exerciseId': 'bench-press',
        'exerciseName': 'Bench Press',
        'muscleGroup': 'chest',
        'targetSets': 3,
        'targetRepsMin': 8,
        'targetRepsMax': 12,
        'restSeconds': 90,
      };
      final dayMap = <String, dynamic>{
        'dayNumber': 1,
        'name': 'Push',
        'estimatedMinutes': 60,
        'slots': [slotMap],
      };

      await seedRoutine(id: 'r-1', days: [dayMap]);
      await seedRoutine(id: 'r-2', days: [dayMap]);
      await seedRoutine(id: 'r-3', days: [dayMap]);

      final result = await repo.listAll();

      expect(result, hasLength(3));
      expect(result.every((r) => r.id.isNotEmpty), isTrue);
      expect(result.every((r) => r.days.isNotEmpty), isTrue);
      expect(result.every((r) => r.days[0].slots.isNotEmpty), isTrue);
    });

    test('SCENARIO-060: getById returns non-null routine with correct id',
        () async {
      await seedRoutine(id: 'ppl-beginner', days: []);

      final result = await repo.getById('ppl-beginner');

      expect(result, isNotNull);
      expect(result!.id, equals('ppl-beginner'));
    });

    test('SCENARIO-061: getById returns null for nonexistent id', () async {
      final result = await repo.getById('nonexistent-routine');
      expect(result, isNull);
    });

    test(
        'SCENARIO-062: nested List<dynamic> from Firestore deserializes to typed objects',
        () async {
      final slot1Map = <String, dynamic>{
        'exerciseId': 'back-squat',
        'exerciseName': 'Back Squat',
        'muscleGroup': 'quads',
        'targetSets': 4,
        'targetRepsMin': 8,
        'targetRepsMax': 12,
        'restSeconds': 120,
      };
      final slot2Map = <String, dynamic>{
        'exerciseId': 'romanian-deadlift',
        'exerciseName': 'Romanian Deadlift',
        'muscleGroup': 'hamstrings',
        'targetSets': 3,
        'targetRepsMin': 10,
        'targetRepsMax': 12,
        'restSeconds': 90,
      };
      final dayMap = <String, dynamic>{
        'dayNumber': 1,
        'name': 'Legs',
        'estimatedMinutes': 70,
        'slots': [slot1Map, slot2Map],
      };

      await seedRoutine(id: 'legs-day', days: [dayMap]);

      final result = await repo.getById('legs-day');

      expect(result, isNotNull);
      expect(result!.days.length, equals(1));
      expect(result.days[0].slots.length, equals(2));
      expect(result.days[0].slots[0].exerciseId, equals('back-squat'));
      expect(result.days[0].slots[1].exerciseId, equals('romanian-deadlift'));
    });

    test(
        'SCENARIO-063: routine with days: [] deserializes to empty List<RoutineDay>',
        () async {
      await seedRoutine(id: 'empty-routine', days: []);

      final result = await repo.getById('empty-routine');

      expect(result, isNotNull);
      expect(result!.days, isEmpty);
    });

    test(
        'SCENARIO-450: listAll() excludes private trainer-assigned routines '
        '(matches firestore.rules visibility constraint)', () async {
      // Public plantilla → must be included
      await seedRoutine(id: 'public-routine', days: []);
      // Private trainer-assigned plan → must be excluded from Plantillas screen
      await seedRoutine(
        id: 'private-trainer-plan',
        days: [],
        visibility: 'private',
        source: 'trainer-assigned',
        assignedBy: 'trainer-uid',
        assignedTo: 'athlete-uid',
      );
      // Shared trainer plan → also excluded (Plantillas shows only public)
      await seedRoutine(
        id: 'shared-trainer-plan',
        days: [],
        visibility: 'shared',
        source: 'trainer-assigned',
        assignedBy: 'trainer-uid',
        assignedTo: 'athlete-uid',
      );

      final result = await repo.listAll();

      expect(result, hasLength(1));
      expect(result.single.id, equals('public-routine'));
    });
  });
}
