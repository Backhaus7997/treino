import 'package:json_annotation/json_annotation.dart';

/// Why someone trains — the vocabulary shared by the athlete's stated goal and
/// (once #635 PR#1 lands) the `goals` a routine declares it serves.
///
/// Deliberately named `RoutineGoal` and not `TrainingGoal`: issue #635 names the
/// future `Routine.goals` field with this exact type, and the scoring in PR#3
/// compares the athlete's answer against the routine's list. Two enums —
/// one for the preference and one for the routine — would be the same
/// parallel-vocabulary mistake the issue calls out for `MuscleGroup`. One
/// vocabulary, both sides.
///
/// [wireKey] is what Firestore stores. English, snake_case, matching the
/// convention `MuscleGroup.key` already set for the stock catalogue, so a future
/// backfill of the 7 system templates writes the same strings the client reads.
///
/// UI labels are NOT here. `MuscleGroup` carries Spanish labels in the enum, but
/// that predates l10n; new copy goes to `lib/l10n` so ES and EN stay in one
/// place. The presentation layer resolves a label per value.
enum RoutineGoal {
  // `@JsonValue` is what json_serializable reads; `wireKey` is for the call
  // sites that need the raw string. They are const literals on the same line
  // pair on purpose — the two cannot drift without it being visible here.
  @JsonValue('health')
  health('health'),
  @JsonValue('injury_prevention')
  injuryPrevention('injury_prevention'),
  @JsonValue('aesthetics')
  aesthetics('aesthetics'),
  @JsonValue('sport')
  sport('sport'),
  @JsonValue('wellbeing')
  wellbeing('wellbeing');

  const RoutineGoal(this.wireKey);

  /// Canonical key persisted in Firestore. Renaming one IS a wire-format
  /// change: existing `users/{uid}.templatePreferences.goal` values would stop
  /// resolving and silently read as "no preference".
  final String wireKey;

  /// Display order for the picker — matches the handoff
  /// ("Onboarding Plantillas.dc.html", PASO 3 DE 4).
  static const List<RoutineGoal> displayOrder = RoutineGoal.values;

  /// Resolves a stored key back to its value, or `null` if unknown.
  ///
  /// Returns `null` rather than throwing so a value written by a newer build
  /// degrades to "no preference" instead of crashing the grid — the same
  /// neutral-not-excluded rule the issue sets for templates without metadata.
  static RoutineGoal? fromWireKey(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final goal in RoutineGoal.values) {
      if (goal.wireKey == v) return goal;
    }
    return null;
  }
}
