import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;
import '../../profile/data/user_public_profile_repository.dart';
import '../../profile/domain/user_public_profile.dart';
import '../domain/ranking_dimension.dart';

/// Alias for [userPublicProfileRepositoryProvider] — the ranking feature
/// reuses the same repository (no dedicated data layer needed, per design
/// `sdd/rankings/design`: rankings are plain gym-scoped queries on the
/// existing `userPublicProfiles` collection). Re-exposed under this name so
/// tests can override it without depending on the profile feature's provider
/// naming.
final rankingRepositoryProvider = userPublicProfileRepositoryProvider;

/// Returns up to 20 opted-in profiles for [gymId], ordered desc by
/// [dimension]'s metric field. Thin wrapper around
/// [UserPublicProfileRepository.leaderboard] — mirrors the
/// `assignedRoutinesProvider` pattern (query logic lives in the repository,
/// the provider only wires the repository + family key).
///
/// `autoDispose` bounds each gym's cached leaderboard to consumer lifetime;
/// `family` keys the cache by `gymId` so switching gyms (edge case) does not
/// stale-serve another gym's data.
final _leaderboardProvider = FutureProvider.autoDispose.family<
    List<UserPublicProfile>, ({String gymId, RankingDimension dimension})>(
  (ref, key) {
    return ref.watch(rankingRepositoryProvider).leaderboard(
          gymId: key.gymId,
          metricField: key.dimension.metricField,
        );
  },
);

/// Streak (racha) leaderboard for [gymId]. Spec `gym-rankings` — Streak
/// Leaderboard.
final streakLeaderboardProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => ref.watch(
    _leaderboardProvider((gymId: gymId, dimension: RankingDimension.streak))
        .future,
  ),
);

/// Lifetime training-volume leaderboard for [gymId]. Spec `gym-rankings` —
/// Volume Leaderboard.
final volumeLeaderboardProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => ref.watch(
    _leaderboardProvider((gymId: gymId, dimension: RankingDimension.volume))
        .future,
  ),
);

/// Squat PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final squatLeaderboardProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => ref.watch(
    _leaderboardProvider((gymId: gymId, dimension: RankingDimension.squat))
        .future,
  ),
);

/// Bench press PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final benchLeaderboardProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => ref.watch(
    _leaderboardProvider((gymId: gymId, dimension: RankingDimension.bench))
        .future,
  ),
);

/// Deadlift PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final deadliftLeaderboardProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => ref.watch(
    _leaderboardProvider((gymId: gymId, dimension: RankingDimension.deadlift))
        .future,
  ),
);
