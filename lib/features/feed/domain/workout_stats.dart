import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_stats.freezed.dart';
part 'workout_stats.g.dart';

/// Denormalized workout metrics attached to a share-a-workout post so the feed
/// card can render real numbers (volume / duration / exercises) instead of the
/// old hardcoded "— kg / — min / — ej." stub (QA-FEED / issues #364, #389).
///
/// Null on manually-composed posts (no workout behind them) and on legacy posts
/// that predate this field — the card hides the stats row in that case, per the
/// issue's "real stats OR no row" requirement.
@freezed
class WorkoutStats with _$WorkoutStats {
  const factory WorkoutStats({
    required double volumeKg,
    required int durationMin,
    required int exerciseCount,
  }) = _WorkoutStats;

  factory WorkoutStats.fromJson(Map<String, Object?> json) =>
      _$WorkoutStatsFromJson(json);
}
