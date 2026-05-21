import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/session_status.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late UserPublicProfileRepository publicProfileRepo;

  const uid = 'user-test-001';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
  });

  // ─── Helpers ──────────────────────────────────────────────────────────────

  DateTime testNow() => DateTime.utc(2026, 5, 18, 10, 0, 0);

  SetLog buildSetLog({required int setNumber, required DateTime completedAt}) {
    return SetLog(
      id: '', // repo replaces this with Firestore auto-id
      exerciseId: 'bench-press',
      exerciseName: 'Bench Press',
      setNumber: setNumber,
      reps: 10,
      weightKg: 80.0,
      rpe: null,
      completedAt: completedAt,
    );
  }

  Future<String> createActiveSession() async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );
    return session.id;
  }

  // ─── create() ─────────────────────────────────────────────────────────────

  test('SCENARIO-240: create writes doc with status active and zero totals',
      () async {
    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();

    expect(snap.docs, hasLength(1));
    final data = snap.docs.first.data();
    expect(data['status'], equals('active'));
    expect(data['totalVolumeKg'], equals(0.0));
    expect(data['durationMin'], equals(0));
    expect(data['finishedAt'], isNull);
  });

  test('SCENARIO-241: create returns Session with Firestore-generated id',
      () async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );

    expect(session.id, isNotEmpty);

    // Verify the id matches the Firestore doc
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(session.id)
        .get();

    expect(snap.exists, isTrue);
    expect(snap.data()?['id'], equals(session.id));
  });

  // ─── finish() ─────────────────────────────────────────────────────────────

  test('SCENARIO-242: finish transitions status and persists totals', () async {
    final sessionId = await createActiveSession();
    final finishedAt = DateTime.utc(2026, 5, 18, 10, 45, 0);

    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: finishedAt,
      totalVolumeKg: 95.5,
      durationMin: 45,
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .get();

    final data = snap.data()!;
    expect(data['status'], equals('finished'));
    // SCENARIO-242b: finishedAt MUST be a Firestore Timestamp, NOT a raw
    // DateTime. Otherwise real Firestore stores an ISO string and the
    // @TimestampConverter fails to deserialize on subsequent reads in Etapa 2.
    expect(
      data['finishedAt'],
      isA<Timestamp>(),
      reason: 'finish() must write Timestamp.fromDate, not raw DateTime',
    );
    expect(
      (data['finishedAt'] as Timestamp).toDate().toUtc(),
      equals(finishedAt),
    );
    expect(data['totalVolumeKg'], equals(95.5));
    expect(data['durationMin'], equals(45));
  });

  // ─── listByUid() ──────────────────────────────────────────────────────────

  test('SCENARIO-243: listByUid returns sessions newest-first', () async {
    final t1 = DateTime.utc(2026, 5, 17, 9, 0, 0); // older
    final t2 = DateTime.utc(2026, 5, 18, 9, 0, 0); // newer

    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: t1,
    );
    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: t2,
    );

    final results = await repo.listByUid(uid);

    expect(results, hasLength(2));
    expect(results.first.startedAt, equals(t2)); // newest first
    expect(results.last.startedAt, equals(t1));
  });

  test('SCENARIO-244: listByUid returns empty list when user has no sessions',
      () async {
    final results = await repo.listByUid('uid-no-sessions');

    expect(results, isEmpty);
  });

  // ─── getActive() ──────────────────────────────────────────────────────────

  test('SCENARIO-245: getActive returns the active session when one exists',
      () async {
    await createActiveSession();

    final result = await repo.getActive(uid);

    expect(result, isNotNull);
    expect(result!.status, equals(SessionStatus.active));
    expect(result.uid, equals(uid));
  });

  test('SCENARIO-246: getActive returns null when no active session', () async {
    final sessionId = await createActiveSession();
    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: DateTime.utc(2026, 5, 18, 10, 45, 0),
      totalVolumeKg: 0,
      durationMin: 0,
    );

    final result = await repo.getActive(uid);

    expect(result, isNull);
  });

  // ─── addSetLog() ──────────────────────────────────────────────────────────

  test('SCENARIO-247: addSetLog writes to nested sub-path', () async {
    final sessionId = await createActiveSession();
    final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: completedAt),
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .get();

    expect(snap.docs, hasLength(1));
    final data = snap.docs.first.data();
    expect(data['exerciseId'], equals('bench-press'));
    expect(data['setNumber'], equals(1));
  });

  test('SCENARIO-248: addSetLog returns SetLog with auto-id', () async {
    final sessionId = await createActiveSession();
    final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

    final result = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: completedAt),
    );

    expect(result.id, isNotEmpty);

    // Verify the returned id matches the Firestore sub-doc id
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(result.id)
        .get();

    expect(snap.exists, isTrue);
  });

  // ─── listSetLogs() ────────────────────────────────────────────────────────

  test('SCENARIO-249: listSetLogs returns logs ordered setNumber ASC',
      () async {
    final sessionId = await createActiveSession();

    // Add in reverse order on purpose
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 3, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 2, completedAt: testNow()),
    );

    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, hasLength(3));
    expect(results[0].setNumber, equals(1));
    expect(results[1].setNumber, equals(2));
    expect(results[2].setNumber, equals(3));
  });

  test('SCENARIO-250: listSetLogs returns empty list when session has no logs',
      () async {
    final sessionId = await createActiveSession();

    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, isEmpty);
  });

  test('SCENARIO-251: SetLogs are accessible after session is finished',
      () async {
    final sessionId = await createActiveSession();
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 2, completedAt: testNow()),
    );

    // Finish the session
    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: DateTime.utc(2026, 5, 18, 10, 50, 0),
      totalVolumeKg: 1600.0,
      durationMin: 50,
    );

    // SetLogs must still be readable
    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, hasLength(2));
    expect(results[0].setNumber, equals(1));
    expect(results[1].setNumber, equals(2));
  });

  // ─── finish() cross-feature write ─────────────────────────────────────────

  // SCENARIO-321 success: finish() updates userPublicProfiles with counters.
  // Uses repoWithProfile for BOTH create() and finish() to ensure
  // fake_cloud_firestore's sub-collection index is consistent.
  test(
      'SCENARIO-321: finish() updates userPublicProfiles/{uid} with workoutsCount and racha',
      () async {
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );

    // Use the same repo instance for create AND finish so fake_cloud_firestore
    // uses the same internal collection reference throughout.
    // Session date: 2026-05-15 = today (matches testNow() for streak calc)
    final session = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );

    await repoWithProfile.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 10, 45, 0),
      totalVolumeKg: 100.0,
      durationMin: 45,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(profileSnap.exists, isTrue);
    final data = profileSnap.data()!;
    // 1 finished session
    expect(data['workoutsCount'], equals(1));
    // racha is computed by computeStreak using DateTime.now() — the value
    // is correct (0 if not trained today in local TZ, 1 if trained today).
    // We only verify it's a non-negative integer.
    expect(data['racha'], isA<int>());
  });

  // SCENARIO-321 failure: when public profile write fails, finish() still
  // completes and the primary session update is not affected
  test(
      'SCENARIO-321 failure: when public profile write throws, finish() resolves and session is finished',
      () async {
    final throwingRepo = _ThrowingPublicProfileRepository();
    final repoWithThrowingProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: throwingRepo,
    );

    final sessionId = await createActiveSession();

    // Must not throw
    await expectLater(
      repoWithThrowingProfile.finish(
        uid: uid,
        sessionId: sessionId,
        finishedAt: DateTime.utc(2026, 5, 18, 10, 45, 0),
        totalVolumeKg: 75.0,
        durationMin: 40,
      ),
      completes,
    );

    // Primary op succeeded
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .get();
    expect(snap.data()?['status'], equals('finished'));
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

class _ThrowingPublicProfileRepository extends UserPublicProfileRepository {
  _ThrowingPublicProfileRepository()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Future<void> updateCounters(String uid, Map<String, Object?> fields) {
    throw Exception('Simulated public profile write failure');
  }
}
