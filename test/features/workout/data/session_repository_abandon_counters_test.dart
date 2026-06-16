import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/data/session_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository publicProfileRepo;
  late SessionRepository repo;

  const uid = 'user-abandon-001';
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

  // BUGFIX: abandoned sessions (status=finished, wasFullyCompleted=false) must
  // NOT inflate the public workoutsCount/racha counters. Only sessions with
  // wasFullyCompleted=true count, matching the display filter in
  // historial_section.dart and planProgressProvider.
  test(
      'abandoned session (wasFullyCompleted=false) does not increment public workoutsCount',
      () async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );

    // Abandon: finish() is called with wasFullyCompleted defaulting to false.
    await repo.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 8, 5, 0),
      totalVolumeKg: 0.0,
      durationMin: 0,
      wasFullyCompleted: false,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(profileSnap.exists, isTrue);
    final data = profileSnap.data()!;
    // Abandoned session must NOT count as a workout.
    expect(data['workoutsCount'], equals(0));
    // Abandoned session must NOT extend the streak.
    expect(data['racha'], equals(0));
  });

  test(
      'only fully completed sessions are counted when mixed with abandoned ones',
      () async {
    // One completed session.
    final completed = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );
    await repo.finish(
      uid: uid,
      sessionId: completed.id,
      finishedAt: DateTime.utc(2026, 5, 15, 9, 0, 0),
      totalVolumeKg: 100.0,
      durationMin: 60,
      wasFullyCompleted: true,
    );

    // One abandoned session.
    final abandoned = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 16, 8, 0, 0),
    );
    await repo.finish(
      uid: uid,
      sessionId: abandoned.id,
      finishedAt: DateTime.utc(2026, 5, 16, 8, 3, 0),
      totalVolumeKg: 0.0,
      durationMin: 0,
      wasFullyCompleted: false,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    final data = profileSnap.data()!;
    // Only the 1 fully completed session counts.
    expect(data['workoutsCount'], equals(1));
  });
}
