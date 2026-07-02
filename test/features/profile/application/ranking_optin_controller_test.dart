// Phase 3 RED — SCENARIO-RANK-5
//
// RankingOptInController orchestrates the opt-in toggle lifecycle:
//   - enableRankingOptIn(uid): one-time client-side backfill of
//     lifetimeVolumeKg (Σ totalVolumeKg over the athlete's own FULL
//     completed-session history) + bestSquatKg/bestBenchKg/bestDeadliftKg
//     (max weightKg per MainLift family over the athlete's own FULL SetLog
//     history), then sets rankingOptIn: true. Does NOT touch racha — it is
//     already denormalized by SessionRepository.finish().
//   - disableRankingOptIn(uid): clears the 4 ranking-metric fields and sets
//     rankingOptIn: false via UserPublicProfileRepository.clearRankingMetrics.
//
// Spec: `gym-rankings` — Opt-In Toggle Lifecycle (SCENARIO: enabling opt-in
// backfills historical metrics / disabling opt-in clears ranking metrics /
// streak is not backfilled on enable).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/ranking_optin_controller.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository sessionRepo;
  late UserPublicProfileRepository publicProfileRepo;
  late RankingOptInController controller;

  const uid = 'athlete-rank-1';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    // publicProfileRepository omitted so finish() does NOT also denormalize —
    // isolates the controller's own backfill computation from Slice 2's
    // session-finish path in these tests.
    sessionRepo = SessionRepository(firestore: firestore);
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    controller = RankingOptInController(
      sessionRepository: sessionRepo,
      publicProfileRepository: publicProfileRepo,
    );
  });

  Future<String> createFinishedSession({
    required DateTime startedAt,
    required DateTime finishedAt,
    required double totalVolumeKg,
  }) async {
    final session = await sessionRepo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: startedAt,
    );
    await sessionRepo.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: finishedAt,
      totalVolumeKg: totalVolumeKg,
      durationMin: 45,
      wasFullyCompleted: true,
    );
    return session.id;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-5a: enable backfills lifetimeVolumeKg + best-lift PRs
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5a: enableRankingOptIn backfills lifetimeVolumeKg and '
      'bestSquatKg/bestBenchKg/bestDeadliftKg from own history', () async {
    await publicProfileRepo.set(const UserPublicProfile(uid: uid));

    final s1 = await createFinishedSession(
      startedAt: DateTime.utc(2026, 1, 10, 8, 0, 0),
      finishedAt: DateTime.utc(2026, 1, 10, 9, 0, 0),
      totalVolumeKg: 1400.0,
    );
    await sessionRepo.addSetLog(
      uid: uid,
      sessionId: s1,
      setLog: SetLog(
        id: '',
        exerciseId: 'squat-barra',
        exerciseName: 'Sentadilla (Barra)',
        setNumber: 1,
        reps: 5,
        weightKg: 100,
        completedAt: DateTime.utc(2026, 1, 10, 8, 10, 0),
      ),
    );

    final s2 = await createFinishedSession(
      startedAt: DateTime.utc(2026, 2, 1, 8, 0, 0),
      finishedAt: DateTime.utc(2026, 2, 1, 9, 0, 0),
      totalVolumeKg: 2000.0,
    );
    await sessionRepo.addSetLog(
      uid: uid,
      sessionId: s2,
      setLog: SetLog(
        id: '',
        exerciseId: 'squat-barra',
        exerciseName: 'Sentadilla (Barra)',
        setNumber: 1,
        reps: 3,
        weightKg: 110,
        completedAt: DateTime.utc(2026, 2, 1, 8, 10, 0),
      ),
    );
    await sessionRepo.addSetLog(
      uid: uid,
      sessionId: s2,
      setLog: SetLog(
        id: '',
        exerciseId: 'bench-press-barra',
        exerciseName: 'Press de banca (Barra)',
        setNumber: 1,
        reps: 5,
        weightKg: 80,
        completedAt: DateTime.utc(2026, 2, 1, 8, 20, 0),
      ),
    );

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile, isNotNull);
    expect(profile!.rankingOptIn, isTrue);
    expect(profile.lifetimeVolumeKg, equals(3400.0));
    expect(profile.bestSquatKg, equals(110));
    expect(profile.bestBenchKg, equals(80));
    // No deadlift logged in history → 0 per spec ("0 if no matching lifts")
    expect(profile.bestDeadliftKg, equals(0));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-5b: enable does NOT recompute racha
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-RANK-5b: enableRankingOptIn does not touch racha', () async {
    await publicProfileRepo.set(
      const UserPublicProfile(uid: uid, racha: 7),
    );

    await createFinishedSession(
      startedAt: DateTime.utc(2026, 1, 10, 8, 0, 0),
      finishedAt: DateTime.utc(2026, 1, 10, 9, 0, 0),
      totalVolumeKg: 500.0,
    );

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile!.racha, equals(7));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-5c: disable clears all 4 ranking-metric fields
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5c: disableRankingOptIn clears lifetimeVolumeKg and '
      'best*Kg and sets rankingOptIn false', () async {
    await publicProfileRepo.set(
      const UserPublicProfile(
        uid: uid,
        rankingOptIn: true,
        lifetimeVolumeKg: 3400,
        bestSquatKg: 110,
        bestBenchKg: 80,
        bestDeadliftKg: 150,
      ),
    );

    await controller.disableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile, isNotNull);
    expect(profile!.rankingOptIn, isFalse);
    expect(profile.lifetimeVolumeKg, equals(0));
    expect(profile.bestSquatKg, isNull);
    expect(profile.bestBenchKg, isNull);
    expect(profile.bestDeadliftKg, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-5d: enable with no training history backfills zeros
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5d: enableRankingOptIn with no session history backfills '
      'lifetimeVolumeKg=0 and best*Kg=0', () async {
    await publicProfileRepo.set(const UserPublicProfile(uid: uid));

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile!.rankingOptIn, isTrue);
    expect(profile.lifetimeVolumeKg, equals(0));
    expect(profile.bestSquatKg, equals(0));
    expect(profile.bestBenchKg, equals(0));
    expect(profile.bestDeadliftKg, equals(0));
  });
}
