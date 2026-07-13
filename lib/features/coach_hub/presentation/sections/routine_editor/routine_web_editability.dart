import '../../../../workout/domain/routine.dart';
import '../../../../workout/domain/set_enums.dart';

/// Whether [routine] can be safely edited in the web MVP editor.
///
/// The web editor only models **single-week, reps-based, normal sets** (reps +
/// weight + rest). It does NOT capture the advanced fields a mobile-authored
/// routine may carry: per-week periodization ([RoutineSlot.weeklySets]), the
/// presence mask ([RoutineSlot.activeWeeks]), supersets
/// ([RoutineSlot.supersetGroup]), duration-based exercises
/// ([RoutineSlot.effectiveExerciseMode]), rep ranges
/// ([RoutineSlot.effectiveRepMode]), free-form coaching [RoutineSlot.notes], or
/// a multi-week [Routine.numWeeks].
///
/// `RoutineRepository.updateAssigned` overwrites the whole `days` array, so
/// loading such a routine into the simple editor and re-saving would SILENTLY
/// TRUNCATE all of that data (⚠️ the exact footgun the create-only MVP avoided
/// — see the editor's own header doc). This gate blocks that: advanced routines
/// stay editable only in the mobile app; the web surface refuses rather than
/// destroys.
///
/// Routines created BY the web editor are always simple, so they round-trip
/// through edit mode without hitting this gate.
bool isRoutineWebEditable(Routine routine) {
  if (routine.numWeeks != 1) return false;
  for (final day in routine.days) {
    for (final slot in day.slots) {
      if (slot.supersetGroup != null) return false;
      if (slot.weeklySets.isNotEmpty) return false;
      if (slot.activeWeeks.isNotEmpty) return false;
      // RAW mode fields — NOT the effective* getters. Those getters infer
      // "range" from `targetRepsMin != targetRepsMax`, which wrongly flags a
      // perfectly simple web routine that merely has DIFFERENT reps per set
      // (12/10/8) — the editor stores per-set reps, so that's fine. Only an
      // explicitly authored range/duration mode is out of scope.
      if (slot.exerciseMode != ExerciseMode.reps) return false;
      if (slot.repMode != RepMode.single) return false;
      final notes = slot.notes;
      if (notes != null && notes.trim().isNotEmpty) return false;
      // Set-level guard: a rep RANGE (repsMin/repsMax) or DURATION set can't be
      // represented by the editor's single-reps + weight fields. Iterating
      // effectiveSets also catches LEGACY routines whose ranges/durations are
      // synthesized from the old target* fields (they have no explicit `sets`).
      for (final set in slot.effectiveSets) {
        if (set.repsMin != null || set.repsMax != null) return false;
        if (set.durationSeconds != null && set.durationSeconds! > 0) {
          return false;
        }
      }
    }
  }
  return true;
}
