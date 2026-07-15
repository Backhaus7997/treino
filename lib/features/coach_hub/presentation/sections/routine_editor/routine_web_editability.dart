import '../../../../workout/domain/routine.dart';

/// Whether [routine] can be safely edited in the web editor.
///
/// The web editor models reps (single or min–max range), duration, weight,
/// rest, per-exercise notes, supersets, and a multi-week count where every
/// week can carry its OWN prescription ([RoutineSlot.weeklySets], Fase 4b —
/// edited via the "Sem 1..N" switcher). It does NOT yet capture the presence
/// mask that hides an exercise in some weeks ([RoutineSlot.activeWeeks],
/// Fase 4c).
///
/// `RoutineRepository.updateAssigned` overwrites the whole `days` array, so
/// loading a routine that uses [RoutineSlot.activeWeeks] into the editor and
/// re-saving would SILENTLY TRUNCATE it. This gate blocks that: such routines
/// stay editable only in the mobile app until Fase 4c lands — at which point
/// this gate always returns true and can be removed.
///
/// Routines created BY the web editor are always within scope (their
/// activeWeeks stays empty), so they round-trip through edit mode.
bool isRoutineWebEditable(Routine routine) {
  for (final day in routine.days) {
    for (final slot in day.slots) {
      if (slot.activeWeeks.isNotEmpty) return false;
    }
  }
  return true;
}
