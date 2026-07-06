// Phase 3 RED — SCENARIO-RANK-5 (+ Phase 5 window-consistency fix)
// rankings-v2 Phase 1 RED — gymId/gymName denormalization + AD-4 self-heal.
// sdd/rankings-integrity Phase 1 — enableRankingOptIn no longer computes
// ranking metrics client-side; SCENARIO-RANK-5a/5d rewritten accordingly.
//
// RankingOptInController orchestrates the opt-in toggle lifecycle:
//   - enableRankingOptIn(uid): writes ONLY the eligibility intent —
//     denormalizes gymId/gymName from `users/{uid}.gymId` onto the public
//     doc (design AD-5, rankings-v2), then sets rankingOptIn: true. As of
//     `sdd/rankings-integrity` (AD-2/AD-9), it does NOT compute or write
//     lifetimeVolumeKg/best<Lift>Kg — the server-side recompute trigger
//     (rankingAggregateOnOptIn, functions/src/ranking-aggregate.ts) is the
//     sole authority for those 4 fields now, firing on the rankingOptIn
//     false→true transition this method writes. Does NOT touch racha — it
//     is already denormalized by SessionRepository.finish().
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
// Design: `sdd/rankings-v2/design` — AD-4, AD-5. `sdd/rankings-integrity/design`
// — AD-2, AD-9.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

class _MockUserPublicProfileRepository extends Mock
    implements UserPublicProfileRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

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
  // SCENARIO-RANK-5a (rewritten, sdd/rankings-integrity Phase 1): enable no
  // longer backfills metrics from own session history — that computation now
  // lives server-side (rankingAggregateOnOptIn trigger, AD-2/AD-9). The
  // fake_cloud_firestore instance used by these tests has no trigger runtime
  // (Admin SDK-only, deployed separately), so lifetimeVolumeKg/best*Kg stay
  // at their pre-opt-in default (absent/null) after enableRankingOptIn —
  // proving the client itself no longer writes them, not that they're zero
  // by computation.
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5a (rewritten): enableRankingOptIn does NOT write '
      'lifetimeVolumeKg/best*Kg even when the athlete has real training '
      'history — metrics are left untouched, only rankingOptIn:true is set',
      () async {
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

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile, isNotNull);
    expect(profile!.rankingOptIn, isTrue);
    // Metrics are NOT computed/written by the client anymore — they stay at
    // the pre-opt-in default. The server-side trigger (deployed separately,
    // not present in this fake_cloud_firestore instance) is the only writer.
    expect(profile.lifetimeVolumeKg, equals(0));
    expect(profile.bestSquatKg, isNull);
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
  // SCENARIO-RANK-5d (rewritten, sdd/rankings-integrity Phase 1): enabling
  // opt-in with no training history leaves ranking metrics at their true
  // model default (lifetimeVolumeKg:0, best*Kg:null) since the client no
  // longer writes them at all — this is the server-side trigger's job now,
  // and a just-opted-in athlete with zero qualifying sessions is expected to
  // show zero/empty per spec (`gym-rankings: Opting in with zero qualifying
  // sessions shows zero, not stale or forged data`).
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-5d (rewritten): enableRankingOptIn with no session '
      'history leaves ranking metrics at their model default', () async {
    await publicProfileRepo.set(const UserPublicProfile(uid: uid));

    await controller.enableRankingOptIn(uid);

    final profile = await publicProfileRepo.get(uid);
    expect(profile!.rankingOptIn, isTrue);
    expect(profile.lifetimeVolumeKg, equals(0));
    expect(profile.bestSquatKg, isNull);
    expect(profile.bestBenchKg, isNull);
    expect(profile.bestDeadliftKg, isNull);
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

  // ──────────────────────────────────────────────────────────────────────────
  // sdd/rankings-integrity Phase 1 (task 1.17) — enableRankingOptIn no longer
  // computes ranking metrics client-side (design AD-2, AD-9). The server-side
  // recompute trigger (rankingAggregateOnOptIn) is now the sole writer of the
  // 4 ranking-metric fields; enableRankingOptIn writes ONLY gymId/gymName
  // (unchanged AD-5 denorm path) then rankingOptIn:true — the intent, not
  // the metrics themselves. The controller no longer takes a
  // SessionRepository dependency at all (removed from the constructor) —
  // the strongest possible guarantee that it cannot read session/SetLog
  // history from this method.
  // ──────────────────────────────────────────────────────────────────────────
  group(
      'RankingOptInController.enableRankingOptIn — server-authoritative '
      'metrics (rankings-integrity)', () {
    late _MockUserPublicProfileRepository mockPublicProfileRepo;
    late _MockUserRepository mockUserRepo;
    late RankingOptInController serverAuthorityController;

    setUpAll(() {
      registerFallbackValue(<String, Object?>{});
    });

    setUp(() {
      mockPublicProfileRepo = _MockUserPublicProfileRepository();
      mockUserRepo = _MockUserRepository();
      serverAuthorityController = RankingOptInController(
        publicProfileRepository: mockPublicProfileRepo,
        userRepository: mockUserRepo,
      );

      when(() => mockUserRepo.get(uid)).thenAnswer(
        (_) async => UserProfile(
          uid: uid,
          email: '$uid@treino.app',
          displayName: 'Athlete',
          role: UserRole.athlete,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          gymId: 'gym-123',
        ),
      );
      when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});
      when(() => mockPublicProfileRepo.setRankingOptIn(any(), any()))
          .thenAnswer((_) async {});
    });

    test('enableRankingOptIn writes gymId then rankingOptIn:true', () async {
      await serverAuthorityController.enableRankingOptIn(uid);

      verify(() => mockUserRepo.update(uid, {'gymId': 'gym-123'})).called(1);
      verify(() => mockPublicProfileRepo.setRankingOptIn(uid, true)).called(1);
    });

    test(
        'enableRankingOptIn does NOT call updateCounters at all — the '
        'server-side trigger owns the 4 ranking-metric fields now', () async {
      await serverAuthorityController.enableRankingOptIn(uid);

      verifyNever(() => mockPublicProfileRepo.updateCounters(any(), any()));
    });
  });
}
