import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise_progression.freezed.dart';

/// A single time-series data point for progression charts.
/// [date] is set from [Session.startedAt] — rendered as-is, no toLocal().
/// [value] is the metric value (kg for PR, kg·reps for Volumen).
@freezed
class ProgressionPoint with _$ProgressionPoint {
  const factory ProgressionPoint({
    required DateTime date,
    required double value,
  }) = _ProgressionPoint;
}

/// Aggregated progression data for a specific exercise.
/// Both series are ordered ascending by [ProgressionPoint.date].
/// [frequencyLast8Weeks] is the session count within the last 56 days.
@freezed
class ExerciseProgression with _$ExerciseProgression {
  const factory ExerciseProgression({
    required String exerciseId,
    required String exerciseName,
    required List<ProgressionPoint> prSeries,
    required List<ProgressionPoint> volumeSeries,
    required int frequencyLast8Weeks,
  }) = _ExerciseProgression;

  factory ExerciseProgression.empty({
    required String exerciseId,
    required String exerciseName,
  }) =>
      ExerciseProgression(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        prSeries: const [],
        volumeSeries: const [],
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
  }) = _ExerciseListEntry;
}
