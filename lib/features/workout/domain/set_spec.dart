import 'package:freezed_annotation/freezed_annotation.dart';

import 'set_enums.dart';

part 'set_spec.freezed.dart';
part 'set_spec.g.dart';

/// A single set row in the per-set model.
///
/// The active fields depend on the exercise's [ExerciseMode] and [RepMode]:
/// - Reps + single: [weightKg] + [reps]
/// - Reps + range:  [weightKg] + [repsMin] + [repsMax]
/// - Duration:      [durationSeconds]
@freezed
class SetSpec with _$SetSpec {
  const factory SetSpec({
    /// The role of this set (warmup, working, drop, failure).
    ///
    /// Serialized as the enum name string; unknown values fall back to [SetType.normal].
    @Default(SetType.normal)
    // ignore: invalid_annotation_target
    @JsonKey(unknownEnumValue: SetType.normal)
    SetType type,

    /// Target weight in kilograms. Null means "bodyweight" or "user picks".
    double? weightKg,

    /// Target rep count — used when [RepMode.single].
    int? reps,

    /// Minimum reps — used when [RepMode.range].
    int? repsMin,

    /// Maximum reps — used when [RepMode.range].
    int? repsMax,

    /// Target duration in seconds — used when [ExerciseMode.duration].
    int? durationSeconds,
  }) = _SetSpec;

  factory SetSpec.fromJson(Map<String, Object?> json) =>
      _$SetSpecFromJson(json);
}
