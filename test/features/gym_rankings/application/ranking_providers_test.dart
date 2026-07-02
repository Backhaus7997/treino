// Phase 4 RED — SCENARIO-RANK-6
//
// Per-dimension ranking query providers wrap
// UserPublicProfileRepository.leaderboard(gymId, dimension, limit) with a
// Riverpod FutureProvider.family<List<UserPublicProfile>, String> (family key
// = gymId), one provider per RankingDimension (streak/volume/squat/bench/
// deadlift). Mirrors the assignedRoutinesProvider pattern (thin provider,
// query lives in the repository).
//
// Spec `gym-rankings`:
//   - Streak/Volume/Main-Lift Leaderboards: gymId + rankingOptIn==true,
//     ordered desc by the dimension's metric, limit N.
//   - Gym Scoping and No-Gym Exclusion: kNoGymId/null excluded.
//   - Empty States: gym with zero opted-in athletes → empty list, not error.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gym_rankings/application/ranking_providers.dart';
import 'package:treino/features/gym_rankings/domain/ranking_dimension.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository repo;

  const gymA = 'gym-a';
  const gymB = 'gym-b';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserPublicProfileRepository(firestore: firestore);
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        rankingRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seed(UserPublicProfile profile) => repo.set(profile);

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6a: streak leaderboard orders desc by racha, gym-scoped
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6a: streakLeaderboardProvider orders opted-in athletes '
      'desc by racha, scoped to gymId', () async {
    await seed(const UserPublicProfile(
      uid: 'u1',
      gymId: gymA,
      rankingOptIn: true,
      racha: 5,
    ));
    await seed(const UserPublicProfile(
      uid: 'u2',
      gymId: gymA,
      rankingOptIn: true,
      racha: 12,
    ));
    await seed(const UserPublicProfile(
      uid: 'u3',
      gymId: gymA,
      rankingOptIn: true,
      racha: 8,
    ));
    // Different gym — must be excluded from gymA's leaderboard.
    await seed(const UserPublicProfile(
      uid: 'u4',
      gymId: gymB,
      rankingOptIn: true,
      racha: 99,
    ));

    final container = buildContainer();
    final result = await container.read(streakLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['u2', 'u3', 'u1']));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6b: excludes non-opted-in athletes
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6b: streakLeaderboardProvider excludes athletes with '
      'rankingOptIn == false', () async {
    await seed(const UserPublicProfile(
      uid: 'opted-in',
      gymId: gymA,
      rankingOptIn: true,
      racha: 3,
    ));
    await seed(const UserPublicProfile(
      uid: 'opted-out',
      gymId: gymA,
      rankingOptIn: false,
      racha: 50,
    ));

    final container = buildContainer();
    final result = await container.read(streakLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['opted-in']));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6c: excludes kNoGymId / null gym
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6c: volumeLeaderboardProvider excludes athletes with no '
      'gym (kNoGymId or null)', () async {
    await seed(const UserPublicProfile(
      uid: 'has-gym',
      gymId: gymA,
      rankingOptIn: true,
      lifetimeVolumeKg: 1000,
    ));
    await seed(const UserPublicProfile(
      uid: 'no-gym-sentinel',
      gymId: 'no-gym',
      rankingOptIn: true,
      lifetimeVolumeKg: 5000,
    ));

    final container = buildContainer();
    final result = await container.read(volumeLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['has-gym']));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6d: volume leaderboard orders desc by lifetimeVolumeKg
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6d: volumeLeaderboardProvider orders desc by '
      'lifetimeVolumeKg', () async {
    await seed(const UserPublicProfile(
      uid: 'low',
      gymId: gymA,
      rankingOptIn: true,
      lifetimeVolumeKg: 3400,
    ));
    await seed(const UserPublicProfile(
      uid: 'high',
      gymId: gymA,
      rankingOptIn: true,
      lifetimeVolumeKg: 5200,
    ));

    final container = buildContainer();
    final result = await container.read(volumeLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['high', 'low']));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6e: squat/bench/deadlift leaderboards order desc by their
  // respective best<Lift>Kg field
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6e: squatLeaderboardProvider orders desc by '
      'bestSquatKg', () async {
    await seed(const UserPublicProfile(
      uid: 'low',
      gymId: gymA,
      rankingOptIn: true,
      bestSquatKg: 100,
    ));
    await seed(const UserPublicProfile(
      uid: 'high',
      gymId: gymA,
      rankingOptIn: true,
      bestSquatKg: 140,
    ));

    final container = buildContainer();
    final result = await container.read(squatLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['high', 'low']));
  });

  test(
      'SCENARIO-RANK-6f: benchLeaderboardProvider orders desc by '
      'bestBenchKg', () async {
    await seed(const UserPublicProfile(
      uid: 'low',
      gymId: gymA,
      rankingOptIn: true,
      bestBenchKg: 60,
    ));
    await seed(const UserPublicProfile(
      uid: 'high',
      gymId: gymA,
      rankingOptIn: true,
      bestBenchKg: 90,
    ));

    final container = buildContainer();
    final result = await container.read(benchLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['high', 'low']));
  });

  test(
      'SCENARIO-RANK-6g: deadliftLeaderboardProvider orders desc by '
      'bestDeadliftKg', () async {
    await seed(const UserPublicProfile(
      uid: 'low',
      gymId: gymA,
      rankingOptIn: true,
      bestDeadliftKg: 120,
    ));
    await seed(const UserPublicProfile(
      uid: 'high',
      gymId: gymA,
      rankingOptIn: true,
      bestDeadliftKg: 180,
    ));

    final container = buildContainer();
    final result =
        await container.read(deadliftLeaderboardProvider(gymA).future);

    expect(result.map((p) => p.uid).toList(), equals(['high', 'low']));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6h: empty gym returns empty list, not an error
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6h: leaderboard providers return an empty list for a '
      'gym with zero opted-in athletes (no error)', () async {
    await seed(const UserPublicProfile(
      uid: 'other-gym-athlete',
      gymId: gymB,
      rankingOptIn: true,
      racha: 10,
    ));

    final container = buildContainer();
    final streak = await container.read(streakLeaderboardProvider(gymA).future);
    final volume = await container.read(volumeLeaderboardProvider(gymA).future);
    final squat = await container.read(squatLeaderboardProvider(gymA).future);

    expect(streak, isEmpty);
    expect(volume, isEmpty);
    expect(squat, isEmpty);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-6i: empty gymId short-circuits without a Firestore call
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-RANK-6i: leaderboard providers return empty list immediately '
      'for a blank gymId (no-gym athlete viewing)', () async {
    final container = buildContainer();
    final result = await container.read(streakLeaderboardProvider('').future);
    expect(result, isEmpty);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // RankingDimension enum sanity — used by the UI to drive the metric field
  // ──────────────────────────────────────────────────────────────────────────
  test('RankingDimension has 5 values: streak, volume, squat, bench, deadlift',
      () {
    expect(
      RankingDimension.values,
      containsAll(<RankingDimension>[
        RankingDimension.streak,
        RankingDimension.volume,
        RankingDimension.squat,
        RankingDimension.bench,
        RankingDimension.deadlift,
      ]),
    );
  });
}
