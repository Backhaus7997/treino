/// The 5 leaderboard dimensions surfaced on the per-gym Rankings screen:
/// streak (racha), lifetime training volume, and the 3 main-lift PRs
/// (squat/bench/deadlift, see `main_lift_family_map.dart`).
///
/// Drives both the Firestore `orderBy` field
/// (`UserPublicProfileRepository.leaderboard`) and the UI section/tab it
/// renders under. See design `sdd/rankings/design` — Data Flow.
enum RankingDimension { streak, volume, squat, bench, deadlift }

/// Maps a [RankingDimension] to the `UserPublicProfile` field it orders by.
/// Single source of truth shared by the repository query and the composite
/// index definitions in `firestore.indexes.json`.
extension RankingDimensionMetricField on RankingDimension {
  String get metricField {
    switch (this) {
      case RankingDimension.streak:
        return 'racha';
      case RankingDimension.volume:
        return 'lifetimeVolumeKg';
      case RankingDimension.squat:
        return 'bestSquatKg';
      case RankingDimension.bench:
        return 'bestBenchKg';
      case RankingDimension.deadlift:
        return 'bestDeadliftKg';
    }
  }
}
