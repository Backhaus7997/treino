import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise_frequency.freezed.dart';

/// [PR4] One ranked entry in the most-frequent-exercises list (Hevy's "Main
/// exercises"): an exercise ranked by the number of DISTINCT sessions that
/// contain at least one set of it, within a [ChartPeriod] window.
///
/// [exerciseName] is sourced from the denormalized field on `SetLog` — no
/// exercise-catalogue Firestore read is performed (same convention as
/// [ExerciseListEntry]).
@freezed
class ExerciseFrequencyEntry with _$ExerciseFrequencyEntry {
  const factory ExerciseFrequencyEntry({
    required String exerciseId,
    required String exerciseName,
    required int sessionCount,
  }) = _ExerciseFrequencyEntry;
}
