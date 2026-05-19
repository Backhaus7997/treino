import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/set_log.dart';

ProviderContainer makeContainer({required SessionRepository repo}) =>
    ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ],
    );

void main() {
  group('session providers', () {
    test(
        'SCENARIO-256: sessionRepositoryProvider resolves with FakeFirebaseFirestore override',
        () {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      // Should not throw — just reads the provider.
      final repo = container.read(sessionRepositoryProvider);
      expect(repo, isA<SessionRepository>());
    });

    test(
        'SCENARIO-257: sessionsByUidProvider returns empty list for unknown uid',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(sessionsByUidProvider('uid_nobody').future);
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-258: sessionsByUidProvider returns empty list when uid is empty',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(sessionsByUidProvider('').future);
      expect(result, isEmpty);
    });

    test('SCENARIO-259: activeSessionProvider returns null when uid is empty',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(activeSessionProvider('').future);
      expect(result, isNull);
    });

    test(
        'SCENARIO-260: activeSessionProvider returns null when no active session exists',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(activeSessionProvider('uid_001').future);
      expect(result, isNull);
    });
  });

  // ─── sessionSummaryProvider ───────────────────────────────────────────────

  group('sessionSummaryProvider', () {
    const uid = 'u1';
    const sessionId = 's1';

    Map<String, Object?> sessionData() => {
          'id': sessionId,
          'uid': uid,
          'routineId': 'r1',
          'routineName': 'Push Pull Legs',
          'startedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18, 10, 0)),
          'finishedAt': null,
          'totalVolumeKg': 50.0,
          'durationMin': 30,
          'status': 'finished',
          'dayNumber': 1,
          'wasFullyCompleted': true,
        };

    Map<String, Object?> setLogData(int setNumber) => {
          'id': 'sl$setNumber',
          'exerciseId': 'e1',
          'exerciseName': 'Bench Press',
          'setNumber': setNumber,
          'reps': 10,
          'weightKg': 60.0,
          'rpe': null,
          'completedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18, 10, 5)),
        };

    test(
        'SCENARIO-334 (integrated): returns record with session + setLogs when both succeed',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Seed session
      await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .set(sessionData());
      // Seed 3 setLogs
      for (int i = 1; i <= 3; i++) {
        await firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(sessionId)
            .collection('setLogs')
            .doc('sl$i')
            .set(setLogData(i));
      }

      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionSummaryProvider((uid: uid, sessionId: sessionId)).future,
      );

      expect(result.session, isNotNull);
      expect(result.session!.id, equals(sessionId));
      expect(result.setLogs, hasLength(3));
      expect(result.setLogs, everyElement(isA<SetLog>()));
    });

    test(
        'SCENARIO-335 (integrated): returns session=null when getById returns null',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionSummaryProvider((uid: uid, sessionId: 'nonexistent')).future,
      );

      expect(result.session, isNull);
      expect(result.setLogs, isEmpty);
    });

    test('SCENARIO error: propagates error when repo throws', () async {
      // Use a fake repo that throws
      final throwingRepo = _ThrowingSessionRepository();
      final container = ProviderContainer(
        overrides: [sessionRepositoryProvider.overrideWithValue(throwingRepo)],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(
          sessionSummaryProvider((uid: uid, sessionId: sessionId)).future,
        ),
        throwsA(anything),
      );
    });
  });
}

// ─── Fake repo that always throws on getById ─────────────────────────────────

class _ThrowingSessionRepository extends SessionRepository {
  _ThrowingSessionRepository() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<Session?> getById({
    required String uid,
    required String sessionId,
  }) async {
    throw Exception('Repo error');
  }
}
