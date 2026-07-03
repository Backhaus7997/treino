// Phase 3 RED — SCENARIO-RANK-5 (+ Phase 5 window-consistency fix)
// rankings-v2 Phase 1 RED — gymId/gymName denormalization + AD-4 self-heal.
//
// RankingOptInController orchestrates the opt-in toggle lifecycle:
//   - enableRankingOptIn(uid): one-time client-side backfill of
//     lifetimeVolumeKg (Σ totalVolumeKg) + bestSquatKg/bestBenchKg/
//     bestDeadliftKg (max weightKg per MainLift family), computed over the
//     SAME bounded recent-sessions window SessionRepository.finish() uses
//     (most recent 365 sessions by startedAt desc — see
//     SessionRepository.counterRecomputeWindow), then denormalizes
//     gymId/gymName from `users/{uid}.gymId` onto the public doc (design
//     AD-5, rankings-v2), then sets rankingOptIn: true. Does NOT touch
//     racha — it is already denormalized by SessionRepository.finish().
//     Using the SAME window as finish() is required so
//     lifetimeVolumeKg/best*Kg do not visibly drop on the next session
//     finish after opt-in (finish() would otherwise recompute a narrower
//     window than the backfill used, corrupting the just-set baseline).
//   - disableRankingOptIn(uid): clears the 4 ranking-metric fields and sets
//     rankingOptIn: false via UserPublicProfileRepository.clearRankingMetrics.
//     gymId/gymName are NOT cleared (design AD-5 / spec
//     user-public-profiles-layer: Opt-In Toggle Lifecycle).
//   - syncGymIfDesynced(uid): idempotent client-side self-heal (design AD-4)
//     for already-opted-in athletes whose public gymId drifted from the
//     private gymId (the reported empty-leaderboard bug).
//
// Spec: `gym-rankings` — Opt-In Toggle Lifecycle. `user-public-profiles-layer`
// — Opt-In Toggle Lifecycle (gymId/gymName sync + gymName-failure tolerance).
// Design: `sdd/rankings-v2/design` — AD-4, AD-5.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/application/ranking_optin_controller.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository sessionRepo;
  late UserPublicProfileRepository publicProfileRepo;
  late UserRepository userRepo;
  late RankingOptInController controller;

  const uid = 'athlete-rank-1';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  Future<void> seedGymDoc(String id, {required String name}) async {
    await firestore.collection('gyms').doc(id).set({
      'name': name,
      'lat': -31.4,
      'lng': -64.18,
      'geohash': 'abc123',
      'source': 'seed',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }

  Future<void> seedUser(String theUid, {String? gymId}) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc(theUid).set(
          UserProfile(
            uid: theUid,
            email: '$theUid@treino.app',
            displayName: 'Athlete $theUid',
            role: UserRole.athlete,
            createdAt: now,
            updatedAt: now,
            gymId: gymId,
          ).toJson(),
        );
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    // publicProfileRepository omitted so finish() does NOT also denormalize —
    // isolates the controller's own backfill computation from Slice 2's
    // session-finish path in these tests.
    sessionRepo = SessionRepository(firestore: firestore);
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    userRepo = UserRepository(
      firestore: firestore,
      gyms: GymRepository(firestore: firestore),
    );
    controller = RankingOptInController(
      sessionRepository: sessionRepo,
      publicProfileRepository: publicProfileRepo,
      userRepository: userRepo,
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

  // ──────────────────────────────────────────────────────────────────────────
  // rankings-v2 Phase 1 (task 1.1) — gymId/gymName denormalization on enable
  // (design AD-5, spec `user-public-profiles-layer`: Opt-In Toggle Lifecycle).
  // ──────────────────────────────────────────────────────────────────────────
  group('RankingOptInController.enableRankingOptIn — gymId/gymName denorm', () {
    test(
        'a desynced-doc athlete (private gymId set, public gymId absent) gets '
        'gymId+gymName written onto userPublicProfiles on enable', () async {
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await seedUser(uid, gymId: 'gym-123');
      await publicProfileRepo.set(const UserPublicProfile(uid: uid));

      await controller.enableRankingOptIn(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.rankingOptIn, isTrue);
      expect(profile.gymId, equals('gym-123'));
      expect(profile.gymName, equals('SportClub - Belgrano'));
    });

    test(
        'a null private gymId writes gymId:null/gymName:null on the public '
        'doc without throwing, and opt-in still succeeds', () async {
      await seedUser(uid); // gymId absent -> null
      await publicProfileRepo.set(const UserPublicProfile(uid: uid));

      await expectLater(controller.enableRankingOptIn(uid), completes);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.rankingOptIn, isTrue);
      expect(profile.gymId, isNull);
      expect(profile.gymName, isNull);
    });

    test(
        'a kNoGymId private gymId writes gymId:kNoGymId/gymName:null on the '
        'public doc without throwing', () async {
      await seedUser(uid, gymId: kNoGymId);
      await publicProfileRepo.set(const UserPublicProfile(uid: uid));

      await controller.enableRankingOptIn(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.rankingOptIn, isTrue);
      expect(profile.gymId, equals(kNoGymId));
      expect(profile.gymName, isNull);
    });

    test(
        'a gymName-resolution failure does NOT abort opt-in — rankingOptIn '
        'still becomes true, metrics and gymId still write, gymName ends up '
        'null', () async {
      // No gym doc seeded for 'ghost-gym-id' — GymRepository.getById
      // resolves to null (never throws), matching UserRepository's existing
      // _resolveGymName tolerance (SCENARIO-526).
      await seedUser(uid, gymId: 'ghost-gym-id');
      await publicProfileRepo.set(const UserPublicProfile(uid: uid));

      await expectLater(controller.enableRankingOptIn(uid), completes);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.rankingOptIn, isTrue);
      expect(profile.gymId, equals('ghost-gym-id'));
      expect(profile.gymName, isNull);
      expect(profile.lifetimeVolumeKg, equals(0));
    });

    test(
        'disabling opt-in leaves gymId/gymName unchanged — only the 4 '
        'ranking-metric fields clear', () async {
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await publicProfileRepo.set(
        const UserPublicProfile(
          uid: uid,
          rankingOptIn: true,
          gymId: 'gym-123',
          gymName: 'SportClub - Belgrano',
          lifetimeVolumeKg: 3400,
          bestSquatKg: 110,
        ),
      );

      await controller.disableRankingOptIn(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.rankingOptIn, isFalse);
      expect(profile.gymId, equals('gym-123'));
      expect(profile.gymName, equals('SportClub - Belgrano'));
      expect(profile.lifetimeVolumeKg, equals(0));
      expect(profile.bestSquatKg, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // rankings-v2 Phase 1 (task 1.4) — AD-4 idempotent client-side self-heal.
  // ──────────────────────────────────────────────────────────────────────────
  group('RankingOptInController.syncGymIfDesynced — AD-4 self-heal', () {
    test(
        'an opted-in athlete whose public gymId is null gets it re-synced '
        'from the private gymId', () async {
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await seedUser(uid, gymId: 'gym-123');
      await publicProfileRepo.set(
        const UserPublicProfile(uid: uid, rankingOptIn: true, gymId: null),
      );

      await controller.syncGymIfDesynced(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.gymId, equals('gym-123'));
      expect(profile.gymName, equals('SportClub - Belgrano'));
    });

    test(
        'an opted-in athlete whose public gymId is empty gets it re-synced '
        'from the private gymId', () async {
      await seedUser(uid, gymId: 'gym-123');
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await publicProfileRepo.set(
        const UserPublicProfile(uid: uid, rankingOptIn: true, gymId: ''),
      );

      await controller.syncGymIfDesynced(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.gymId, equals('gym-123'));
    });

    test(
        'an opted-in athlete whose public gymId is kNoGymId while the '
        'private gymId is a real gym gets it re-synced', () async {
      await seedUser(uid, gymId: 'gym-123');
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await publicProfileRepo.set(
        const UserPublicProfile(uid: uid, rankingOptIn: true, gymId: kNoGymId),
      );

      await controller.syncGymIfDesynced(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.gymId, equals('gym-123'));
    });

    test(
        'an opted-in athlete whose public gymId differs from the private '
        'gymId (stale) gets it re-synced', () async {
      await seedUser(uid, gymId: 'gym-new');
      await seedGymDoc('gym-new', name: 'Gym Nuevo');
      await publicProfileRepo.set(
        const UserPublicProfile(
          uid: uid,
          rankingOptIn: true,
          gymId: 'gym-old',
          gymName: 'Gym Viejo',
        ),
      );

      await controller.syncGymIfDesynced(uid);

      final profile = await publicProfileRepo.get(uid);
      expect(profile!.gymId, equals('gym-new'));
      expect(profile.gymName, equals('Gym Nuevo'));
    });

    test(
        'a matching gymId issues ZERO writes — idempotency (write-log '
        'assertion via userPublicProfiles updatedAt-less merge equality)',
        () async {
      await seedUser(uid, gymId: 'gym-123');
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await publicProfileRepo.set(
        const UserPublicProfile(
          uid: uid,
          rankingOptIn: true,
          gymId: 'gym-123',
          gymName: 'SportClub - Belgrano',
        ),
      );

      // Snapshot the doc before, run the self-heal, snapshot after — a
      // matching gymId must issue zero writes (no field, incl. no implicit
      // updatedAt-style bump) so the two snapshots are byte-identical.
      final before =
          await firestore.collection('userPublicProfiles').doc(uid).get();
      await controller.syncGymIfDesynced(uid);
      final after =
          await firestore.collection('userPublicProfiles').doc(uid).get();

      expect(after.data(), equals(before.data()));
    });

    test('an opted-out athlete is never touched by the self-heal (guard)',
        () async {
      await seedUser(uid, gymId: 'gym-123');
      await seedGymDoc('gym-123', name: 'SportClub - Belgrano');
      await publicProfileRepo.set(
        const UserPublicProfile(uid: uid, rankingOptIn: false, gymId: null),
      );

      await controller.syncGymIfDesynced(uid);

      final profile = await publicProfileRepo.get(uid);
      // Guard: opted-out athletes are never touched, gymId stays null.
      expect(profile!.gymId, isNull);
    });

    test(
        'a best-effort failure during self-heal is swallowed (does not '
        'throw, does not break the caller)', () async {
      // No users/{uid} doc seeded at all -> UserRepository.get(uid) returns
      // null -> the self-heal has no private gymId to compare against and
      // must swallow this gracefully rather than throwing.
      await publicProfileRepo.set(
        const UserPublicProfile(uid: uid, rankingOptIn: true, gymId: null),
      );

      await expectLater(controller.syncGymIfDesynced(uid), completes);
    });
  });
}
