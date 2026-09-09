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

  // ─── listAuthoredBy ───────────────────────────────────────────────────────

  group('RoutineRepository.listAuthoredBy', () {
    test('trae plantillas Y planes asignados del mismo PF', () async {
      // `assignedBy` es lo único que une a las dos formas: una plantilla es
      // `trainer-template` con `assignedTo: null`, un plan es
      // `trainer-assigned` con el uid del alumno. Esta query es la contracara
      // de `listAssignedTo`: aquélla parte del ALUMNO, ésta del AUTOR.
      await seedAssignedRoutine(
        id: 'r-plan',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
      );
      await firestore.collection('routines').doc('r-plantilla').set({
        'id': 'r-plantilla',
        'name': 'Plantilla del PF',
        'split': 'PPL',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'trainer-template',
        'assignedBy': 'trainer-1',
        'assignedTo': null,
        'visibility': 'private',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(2000),
      });

      final result = await repo.listAuthoredBy('trainer-1');

      expect(
        result.map((r) => r.id).toSet(),
        {'r-plan', 'r-plantilla'},
        reason: 'las dos formas llevan `assignedBy`',
      );
    });

    test('no trae lo de OTRO pf ni lo que creó el alumno', () async {
      await seedAssignedRoutine(
        id: 'r-mio',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
      );
      await seedAssignedRoutine(
        id: 'r-ajeno',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-2',
      );
      // Rutina propia del alumno: no tiene `assignedBy`.
      await firestore.collection('routines').doc('r-del-alumno').set({
        'id': 'r-del-alumno',
        'name': 'Mi rutina',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[],
        'source': 'user-created',
        'createdBy': 'athlete-1',
        'visibility': 'private',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      });

      final result = await repo.listAuthoredBy('trainer-1');

      expect(result.map((r) => r.id), ['r-mio']);
    });

    test('más nuevas primero, y las que no tienen fecha al fondo', () async {
      // Un `serverTimestamp` pendiente todavía no tiene valor: no se puede
      // comparar con honestidad, así que queda último en vez de adivinarle
      // una posición.
      await seedAssignedRoutine(
        id: 'r-vieja',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(1000),
      );
      await seedAssignedRoutine(
        id: 'r-nueva',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(9000),
      );
      await firestore.collection('routines').doc('r-sin-fecha').set({
        'id': 'r-sin-fecha',
        'name': 'Sin fecha',
        'split': 'PPL',
        'level': 'beginner',
        'days': <dynamic>[],
        'source': 'trainer-assigned',
        'assignedBy': 'trainer-1',
        'assignedTo': 'athlete-1',
        'visibility': 'private',
      });

      final result = await repo.listAuthoredBy('trainer-1');

      expect(result.map((r) => r.id), ['r-nueva', 'r-vieja', 'r-sin-fecha']);
    });

    test('un uid vacío no consulta y devuelve vacío', () async {
      await seedAssignedRoutine(
        id: 'r1',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
      );
      expect(await repo.listAuthoredBy(''), isEmpty);
    });
  });

  // ─── listAssignedToByTrainer ───────────────────────────────────────────────

  group('RoutineRepository.listAssignedToByTrainer', () {
    test('returns only plans assigned to the athlete by the trainer', () async {
      await seedAssignedRoutine(
        id: 'r-own',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
      );
      await seedAssignedRoutine(
        id: 'r-other-trainer',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-2',
      );
      await seedAssignedRoutine(
        id: 'r-other-athlete',
        assignedTo: 'athlete-2',
        assignedBy: 'trainer-1',
      );

      final result = await repo.listAssignedToByTrainer(
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
      );

      expect(result.map((routine) => routine.id), equals(['r-own']));
    });

    test('orders raw documents by createdAt descending', () async {
      await seedAssignedRoutine(
        id: 'r-old',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(1000000),
      );
      await seedAssignedRoutine(
        id: 'r-new',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(2000000),
      );

      final result = await repo.listAssignedToByTrainer(
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
      );

      expect(result.map((routine) => routine.id), equals(['r-new', 'r-old']));
    });

    test('puts a pending null createdAt last without throwing', () async {
      await seedAssignedRoutine(
        id: 'r-persisted',
        assignedTo: 'athlete-1',
        assignedBy: 'trainer-1',
        createdAt: Timestamp.fromMillisecondsSinceEpoch(1000000),
      );
      await firestore.collection('routines').doc('r-pending').set({
        'id': 'r-pending',
        'name': 'Assigned Routine pending',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
        'source': 'trainer-assigned',
        'assignedBy': 'trainer-1',
        'assignedTo': 'athlete-1',
        'visibility': 'private',
        'createdAt': null,
      });

      final result = await repo.listAssignedToByTrainer(
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
      );

      expect(
        result.map((routine) => routine.id),
        equals(['r-persisted', 'r-pending']),
      );
    });

    test('returns empty when either id is empty', () async {
      expect(
        await repo.listAssignedToByTrainer(
          trainerId: '',
          athleteId: 'athlete-1',
        ),
        isEmpty,
      );
      expect(
        await repo.listAssignedToByTrainer(
          trainerId: 'trainer-1',
          athleteId: '',
        ),
        isEmpty,
      );
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
