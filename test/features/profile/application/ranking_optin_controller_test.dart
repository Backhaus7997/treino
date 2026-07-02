// Phase 3 RED — SCENARIO-RANK-5 (+ Phase 5 window-consistency fix)
//
// RankingOptInController orchestrates the opt-in toggle lifecycle:
//   - enableRankingOptIn(uid): one-time client-side backfill of
//     lifetimeVolumeKg (Σ totalVolumeKg) + bestSquatKg/bestBenchKg/
//     bestDeadliftKg (max weightKg per MainLift family), computed over the
//     SAME bounded recent-sessions window SessionRepository.finish() uses
//     (most recent 365 sessions by startedAt desc — see
//     SessionRepository.counterRecomputeWindow), then sets
//     rankingOptIn: true. Does NOT touch racha — it is already denormalized
//     by SessionRepository.finish(). Using the SAME window as finish() is
//     required so lifetimeVolumeKg/best*Kg do not visibly drop on the next
//     session finish after opt-in (finish() would otherwise recompute a
//     narrower window than the backfill used, corrupting the just-set
//     baseline).
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
  // SCENARIO-RANK-5e: enable backfill uses the SAME bounded window as
  // finish() — a session outside the window must NOT count, and the
  // backfilled value must match what finish() would recompute on the very
  // next session finish (window-consistency fix, Phase 5).
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5e: enableRankingOptIn backfills over the SAME bounded '
      'window as finish() (sessions outside the window are excluded, and '
      'finish() immediately after opt-in does not change the backfilled '
      'value)', () async {
    await publicProfileRepo.set(const UserPublicProfile(uid: uid));

    // One session strictly OUTSIDE the recompute window (oldest by
    // startedAt) plus [SessionRepository.counterRecomputeWindow] sessions
    // INSIDE the window — mirrors finish()'s
    // .orderBy('startedAt', descending: true).limit(counterRecomputeWindow).
    await createFinishedSession(
      startedAt: DateTime.utc(2020, 1, 1, 8, 0, 0),
      finishedAt: DateTime.utc(2020, 1, 1, 9, 0, 0),
      totalVolumeKg: 999999.0,
    );

    const windowSize = SessionRepository.counterRecomputeWindow;
    for (var i = 0; i < windowSize; i++) {
      await createFinishedSession(
        startedAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        finishedAt: DateTime.utc(2026, 1, 1).add(Duration(days: i, hours: 1)),
        totalVolumeKg: 10.0,
      );
    }

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    // Only the windowSize in-window sessions (10.0 each) count — the
    // out-of-window 2020 session's 999999.0 is excluded.
    expect(profile!.lifetimeVolumeKg, equals(windowSize * 10.0));

    // finish() immediately after opt-in must NOT change the just-backfilled
    // value — proves both computations agree on the SAME window.
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );
    final nextSession = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 1, 1).add(const Duration(days: windowSize)),
    );
    await repoWithProfile.finish(
      uid: uid,
      sessionId: nextSession.id,
      finishedAt: DateTime.utc(2026, 1, 1)
          .add(const Duration(days: windowSize, hours: 1)),
      totalVolumeKg: 10.0,
      durationMin: 45,
      wasFullyCompleted: true,
    );

    final afterFinish = await publicProfileRepo.get(uid);
    // Window slides by one (oldest in-window session drops out, new session
    // enters) — net change is 0 since both are 10.0. Critically, it must NOT
    // jump back up by 999999.0, nor drop to a bounded-vs-unbounded mismatch.
    expect(afterFinish!.lifetimeVolumeKg, equals(windowSize * 10.0));
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
