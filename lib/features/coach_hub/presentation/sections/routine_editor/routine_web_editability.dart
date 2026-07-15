import '../../../../workout/domain/routine.dart';

/// Whether [routine] can be safely edited in the web editor.
///
/// The web editor models single-week routines — reps (single or min–max range),
/// duration, weight, rest, per-exercise notes, and supersets (Fases 1-3
/// parity). It does NOT yet capture per-week periodization
/// ([RoutineSlot.weeklySets] / [RoutineSlot.activeWeeks] / multi-week
/// [Routine.numWeeks], Fase 4).
///
/// `RoutineRepository.updateAssigned` overwrites the whole `days` array, so
/// loading a periodized routine into the editor and re-saving would SILENTLY
/// TRUNCATE it. This gate blocks that: periodized routines stay editable only
/// in the mobile app until Fase 4 lands — at which point this gate always
/// returns true and can be removed.
///
/// Routines created BY the web editor are always within scope, so they
/// round-trip through edit mode without hitting this gate.
bool isRoutineWebEditable(Routine routine) {
  if (routine.numWeeks != 1) return false;
  for (final day in routine.days) {
    for (final slot in day.slots) {
      if (slot.weeklySets.isNotEmpty) return false;
      if (slot.activeWeeks.isNotEmpty) return false;
    }
  }
  return true;
}
