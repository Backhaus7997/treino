import 'routine_day.dart';

/// Result of [estimateRoutineDayMinutes]. `null` minutes means nothing
/// measurable on the day (callers render a placeholder). [authored] is true
/// when the value came from `day.estimatedMinutes` (trainer/athlete set it
/// explicitly) and false when computed from the slots — callers typically
/// prefix computed values with "~" to read as an estimate.
typedef RoutineDayDuration = ({int? minutes, bool authored});

/// Estimated total minutes to complete [day] in the given 0-based [week].
///
/// Priority:
///   1. Authored `day.estimatedMinutes` when present → returns it with
///      `authored: true`.
///   2. Otherwise sum per slot present in the week, per set:
///      work seconds (slot's `durationSeconds` if positive, else
///      `reps × 3s` using `reps ?? repsMax ?? repsMin ?? 12`) plus the
///      slot's `restSeconds`. Round to nearest minute → `authored: false`.
///   3. Returns `minutes: null` when nothing measurable is on the day
///      (no slots / every set evaluates to zero seconds).
///
/// Pure function — no Flutter imports, no providers, safe to use from both
/// presentation widgets and Riverpod providers.
RoutineDayDuration estimateRoutineDayMinutes(RoutineDay day, {int week = 0}) {
  if (day.estimatedMinutes != null) {
    return (minutes: day.estimatedMinutes, authored: true);
  }

  var seconds = 0;
  for (final slot in day.slots) {
    if (!slot.isPresentInWeek(week)) continue;
    for (final s in slot.effectiveSetsForWeek(week)) {
      final work = (s.durationSeconds != null && s.durationSeconds! > 0)
          ? s.durationSeconds!
          : (s.reps ?? s.repsMax ?? s.repsMin ?? 12) * 3;
      seconds += work + slot.restSeconds;
    }
  }
  if (seconds <= 0) return (minutes: null, authored: false);
  return (minutes: (seconds / 60).round(), authored: false);
}
