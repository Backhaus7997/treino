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
/// [UserPublicProfileRepository.watchLeaderboard] — mirrors the
/// `assignedRoutinesProvider` pattern (query logic lives in the repository,
/// the provider only wires the repository + family key).
///
/// Es un STREAM y no un `Future` (#1518): las métricas de ranking las escribe
/// una Cloud Function 1-3 s después de que el atleta activa el opt-in, y con
/// una lectura puntual el board quedaba congelado con lo que había en ese
/// instante (volumen en 0) hasta salir y volver a la pantalla.
///
/// `autoDispose` bounds each gym's listener to consumer lifetime (se cancela
/// al salir de la pantalla); `family` keys the cache by `gymId` so switching
/// gyms (edge case) does not stale-serve another gym's data.
Stream<List<UserPublicProfile>> _watchBoard(
  Ref ref,
  String gymId,
  RankingDimension dimension,
) {
  return ref.watch(rankingRepositoryProvider).watchLeaderboard(
        gymId: gymId,
        metricField: dimension.metricField,
      );
}

/// Streak (racha) leaderboard for [gymId]. Spec `gym-rankings` — Streak
/// Leaderboard.
final streakLeaderboardProvider =
    StreamProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => _watchBoard(ref, gymId, RankingDimension.streak),
);

/// Lifetime training-volume leaderboard for [gymId]. Spec `gym-rankings` —
/// Volume Leaderboard.
final volumeLeaderboardProvider =
    StreamProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => _watchBoard(ref, gymId, RankingDimension.volume),
);

/// Squat PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final squatLeaderboardProvider =
    StreamProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => _watchBoard(ref, gymId, RankingDimension.squat),
);

/// Bench press PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final benchLeaderboardProvider =
    StreamProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => _watchBoard(ref, gymId, RankingDimension.bench),
);

/// Deadlift PR leaderboard for [gymId]. Spec `gym-rankings` — Main-Lift
/// Leaderboards.
final deadliftLeaderboardProvider =
    StreamProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) => _watchBoard(ref, gymId, RankingDimension.deadlift),
);
