import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

/// Builds a minimal Routine in the trainer-assigned shape.
/// [assignedBy] and [assignedTo] can be null to test validation paths.
Routine buildAssignedRoutine({
  required String? assignedBy,
  required String? assignedTo,
}) {
  return Routine(
    id: '',
    name: 'Plan Fuerza',
    split: 'Full Body',
    level: ExperienceLevel.intermediate,
    days: const [],
    source: RoutineSource.trainerAssigned,
    assignedBy: assignedBy,
    assignedTo: assignedTo,
    visibility: RoutineVisibility.private,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RoutineRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RoutineRepository(firestore: firestore);
  });

  /// Seeds a minimal assigned-routine document in Firestore wire format.
  Future<void> seedAssignedRoutine({
    required String id,
    required String assignedTo,
    required String assignedBy,
    String source = 'trainer-assigned',
    String visibility = 'private',
    Timestamp? createdAt,
  }) async {
    await firestore.collection('routines').doc(id).set({
      'id': id,
      'name': 'Assigned Routine $id',
      'split': 'Full Body',
      'level': 'beginner',
      'days': <dynamic>[],
      'estimatedMinutesPerDay': null,
      'imageUrl': null,
      'source': source,
      'assignedBy': assignedBy,
      'assignedTo': assignedTo,
      'visibility': visibility,
      'createdAt': createdAt ?? Timestamp.fromMillisecondsSinceEpoch(1000),
    });
  }

  // ─── listAssignedTo ───────────────────────────────────────────────────────

  group('RoutineRepository.listAssignedTo', () {
    test(
        'SCENARIO-432: returns only plans assigned to the given athlete, newest first',
        () async {
      // Seed 2 routines for athlete-1 with different timestamps so order matters.
      final older = Timestamp.fromMillisecondsSinceEpoch(1000000); // older
      final newer = Timestamp.fromMillisecondsSinceEpoch(2000000); // newer

      await seedAssignedRoutine(
        id: 'r-old',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: older,
      );
      await seedAssignedRoutine(
        id: 'r-new',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: newer,
      );
      // Routine assigned to another athlete — must NOT appear.
      await seedAssignedRoutine(
        id: 'r-other',
        assignedTo: 'athlete-2',
        assignedBy: 'trainer-1',
        createdAt: newer,
      );

      final result = await repo.listAssignedTo('athlete-1');

      expect(result, hasLength(2));
      // Newest first — r-new has higher createdAt millis.
      expect(result[0].id, equals('r-new'));
      expect(result[1].id, equals('r-old'));
    });

    test('SCENARIO-433: returns empty list when athlete has no assigned plans',
        () async {
      // Seed a routine for a different athlete to ensure the filter is applied.
      await seedAssignedRoutine(
        id: 'r-other',
        assignedTo: 'athlete-other',
        assignedBy: 'trainer-1',
      );

      final result = await repo.listAssignedTo('unknown-athlete');

      expect(result, isEmpty);
    });

    test('excludes routines with source != trainer-assigned', () async {
      // System-source routine for the same athlete must be excluded.
      await firestore.collection('routines').doc('r-system').set({
        'id': 'r-system',
        'name': 'System Routine',
        'split': 'PPL',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'system',
        'assignedTo': 'athlete-1',
        'visibility': 'public',
      });

      final result = await repo.listAssignedTo('athlete-1');

      expect(result, isEmpty);
    });
  });

  // ─── createAssigned ───────────────────────────────────────────────────────

  group('RoutineRepository.createAssigned', () {
    test(
        'SCENARIO-434: writes the routine and returns it with a Firestore-generated id',
        () async {
      const trainerId = 'trainer-1';
      const athleteId = 'athlete-1';

      final routine = buildAssignedRoutine(
        assignedBy: trainerId,
        assignedTo: athleteId,
      );

      final saved = await repo.createAssigned(routine);

      // Returned routine must have a non-empty id (Firestore generated).
      expect(saved.id, isNotEmpty);

      // Doc must exist in Firestore with the generated id.
      final snap = await firestore.collection('routines').doc(saved.id).get();
      expect(snap.exists, isTrue);
    });

    test(
        'SCENARIO-435: createAssigned does not modify source, assignedBy, or assignedTo',
        () async {
      const trainerId = 'trainer-2';
      const athleteId = 'athlete-2';

      final routine = buildAssignedRoutine(
        assignedBy: trainerId,
        assignedTo: athleteId,
      );

      final saved = await repo.createAssigned(routine);

      final snap = await firestore.collection('routines').doc(saved.id).get();
      final data = snap.data()!;

      expect(data['source'], equals('trainer-assigned'));
      expect(data['assignedBy'], equals(trainerId));
      expect(data['assignedTo'], equals(athleteId));
    });

    test('createAssigned: json sent to Firestore must NOT contain id: ""',
        () async {
      final routine = buildAssignedRoutine(
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );

      final saved = await repo.createAssigned(routine);

      final snap = await firestore.collection('routines').doc(saved.id).get();
      final data = snap.data()!;

      // The stored doc must NOT have an empty-string id field.
      expect(data['id'], isNot(equals('')));
    });

    test('createAssigned: createdAt is persisted in Firestore', () async {
      final routine = buildAssignedRoutine(
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );

      final saved = await repo.createAssigned(routine);

      final snap = await firestore.collection('routines').doc(saved.id).get();
      final data = snap.data()!;

      // fake_cloud_firestore resolves FieldValue.serverTimestamp() to a Timestamp.
      expect(data['createdAt'], isNotNull);
    });

    test('createAssigned throws ArgumentError when assignedBy is empty',
        () async {
      final routine =
          buildAssignedRoutine(assignedBy: '', assignedTo: 'athlete-1');

      expect(() => repo.createAssigned(routine), throwsArgumentError);
    });

    test('createAssigned throws ArgumentError when assignedTo is empty',
        () async {
      final routine =
          buildAssignedRoutine(assignedBy: 'trainer-1', assignedTo: '');

      expect(() => repo.createAssigned(routine), throwsArgumentError);
    });

    test('createAssigned throws ArgumentError when assignedBy is null',
        () async {
      final routine =
          buildAssignedRoutine(assignedBy: null, assignedTo: 'athlete-1');

      expect(() => repo.createAssigned(routine), throwsArgumentError);
    });
  });
}
