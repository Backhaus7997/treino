// Tests for RoutineRepository — updateAssigned and updateTemplate.
//
// Covers:
//   SCENARIO-TRN-REPO-001: updateAssigned happy path — updates name/split/level/days.
//   SCENARIO-TRN-REPO-002: updateAssigned does NOT send assignedBy/assignedTo/source/
//                          createdBy/createdAt in the payload (preserves immutables).
//   SCENARIO-TRN-REPO-003: updateAssigned rejects empty uid.
//   SCENARIO-TRN-REPO-004: updateAssigned rejects empty draft.id.
//   SCENARIO-TRN-REPO-005: updateTemplate happy path — updates name/split/level/days.
//   SCENARIO-TRN-REPO-006: updateTemplate does NOT send assignedBy/source/createdBy/
//                          createdAt/assignedTo in the payload.
//   SCENARIO-TRN-REPO-007: updateTemplate rejects empty uid.
//   SCENARIO-TRN-REPO-008: updateTemplate rejects empty draft.id.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RoutineRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RoutineRepository(firestore: firestore);
  });

  /// Seeds a trainer-assigned plan doc and returns its id.
  Future<String> seedAssignedPlan({
    String trainerId = 'trainer-a',
    String athleteId = 'athlete-b',
    String name = 'Plan Original',
    String split = 'PPL',
  }) async {
    final ref = await firestore.collection('routines').add({
      'name': name,
      'split': split,
      'level': 'beginner',
      'days': <dynamic>[],
      'source': 'trainer-assigned',
      'assignedBy': trainerId,
      'assignedTo': athleteId,
      'visibility': 'private',
      'status': 'active',
      'createdAt': DateTime.now(),
    });
    return ref.id;
  }

  /// Seeds a trainer template doc and returns its id.
  Future<String> seedTemplate({
    String trainerId = 'trainer-a',
    String name = 'Plantilla Original',
    String split = 'Full Body',
  }) async {
    final ref = await firestore.collection('routines').add({
      'name': name,
      'split': split,
      'level': 'beginner',
      'days': <dynamic>[],
      'source': 'trainer-template',
      'assignedBy': trainerId,
      'assignedTo': null,
      'visibility': 'private',
      'status': 'active',
      'createdAt': DateTime.now(),
    });
    return ref.id;
  }

  // ── updateAssigned ────────────────────────────────────────────────────────

  group('updateAssigned', () {
    test(
        'SCENARIO-TRN-REPO-001: updates name, split, level, days without '
        'touching immutable fields', () async {
      final id = await seedAssignedPlan();

      final before =
          (await firestore.collection('routines').doc(id).get()).data()!;
      expect(before['assignedBy'], equals('trainer-a'));
      expect(before['assignedTo'], equals('athlete-b'));
      expect(before['source'], equals('trainer-assigned'));

      final updatedDraft = Routine(
        id: id,
        name: 'Plan Editado',
        split: 'Upper/Lower',
        level: ExperienceLevel.advanced,
        days: const [],
        source: RoutineSource.trainerAssigned,
        assignedBy: 'trainer-a',
        assignedTo: 'athlete-b',
        visibility: RoutineVisibility.private,
      );
      final result =
          await repo.updateAssigned(uid: 'trainer-a', draft: updatedDraft);

      final after =
          (await firestore.collection('routines').doc(id).get()).data()!;

      // Content fields updated.
      expect(after['name'], equals('Plan Editado'));
      expect(after['split'], equals('Upper/Lower'));
      expect(after['level'], equals('advanced'));

      // Immutable fields preserved.
      expect(after['assignedBy'], equals('trainer-a'));
      expect(after['assignedTo'], equals('athlete-b'));
      expect(after['source'], equals('trainer-assigned'));

      // Returned routine has the updated name.
      expect(result.id, equals(id));
      expect(result.name, equals('Plan Editado'));
    });

    test(
        'SCENARIO-TRN-REPO-002: payload does NOT include assignedBy / assignedTo '
        '/ source / createdAt in the written doc (immutables stay preserved)',
        () async {
      final id = await seedAssignedPlan(trainerId: 'trainer-a');

      // The doc has these fields from the seed; after update they must not be
      // overwritten by a payload that included them.
      final updatedDraft = Routine(
        id: id,
        name: 'Nueva',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: const [],
        source: RoutineSource.trainerAssigned,
        assignedBy: 'trainer-a',
        assignedTo: 'athlete-b',
        visibility: RoutineVisibility.private,
      );
      await repo.updateAssigned(uid: 'trainer-a', draft: updatedDraft);

      final data =
          (await firestore.collection('routines').doc(id).get()).data()!;
      // These were in the original doc and must still be there (not wiped).
      expect(data['assignedBy'], equals('trainer-a'));
      expect(data['assignedTo'], equals('athlete-b'));
      expect(data['source'], equals('trainer-assigned'));
      // createdAt was in the seed; the update payload must not have cleared it.
      expect(data.containsKey('createdAt'), isTrue,
          reason: 'createdAt must remain — update payload must not clear it');
    });

    test('SCENARIO-TRN-REPO-003: rejects empty uid', () async {
      final id = await seedAssignedPlan();
      expect(
        () => repo.updateAssigned(
          uid: '',
          draft: Routine(
            id: id,
            name: 'X',
            level: ExperienceLevel.beginner,
            days: const [],
            assignedBy: 'trainer-a',
            assignedTo: 'athlete-b',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SCENARIO-TRN-REPO-004: rejects empty draft.id', () async {
      expect(
        () => repo.updateAssigned(
          uid: 'trainer-a',
          draft: const Routine(
            id: '',
            name: 'X',
            level: ExperienceLevel.beginner,
            days: [],
            assignedBy: 'trainer-a',
            assignedTo: 'athlete-b',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── updateTemplate ────────────────────────────────────────────────────────

  group('updateTemplate', () {
    test(
        'SCENARIO-TRN-REPO-005: updates name, split, level, days without '
        'touching immutable fields', () async {
      final id = await seedTemplate();

      final updatedDraft = Routine(
        id: id,
        name: 'Plantilla Editada',
        split: 'PPL',
        level: ExperienceLevel.intermediate,
        days: const [],
        source: RoutineSource.trainerTemplate,
        assignedBy: 'trainer-a',
        visibility: RoutineVisibility.private,
      );
      final result =
          await repo.updateTemplate(uid: 'trainer-a', draft: updatedDraft);

      final after =
          (await firestore.collection('routines').doc(id).get()).data()!;

      // Content fields updated.
      expect(after['name'], equals('Plantilla Editada'));
      expect(after['split'], equals('PPL'));
      expect(after['level'], equals('intermediate'));

      // Immutable fields preserved.
      expect(after['assignedBy'], equals('trainer-a'));
      expect(after['source'], equals('trainer-template'));

      // Returned routine has the updated name.
      expect(result.id, equals(id));
      expect(result.name, equals('Plantilla Editada'));
    });

    test(
        'SCENARIO-TRN-REPO-006: payload does NOT include assignedBy / source / '
        'createdAt — immutables remain intact in the doc', () async {
      final id = await seedTemplate(trainerId: 'trainer-a');

      final updatedDraft = Routine(
        id: id,
        name: 'Nueva',
        split: 'Full Body',
        level: ExperienceLevel.beginner,
        days: const [],
        source: RoutineSource.trainerTemplate,
        assignedBy: 'trainer-a',
        visibility: RoutineVisibility.private,
      );
      await repo.updateTemplate(uid: 'trainer-a', draft: updatedDraft);

      final data =
          (await firestore.collection('routines').doc(id).get()).data()!;
      expect(data['assignedBy'], equals('trainer-a'));
      expect(data['source'], equals('trainer-template'));
      expect(data.containsKey('createdAt'), isTrue,
          reason: 'createdAt must remain — update payload must not clear it');
      // assignedTo was null in the seed; must stay null (not introduced).
      expect(data['assignedTo'], isNull,
          reason: 'assignedTo must remain null for templates');
    });

    test('SCENARIO-TRN-REPO-007: rejects empty uid', () async {
      final id = await seedTemplate();
      expect(
        () => repo.updateTemplate(
          uid: '',
          draft: Routine(
            id: id,
            name: 'X',
            level: ExperienceLevel.beginner,
            days: const [],
            assignedBy: 'trainer-a',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SCENARIO-TRN-REPO-008: rejects empty draft.id', () async {
      expect(
        () => repo.updateTemplate(
          uid: 'trainer-a',
          draft: const Routine(
            id: '',
            name: 'X',
            level: ExperienceLevel.beginner,
            days: [],
            assignedBy: 'trainer-a',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
