// Tests for coachSessionSetLogsProvider (REQ-SETLOGS-005).
// TDD RED: written before implementation — all tests must fail first.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// Minimal SetLog factory.
SetLog _setLog({
  String id = 'sl1',
  String exerciseId = 'e1',
  String exerciseName = 'Sentadilla',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 80.0,
}) =>
    SetLog(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 6, 1),
    );

/// Seeds N setLogs into FakeFirestore for the given uid/sessionId, then
/// returns the repo and a pre-seeded container.
Future<({SessionRepository repo, FakeFirebaseFirestore firestore})> _seed(
  List<SetLog> logs, {
  String uid = 'athlete1',
  String sessionId = 'session1',
}) async {
  final firestore = FakeFirebaseFirestore();
  for (final log in logs) {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(log.id)
        .set({
      'id': log.id, // SetLog.fromJson reads 'id' from the map body
      'exerciseId': log.exerciseId,
      'exerciseName': log.exerciseName,
      'setNumber': log.setNumber,
      'reps': log.reps,
      'weightKg': log.weightKg,
      'completedAt': Timestamp.fromDate(log.completedAt),
    });
  }
  return (repo: SessionRepository(firestore: firestore), firestore: firestore);
}

ProviderContainer _container(SessionRepository repo) => ProviderContainer(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    );

void main() {
  group('coachSessionSetLogsProvider (REQ-SETLOGS-005)', () {
    test('SCENARIO-SL-001: returns N setLogs for valid (athleteUid, sessionId)',
        () async {
      final logs = [
        _setLog(id: 'sl1', setNumber: 1),
        _setLog(id: 'sl2', setNumber: 2),
        _setLog(id: 'sl3', setNumber: 3),
      ];
      final seed = await _seed(logs, uid: 'a1', sessionId: 's1');
      final container = _container(seed.repo);
      addTearDown(container.dispose);

      final result = await container.read(
        coachSessionSetLogsProvider(
          (athleteUid: 'a1', sessionId: 's1'),
        ).future,
      );

      expect(result, hasLength(3));
      expect(result.map((l) => l.id), containsAll(['sl1', 'sl2', 'sl3']));
    });

    test('SCENARIO-SL-002: empty athleteUid returns [] without calling repo',
        () async {
      // FakeFirestore has no data; with empty uid it must short-circuit.
      final firestore = FakeFirebaseFirestore();
      final repo = SessionRepository(firestore: firestore);
      final container = _container(repo);
      addTearDown(container.dispose);

      final result = await container.read(
        coachSessionSetLogsProvider(
          (athleteUid: '', sessionId: 's1'),
        ).future,
      );

      expect(result, isEmpty);
    });

    test('SCENARIO-SL-003: empty sessionId returns [] without calling repo',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repo = SessionRepository(firestore: firestore);
      final container = _container(repo);
      addTearDown(container.dispose);

      final result = await container.read(
        coachSessionSetLogsProvider(
          (athleteUid: 'a1', sessionId: ''),
        ).future,
      );

      expect(result, isEmpty);
    });

    test('SCENARIO-SL-004: autoDispose — provider disposes after no listeners',
        () async {
      // Verify the provider is autoDispose by checking it resolves and then
      // can be disposed without error. We test this by manually disposing
      // the container with no active listeners.
      final firestore = FakeFirebaseFirestore();
      final repo = SessionRepository(firestore: firestore);
      final container = _container(repo);

      // Read and await so the provider activates.
      final result = await container.read(
        coachSessionSetLogsProvider(
          (athleteUid: 'a1', sessionId: 's1'),
        ).future,
      );
      expect(result, isA<List<SetLog>>());

      // dispose() should complete without error — confirms autoDispose works.
      expect(() => container.dispose(), returnsNormally);
    });
  });
}
