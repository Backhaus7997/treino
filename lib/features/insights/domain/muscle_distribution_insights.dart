import 'package:flutter/foundation.dart';

import 'muscle_group.dart';
import 'radar_axis.dart';

/// [AD4] Immutable DTO with the current-vs-previous period aggregates for
/// [MuscleDistributionRadar] — the 6-axis radar chart + Workouts/Duration/
/// Volume/Sets stat cards (Hevy-style "Muscle distribution" screen).
///
/// Computed client-side over a [ChartPeriod] window (see
/// `muscleDistributionInsightsProvider`). Does NOT persist — recomputed on
/// every screen visit / period change, same convention as [WeeklyInsights].
@immutable
class MuscleDistributionInsights {
  const MuscleDistributionInsights({
    required this.currentSetsByAxis,
    required this.previousSetsByAxis,
    this.currentSetsByGroup = const {},
    this.previousSetsByGroup = const {},
    required this.currentWorkouts,
    required this.previousWorkouts,
    required this.currentDurationMin,
    required this.previousDurationMin,
    required this.currentVolumeKg,
    required this.previousVolumeKg,
    required this.currentSets,
    required this.previousSets,
  });

  /// Sets logged per [RadarAxis] during the CURRENT period window. Only
  /// axes with ≥1 set are present — same "sparse map" convention as
  /// [WeeklyInsights.setsByGroup].
  final Map<RadarAxis, int> currentSetsByAxis;

  /// Sets logged per [RadarAxis] during the PREVIOUS (comparison) period
  /// window.
  final Map<RadarAxis, int> previousSetsByAxis;

  /// Sets logged per one of the 10 display groups during the CURRENT period.
  ///
  /// This is the granular source behind [currentSetsByAxis]: the radar folds
  /// multiple groups into six axes, while report surfaces that need the real
  /// group split can reuse the same aggregation without reading SetLogs again.
  final Map<MuscleGroupDisplay, int> currentSetsByGroup;

  /// Granular set counts for the PREVIOUS comparison period.
  final Map<MuscleGroupDisplay, int> previousSetsByGroup;

  /// Finished sessions count — current period.
  final int currentWorkouts;

  /// Finished sessions count — previous period.
  final int previousWorkouts;

  /// Σ [Session.durationMin] — current period.
  final int currentDurationMin;

  /// Σ [Session.durationMin] — previous period.
  final int previousDurationMin;

  /// Σ [Session.totalVolumeKg] — current period.
  final double currentVolumeKg;

  /// Σ [Session.totalVolumeKg] — previous period.
  final double previousVolumeKg;

  /// Total sets logged (all axes/groups, not just the 6 radar axes) —
  /// current period.
  final int currentSets;

  /// Total sets logged — previous period.
  final int previousSets;

  /// True when there is no data at all in EITHER window — the empty state
  /// per spec requirement 4 ("empty state" for the radar).
  bool get isEmpty =>
      currentSetsByAxis.isEmpty &&
      previousSetsByAxis.isEmpty &&
      currentWorkouts == 0 &&
      previousWorkouts == 0;

  static const empty = MuscleDistributionInsights(
    currentSetsByAxis: {},
    previousSetsByAxis: {},
    currentSetsByGroup: {},
    previousSetsByGroup: {},
    currentWorkouts: 0,
    previousWorkouts: 0,
    currentDurationMin: 0,
    previousDurationMin: 0,
    currentVolumeKg: 0,
    previousVolumeKg: 0,
    currentSets: 0,
    previousSets: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MuscleDistributionInsights &&
          mapEquals(other.currentSetsByAxis, currentSetsByAxis) &&
          mapEquals(other.previousSetsByAxis, previousSetsByAxis) &&
          mapEquals(other.currentSetsByGroup, currentSetsByGroup) &&
          mapEquals(other.previousSetsByGroup, previousSetsByGroup) &&
          other.currentWorkouts == currentWorkouts &&
          other.previousWorkouts == previousWorkouts &&
          other.currentDurationMin == currentDurationMin &&
          other.previousDurationMin == previousDurationMin &&
          other.currentVolumeKg == currentVolumeKg &&
          other.previousVolumeKg == previousVolumeKg &&
          other.currentSets == currentSets &&
          other.previousSets == previousSets;

  @override
  int get hashCode => Object.hash(
        _stableMapHash(currentSetsByAxis),
        _stableMapHash(previousSetsByAxis),
        _stableGroupMapHash(currentSetsByGroup),
        _stableGroupMapHash(previousSetsByGroup),
        currentWorkouts,
        previousWorkouts,
        currentDurationMin,
        previousDurationMin,
        currentVolumeKg,
        previousVolumeKg,
        currentSets,
        previousSets,
      );

  /// MapEntry has identity-based hash — iterate ordered by enum.index for
  /// reproducibility between instances with the same (key, value) pairs.
  /// Same pattern as [WeeklyInsights._stableMapHash].
  static int _stableMapHash(Map<RadarAxis, int> map) {
    final flat = <int>[];
    for (final key in RadarAxis.values) {
      if (map.containsKey(key)) {
        flat.add(key.index);
        flat.add(map[key]!);
      }
    }
    return Object.hashAll(flat);
  }

  /// Group-map counterpart to [_stableMapHash]. Iterating the enum rather than
  /// the map entries keeps equal sparse maps reproducible across instances.
  static int _stableGroupMapHash(Map<MuscleGroupDisplay, int> map) {
    final flat = <int>[];
    for (final key in MuscleGroupDisplay.values) {
      if (map.containsKey(key)) {
        flat.add(key.index);
        flat.add(map[key]!);
      }
    }
    return Object.hashAll(flat);
  }
}
