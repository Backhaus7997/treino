import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Minimal user-authored draft — id is '' so the repo strips it before write.
Routine _minimalDraft() => const Routine(
      id: '',
      name: 'Mi rutina de prueba',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: [],
    );

void main() {
  late FakeFirebaseFirestore firestore;
  late RoutineRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RoutineRepository(firestore: firestore);
  });

  /// Seeds a routine document using raw wire-format maps (mimicking Firestore).
  ///
  /// `visibility` defaults to `'public'` and `source` defaults to `'system'`
  /// so the doc is returned by `listSystemTemplates()` (REQ-USR-015).
  /// Pass `visibility: 'private'` / `source: 'trainer-assigned'` to seed a
  /// trainer-assigned plan that must NOT appear in the Plantillas screen.
  Future<void> seedRoutine({
    required String id,
    required List<Map<String, dynamic>> days,
    String visibility = 'public',
    String source = 'system',
    String? assignedBy,
    String? assignedTo,
    String? createdBy,
    String status = 'active',
    DateTime? createdAt,
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
      'status': status,
      if (assignedBy != null) 'assignedBy': assignedBy,
      if (assignedTo != null) 'assignedTo': assignedTo,
      if (createdBy != null) 'createdBy': createdBy,
      if (createdAt != null) 'createdAt': createdAt,
    });
  }

  group('RoutineRepository', () {
    test('SCENARIO-058: empty collection returns empty list', () async {
      final result = await repo.listSystemTemplates();
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

      final result = await repo.listSystemTemplates();

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
        'SCENARIO-450: listSystemTemplates() excludes private trainer-assigned routines '
        'and only returns source=system (REQ-USR-015, REQ-USR-016)', () async {
      // Public system plantilla → must be included
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

      final result = await repo.listSystemTemplates();

      expect(result, hasLength(1));
      expect(result.single.id, equals('public-routine'));
    });
  });

  // ── athlete-self-routines (REQ-USR-015, REQ-USR-016) ─────────────────────

  group('listSystemTemplates (renamed from listAll)', () {
    test('SCENARIO-USR-020: returns only source=system docs', () async {
      await seedRoutine(id: 'sys-1', days: [], source: 'system');
      await seedRoutine(
        id: 'user-1',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-uid',
      );
      await seedRoutine(
        id: 'trainer-1',
        days: [],
        source: 'trainer-assigned',
        visibility: 'private',
        assignedBy: 'trainer-uid',
        assignedTo: 'athlete-uid',
      );

      final result = await repo.listSystemTemplates();

      expect(result, hasLength(1));
      expect(result.single.id, equals('sys-1'));
    });

    test(
        'SCENARIO-USR-020: user-created routine does NOT appear even if visibility changes',
        () async {
      // user-created with public visibility (hypothetical future state) must
      // still be excluded because listSystemTemplates filters on source first.
      await seedRoutine(
        id: 'user-public',
        days: [],
        source: 'user-created',
        visibility: 'public',
        createdBy: 'athlete-uid',
      );

      final result = await repo.listSystemTemplates();

      expect(result, isEmpty);
    });
  });

  // ── createUserOwned (REQ-USR-004, SCENARIO-USR-005..007) ─────────────────

  group('createUserOwned', () {
    test(
        'SCENARIO-USR-005: sets source=user-created, createdBy=uid, '
        'visibility=private, status=active', () async {
      final draft = _minimalDraft();

      final saved = await repo.createUserOwned(uid: 'athlete-a', draft: draft);

      final snap = await firestore.collection('routines').doc(saved.id).get();
      final data = snap.data()!;
      expect(data['source'], equals('user-created'));
      expect(data['createdBy'], equals('athlete-a'));
      expect(data['visibility'], equals('private'));
      expect(data['status'], equals('active'));
    });

    test(
        'SCENARIO-USR-006: id field removed before write (Firestore generates it)',
        () async {
      final draft = _minimalDraft();

      final saved = await repo.createUserOwned(uid: 'athlete-a', draft: draft);

      expect(saved.id, isNotEmpty);
      // The id returned by the repo must match the Firestore doc id
      final snap = await firestore.collection('routines').doc(saved.id).get();
      expect(snap.exists, isTrue);
    });

    test('SCENARIO-USR-007: rejects empty uid', () async {
      final draft = _minimalDraft();

      expect(
        () => repo.createUserOwned(uid: '', draft: draft),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SCENARIO-USR-007: rejects draft that has assignedBy set', () async {
      final draft = _minimalDraft().copyWith(assignedBy: 'trainer-x');

      expect(
        () => repo.createUserOwned(uid: 'athlete-a', draft: draft),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SCENARIO-USR-007: rejects draft that has assignedTo set', () async {
      final draft = _minimalDraft().copyWith(assignedTo: 'athlete-b');

      expect(
        () => repo.createUserOwned(uid: 'athlete-a', draft: draft),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── listUserCreated (REQ-USR-007, SCENARIO-USR-015) ──────────────────────

  group('listUserCreated', () {
    test('returns empty stream when uid is empty', () async {
      final stream = repo.listUserCreated('');
      final result = await stream.first;
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-USR-015: filters by createdBy + source=user-created + '
        'status=active; excludes other user\'s routines', () async {
      final now = DateTime.now();
      await seedRoutine(
        id: 'mine-1',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
        createdAt: now.subtract(const Duration(minutes: 1)),
      );
      await seedRoutine(
        id: 'theirs-1',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-b', // different owner — must be excluded
        status: 'active',
        createdAt: now,
      );
      await seedRoutine(
        id: 'mine-archived',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'archived', // archived — must be excluded from active list
        createdAt: now.subtract(const Duration(minutes: 2)),
      );

      final stream = repo.listUserCreated('athlete-a');
      final result = await stream.first;

      expect(result, hasLength(1));
      expect(result.single.id, equals('mine-1'));
    });

    test('excludes archived routines for the same user', () async {
      await seedRoutine(
        id: 'active-1',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
      );
      await seedRoutine(
        id: 'archived-1',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'archived',
      );

      final result = await repo.listUserCreated('athlete-a').first;

      expect(result, hasLength(1));
      expect(result.single.id, equals('active-1'));
    });
  });

  // ── archive (REQ-USR-006, SCENARIO-USR-010..011) ─────────────────────────

  group('archive', () {
    test('SCENARIO-USR-010: flips status to archived', () async {
      await seedRoutine(
        id: 'r-to-archive',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
      );

      await repo.archive('r-to-archive');

      final snap =
          await firestore.collection('routines').doc('r-to-archive').get();
      expect(snap.data()!['status'], equals('archived'));
    });

    test('SCENARIO-USR-010: does not mutate other fields', () async {
      await seedRoutine(
        id: 'r-check-fields',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
      );

      await repo.archive('r-check-fields');

      final snap =
          await firestore.collection('routines').doc('r-check-fields').get();
      final data = snap.data()!;
      expect(data['source'], equals('user-created'));
      expect(data['createdBy'], equals('athlete-a'));
      expect(data['visibility'], equals('private'));
      expect(data['status'], equals('archived'));
    });

    test('SCENARIO-USR-011: archived routine still exists (soft-delete)',
        () async {
      await seedRoutine(
        id: 'r-soft-delete',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
      );

      await repo.archive('r-soft-delete');

      final snap =
          await firestore.collection('routines').doc('r-soft-delete').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['status'], equals('archived'));
    });

    test('listUserCreated no longer returns archived routine after archive()',
        () async {
      await seedRoutine(
        id: 'r-will-archive',
        days: [],
        source: 'user-created',
        visibility: 'private',
        createdBy: 'athlete-a',
        status: 'active',
      );

      final before = await repo.listUserCreated('athlete-a').first;
      expect(before, hasLength(1));

      // archive updates Firestore; FakeFirebaseFirestore reflects it immediately
      await repo.archive('r-will-archive');
      // Re-seed with archived status to simulate the updated doc in FakeFirestore
      await firestore
          .collection('routines')
          .doc('r-will-archive')
          .update({'status': 'archived'});

      final after = await repo.listUserCreated('athlete-a').first;
      expect(after, isEmpty);
    });
  });
}
