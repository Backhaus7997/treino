import 'package:freezed_annotation/freezed_annotation.dart';

import 'set_enums.dart';
import 'set_spec.dart';

part 'routine_slot.freezed.dart';
part 'routine_slot.g.dart';

/// Firestore cannot store nested arrays (an array element must not be
/// another array), so `List<List<SetSpec>>` is unpersistable as-is. On the
/// wire each week is wrapped in a map: `[{'sets': [...]}, {'sets': [...]}]`.
/// The domain type stays `List<List<SetSpec>>` — only the JSON shape changes.
class WeeklySetsConverter
    implements JsonConverter<List<List<SetSpec>>, List<dynamic>> {
  const WeeklySetsConverter();

  @override
  List<List<SetSpec>> fromJson(List<dynamic> json) => json
      .map((week) => ((week as Map)['sets'] as List<dynamic>? ?? const [])
          .map((s) => SetSpec.fromJson(Map<String, Object?>.from(s as Map)))
          .toList())
      .toList();

  @override
  List<dynamic> toJson(List<List<SetSpec>> weeks) => weeks
      .map((week) => {'sets': week.map((s) => s.toJson()).toList()})
      .toList();
}

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

    /// Periodization (Model B): per-week explicit set rows.
    /// `weeklySets[w]` holds the prescription for 0-based week `w`.
    /// Empty OUTER list = legacy / single-week slot → resolve via
    /// [effectiveSets]. An in-range EMPTY inner list is an authored-empty
    /// week (e.g. deload/rest) and is returned as-is — no fallback.
    /// Wire format via [WeeklySetsConverter] — Firestore rejects nested
    /// arrays, so weeks are map-wrapped on the wire.
    @Default(<List<SetSpec>>[])
    @WeeklySetsConverter()
    List<List<SetSpec>> weeklySets,
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

  /// The per-set rows for a specific 0-based [week] of a periodized plan.
  ///
  /// Precedence: when [weeklySets] is populated AND [week] is in range, that
  /// week's rows win — INCLUDING an authored-empty week (`[]`, e.g. a
  /// deload/rest week), which is returned as-is with no fallback. Only an
  /// empty OUTER [weeklySets] or an out-of-range/negative [week] falls back
  /// to [effectiveSets] (single-week / legacy behavior). Never throws.
  List<SetSpec> effectiveSetsForWeek(int week) {
    if (weeklySets.isNotEmpty && week >= 0 && week < weeklySets.length) {
      return weeklySets[week];
    }
    return effectiveSets;
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
