import '../../../../workout/domain/routine.dart';

/// Whether [routine] can be safely edited in the web editor.
///
/// The web editor models single-week exercises — reps (single or min–max
/// range), duration (timed), weight, rest, plus per-exercise coaching notes
/// (Fases 1-2 parity). It does NOT yet capture: supersets
/// ([RoutineSlot.supersetGroup], Fase 3) or per-week periodization
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
    }
  }
  return true;
}
