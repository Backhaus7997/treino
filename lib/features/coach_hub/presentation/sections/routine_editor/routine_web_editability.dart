import '../../../../workout/domain/routine.dart';
import '../../../../workout/domain/set_enums.dart';

/// Whether [routine] can be safely edited in the web editor.
///
/// The web editor models single-week, reps-based sets — reps OR a min–max
/// range, weight, rest, plus per-exercise coaching notes (Fase 1 parity). It
/// does NOT yet capture: duration-based exercises (Fase 2), supersets
/// ([RoutineSlot.supersetGroup], Fase 3), or per-week periodization
/// ([RoutineSlot.weeklySets] / [RoutineSlot.activeWeeks] / multi-week
/// [Routine.numWeeks], Fase 4).
///
/// `RoutineRepository.updateAssigned` overwrites the whole `days` array, so
/// loading a routine that uses one of those unsupported features into the
/// editor and re-saving would SILENTLY TRUNCATE it. This gate blocks that:
/// such routines stay editable only in the mobile app until web reaches full
/// parity — at which point this gate always returns true and can be removed.
///
/// Routines created BY the web editor are always within scope, so they
/// round-trip through edit mode without hitting this gate.
bool isRoutineWebEditable(Routine routine) {
  if (routine.numWeeks != 1) return false;
  for (final day in routine.days) {
    for (final slot in day.slots) {
      if (slot.supersetGroup != null) return false;
      if (slot.weeklySets.isNotEmpty) return false;
      if (slot.activeWeeks.isNotEmpty) return false;
      // Duration is still out of scope (Fase 2). Reps — single or range — and
      // notes ARE supported, so they no longer block. Raw `exerciseMode` plus
      // the per-set `durationSeconds` check below catch both explicit and
      // legacy (synthesized) duration slots.
      if (slot.exerciseMode != ExerciseMode.reps) return false;
      for (final set in slot.effectiveSets) {
        if (set.durationSeconds != null && set.durationSeconds! > 0) {
          return false;
        }
      }
    }
  }
  return true;
}
