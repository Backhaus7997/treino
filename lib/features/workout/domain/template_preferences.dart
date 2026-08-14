import 'package:freezed_annotation/freezed_annotation.dart';

import 'muscle_group.dart';
import 'routine_goal.dart';

part 'template_preferences.freezed.dart';
part 'template_preferences.g.dart';

/// What the athlete told the PLANTILLAS mini-onboarding (#635 PR#2): how much
/// they can train, what for, and which zones they want prioritised.
///
/// Persisted under `users/{uid}.templatePreferences`. PRIVATE data: it never
/// reaches `userPublicProfiles`, which carries its own explicit key allowlist
/// in firestore.rules — adding a field here cannot leak into it by accident.
/// `users/{uid}` has no `hasOnly` guard on update (firestore.rules:65-80), so
/// this field needs no rules change; only the routine paths have that coupling.
///
/// ── Every field is nullable / empty-able on purpose ─────────────────────────
/// The flow is skippable at every step, and the issue is explicit that a
/// missing answer must read as NEUTRAL, never as an exclusion. A user who
/// skipped step 2 has no opinion about session length — that is not the same as
/// wanting 0 minutes, and the ranking (PR#3) must not treat it as one.
@freezed
class TemplatePreferences with _$TemplatePreferences {
  const factory TemplatePreferences({
    /// 2..6. Null ⇒ not answered.
    int? daysPerWeek,

    /// 30 / 45 / 60 / 75, where 75 means "75 or more" — the handoff's last
    /// option is "75 MIN O MÁS". Stored as the lower bound so a future finer
    /// scale stays comparable. Null ⇒ not answered.
    int? minutesPerSession,

    /// Single-valued for the ATHLETE. The routine side is multi-valued
    /// (`Routine.goals`, #635 PR#1) because one template genuinely serves
    /// several goals; a person picking "what am I training for" right now does
    /// not need that. Null ⇒ not answered.
    ///
    /// `nullForUndefinedEnumValue` is not decoration. Without it the generated
    /// `$enumDecodeNullable` THROWS on any key it does not know, and this model
    /// is decoded as part of `UserProfile` — so one goal value added by a newer
    /// build would break the whole profile stream on every older client and
    /// route them to `/profile-unavailable` (#544). An unknown goal has to
    /// degrade to "no preference", exactly like [RoutineGoal.fromWireKey] and
    /// [priorityGroups] already do for their own unknown keys.
    // ignore: invalid_annotation_target
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    RoutineGoal? goal,

    /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
    /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
    /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
    /// opcional").
    @Default(<String>[]) List<String> priorityMuscleGroups,
  }) = _TemplatePreferences;

  const TemplatePreferences._();

  factory TemplatePreferences.fromJson(Map<String, Object?> json) =>
      _$TemplatePreferencesFromJson(json);

  /// True when the athlete answered nothing at all.
  ///
  /// Used to decide whether there is anything worth writing: SALTAR on step 1
  /// should not put an all-null map on the user's document just to prove the
  /// flow ran. The "did they see it" signal is `onboardingSeen`, not this.
  bool get isEmpty =>
      daysPerWeek == null &&
      minutesPerSession == null &&
      goal == null &&
      priorityMuscleGroups.isEmpty;

  /// The priority zones resolved to their canonical groups, dropping anything
  /// unknown.
  ///
  /// Unknown keys are skipped rather than surfaced: a value written by a newer
  /// build must degrade to "one less priority", never to a crash or an empty
  /// grid.
  List<MuscleGroup> get priorityGroups => priorityMuscleGroups
      .map(MuscleGroup.fromKey)
      .whereType<MuscleGroup>()
      .toList(growable: false);
}
