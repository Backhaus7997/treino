import 'package:freezed_annotation/freezed_annotation.dart';

import '../../insights/domain/chart_period.dart';

part 'exercise_progression.freezed.dart';

/// A single time-series data point for progression charts.
/// [date] is set from [Session.startedAt] — rendered as-is, no toLocal().
/// [value] is the metric value (kg for Heaviest Weight / 1RM,
/// kg·reps for Best Set Volume / Best Session Volume).
@freezed
class ProgressionPoint with _$ProgressionPoint {
  const factory ProgressionPoint({
    required DateTime date,
    required double value,
  }) = _ProgressionPoint;
}

/// [AD3] Identifies which of the 4 client-computed metrics a
/// [PersonalRecord] belongs to.
enum ProgressionRecordType {
  /// Heaviest single-set weight lifted (was mislabeled "PR").
  heaviestWeight,

  /// Epley-estimated one-rep max (AD2).
  oneRepMax,

  /// Max (reps × weightKg) of a single set within a session.
  bestSetVolume,

  /// Σ(reps × weightKg) across all sets of a session (was `volumeSeries`).
  bestSessionVolume,
}

/// [AD3] The first-achieved date + value for a given [ProgressionRecordType],
/// derived by [derivePersonalRecords] — powers the dated PR list (REQ spec#2).
@freezed
class PersonalRecord with _$PersonalRecord {
  const factory PersonalRecord({
    required ProgressionRecordType recordType,
    required double value,
    required DateTime achievedAt,
  }) = _PersonalRecord;
}

/// Aggregated progression data for a specific exercise.
///
/// [AD3] 4 distinct client-computed series (all ordered ASC by
/// [ProgressionPoint.date]):
/// - [heaviestWeightSeries]: max(weightKg) per session (renamed from the
///   mislabeled `prSeries` — UI label is now "Peso máximo", NOT "PR").
/// - [oneRepMaxSeries]: Epley-estimated 1RM per session (AD2).
/// - [bestSetVolumeSeries]: max(reps×weightKg) of a single set per session.
/// - [bestSessionVolumeSeries]: Σ(reps×weightKg) per session (renamed from
///   the old `volumeSeries` — same semantics, new name for clarity now that
///   Best Set Volume also exists).
///
/// [personalRecords] is the first-achieved-date list derived by
/// [derivePersonalRecords], one entry per record type that has data.
/// [frequencyLast8Weeks] is the session count within the last 56 days.
@freezed
class ExerciseProgression with _$ExerciseProgression {
  const factory ExerciseProgression({
    required String exerciseId,
    required String exerciseName,
    required List<ProgressionPoint> heaviestWeightSeries,
    required List<ProgressionPoint> oneRepMaxSeries,
    required List<ProgressionPoint> bestSetVolumeSeries,
    required List<ProgressionPoint> bestSessionVolumeSeries,
    required List<PersonalRecord> personalRecords,
    required int frequencyLast8Weeks,
  }) = _ExerciseProgression;

  factory ExerciseProgression.empty({
    required String exerciseId,
    required String exerciseName,
  }) =>
      ExerciseProgression(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        heaviestWeightSeries: const [],
        oneRepMaxSeries: const [],
        bestSetVolumeSeries: const [],
        bestSessionVolumeSeries: const [],
        personalRecords: const [],
        frequencyLast8Weeks: 0,
      );
}

/// A deduplicated exercise entry for the picker chip row.
/// [exerciseName] is sourced from the denormalized field on SetLog —
/// no catalogue Firestore read is performed.
@freezed
class ExerciseListEntry with _$ExerciseListEntry {
  const factory ExerciseListEntry({
    required String exerciseId,
    required String exerciseName,

    /// [#377] Periods whose CURRENT window holds at least one chartable set
    /// for this exercise — same predicate the aggregator uses to build the
    /// series (countsAsWorkout session, weightKg > 0). The section widget
    /// bounds the default preselection to the active period with this, so
    /// the screen never opens on the chart's empty state by itself.
    @Default(<ChartPeriod>{}) Set<ChartPeriod> periodsWithData,
  }) = _ExerciseListEntry;
}
