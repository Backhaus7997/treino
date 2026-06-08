import 'package:freezed_annotation/freezed_annotation.dart';

import 'set_enums.dart';
import 'set_spec.dart';

part 'routine_slot.freezed.dart';
part 'routine_slot.g.dart';

@freezed
class RoutineSlot with _$RoutineSlot {
  // Private constructor required for custom getters in freezed classes.
  const RoutineSlot._();

  const factory RoutineSlot({
    required String exerciseId, // FK → exercises/{id} (canonical reference)
    required String
        exerciseName, // denormalized for compact card display (ADR-2)
    required String muscleGroup, // denormalized for compact card display
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required int restSeconds,
    double?
        targetWeightKg, // null means "user picks" or "no target" (plate math)
    String? notes, // nullable free-form coaching notes
    int? supersetGroup, // non-null → slot belongs to a superset block
    // ── Existing additive fields (kept for backward compat) ──────────────────
    // Per-set reps: [] = none/legacy; [10] = uniform; [6,8,10] = per-set.
    @Default(<int>[]) List<int> targetReps,
    // null / 0 = reps-based; > 0 = time-based (seconds per set).
    int? durationSeconds,
    // ── Phase-1 additions: Hevy per-set-row model ────────────────────────────
    /// Whether each set is reps-based or duration-based.
    /// Unknown values on read fall back to [ExerciseMode.reps].
    @Default(ExerciseMode.reps)
    // ignore: invalid_annotation_target
    @JsonKey(unknownEnumValue: ExerciseMode.reps)
    ExerciseMode exerciseMode,

    /// Whether the rep target is a single count or a min–max range.
    /// Unknown values on read fall back to [RepMode.single].
    @Default(RepMode.single)
    // ignore: invalid_annotation_target
    @JsonKey(unknownEnumValue: RepMode.single)
    RepMode repMode,

    /// The explicit per-set rows for this slot.
    /// Empty list = use legacy fields and synthesize via [effectiveSets].
    @Default(<SetSpec>[]) List<SetSpec> sets,
  }) = _RoutineSlot;

  factory RoutineSlot.fromJson(Map<String, Object?> json) =>
      _$RoutineSlotFromJson(json);

  // ── Derived getters ────────────────────────────────────────────────────────

  /// The per-set rows to render and execute.
  ///
  /// If [sets] is populated (new model) it is returned as-is.
  /// Otherwise synthesizes rows from the legacy fields so pre-existing
  /// routines continue to work unchanged.
  List<SetSpec> get effectiveSets {
    // New model: explicit rows win.
    if (sets.isNotEmpty) return sets;

    // Guard: always produce at least 1 set from legacy data.
    final n = targetSets.clamp(1, 999);

    // Duration-based legacy (durationSeconds > 0).
    if (durationSeconds != null && durationSeconds! > 0) {
      return List.generate(
        n,
        (_) => SetSpec(
          type: SetType.normal,
          durationSeconds: durationSeconds,
        ),
      );
    }

    // Per-set reps legacy ([6, 8, 10] or [10]).
    if (targetReps.isNotEmpty) {
      if (targetReps.length == 1) {
        // Single uniform value → repeat for targetSets rows.
        return List.generate(
          n,
          (_) => SetSpec(reps: targetReps.first),
        );
      } else {
        // Explicit per-set sequence — one row per entry.
        return targetReps.map((r) => SetSpec(reps: r)).toList(growable: false);
      }
    }

    // Fallback: synthesize from targetRepsMin/Max + targetWeightKg.
    return List.generate(
      n,
      (_) => SetSpec(
        repsMin: targetRepsMin,
        repsMax: targetRepsMax,
        weightKg: targetWeightKg,
      ),
    );
  }

  /// Derives the exercise mode from the new field, falling back to legacy
  /// signals (durationSeconds > 0 → [ExerciseMode.duration]).
  ExerciseMode get effectiveExerciseMode {
    if (exerciseMode != ExerciseMode.reps) return exerciseMode;
    if (durationSeconds != null && durationSeconds! > 0) {
      return ExerciseMode.duration;
    }
    return ExerciseMode.reps;
  }

  /// Derives the rep mode from the new field, falling back to legacy signals
  /// (targetRepsMin != targetRepsMax → [RepMode.range]).
  RepMode get effectiveRepMode {
    if (repMode != RepMode.single) return repMode;
    if (targetRepsMin != targetRepsMax) return RepMode.range;
    return RepMode.single;
  }
}
