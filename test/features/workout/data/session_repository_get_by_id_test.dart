// Tests for SessionRepository.getById — SCENARIO-334..336
// TDD RED: these tests fail before getById is implemented.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'u1';
  const sessionId = 's1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  Map<String, Object?> sessionData(String id) => {
        'id': id,
        'uid': uid,
        'routineId': 'r1',
        'routineName': 'Push Pull Legs',
        'startedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18, 10, 0)),
        'finishedAt': null,
        'totalVolumeKg': 0.0,
        'durationMin': 0,
        'status': 'active',
        'dayNumber': 1,
        'wasFullyCompleted': false,
      };

  test('SCENARIO-334: getById returns Session when document exists', () async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .set(sessionData(sessionId));

    final result = await repo.getById(uid: uid, sessionId: sessionId);

    expect(result, isNotNull);
    expect(result!.id, equals(sessionId));
  });

  test('SCENARIO-335: getById returns null when document does not exist',
      () async {
    final result = await repo.getById(uid: uid, sessionId: 'unknown-id');

    expect(result, isNull);
  });

  test(
      'SCENARIO-336: getById reads from correct Firestore path users/{uid}/sessions/{sessionId}',
      () async {
    // Seed at the correct sub-path
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .set(sessionData(sessionId));

    // A different path should NOT return a result
    final wrongPath =
        await repo.getById(uid: 'other-uid', sessionId: sessionId);
    expect(wrongPath, isNull);

    // The correct path should return the session
    final correct = await repo.getById(uid: uid, sessionId: sessionId);
    expect(correct, isNotNull);
    expect(correct!.uid, equals(uid));
  });
}
