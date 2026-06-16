import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/data/session_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository publicProfileRepo;
  late SessionRepository repo;

  const uid = 'user-bounded-001';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    repo = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );
  });

  // Seeds [count] finished + fully-completed session docs directly (fast), one
  // per distinct day counting back from [latestDay], so they all decode and
  // count toward the recompute.
  Future<void> seedFinishedSessions({
    required int count,
    required DateTime latestDay,
  }) async {
    final col = firestore.collection('users').doc(uid).collection('sessions');
    for (var i = 0; i < count; i++) {
      final day = latestDay.subtract(Duration(days: i));
      final ref = col.doc();
      await ref.set({
        'id': ref.id,
        'uid': uid,
        'routineId': routineId,
        'routineName': routineName,
        'startedAt': Timestamp.fromDate(day),
        'finishedAt': Timestamp.fromDate(day.add(const Duration(hours: 1))),
        'totalVolumeKg': 50.0,
        'durationMin': 30,
        'status': 'finished',
        'wasFullyCompleted': true,
        'dayNumber': 1,
        'weekNumber': 0,
      });
    }
  }

  // BUGFIX: finish() previously read the ENTIRE sessions collection (no limit)
  // on every workout completion, so read cost grew linearly with the user's
  // lifetime session count. It now reads only a bounded recent window. With a
  // history LARGER than that window, the recomputed workoutsCount is capped at
  // the window size — proving the .limit() is applied. (If the limit were
  // dropped, this count would equal the full lifetime total instead.)
  test(
      'finish() recomputes counters from a bounded recent window, not the full collection',
      () async {
    // Seed more finished sessions than the recompute window can hold.
    const window = 365; // mirrors SessionRepository._counterRecomputeWindow
    await seedFinishedSessions(
      count: window + 25,
      latestDay: DateTime.utc(2026, 5, 10, 8, 0, 0),
    );

    // One MORE fresh session, finished today.
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 11, 8, 0, 0),
    );
    await repo.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 11, 9, 0, 0),
      totalVolumeKg: 100.0,
      durationMin: 60,
      wasFullyCompleted: true,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    final data = profileSnap.data()!;

    // Lifetime history is window + 26 completed sessions, but the recompute is
    // bounded — workoutsCount is capped at the window size, never the full
    // total. A linear full read would have produced window + 26 here.
    expect(data['workoutsCount'], equals(window));
    expect(data['workoutsCount'], lessThan(window + 26));
  });
}
