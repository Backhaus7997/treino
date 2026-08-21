import 'routine.dart';
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

/// Estimated minutes of ONE session of [routine] — what a card shows to answer
/// "how long is this going to take me today?" (#639).
///
/// Priority:
///   1. Authored `routine.estimatedMinutesPerDay` → `authored: true`.
///   2. Otherwise the AVERAGE of [estimateRoutineDayMinutes] over the days
///      that yield a value. `authored` stays true only when every counted day
///      was itself authored — one computed day makes the whole figure an
///      estimate, and the UI must say so.
///   3. `minutes: null` when no day yields anything measurable. Callers render
///      NOTHING in that case — never "0 min" or a dash. Trainer- and
///      community-published routines are not guaranteed to carry duration
///      data, and inventing one for them is worse than staying quiet.
///
/// DECISION — average, not a range. Days of a routine can differ (an
/// Upper/Lower with a 50' day and an 80' day), so a range would be more
/// faithful for those. Average wins here because this feeds a two-line
/// metadata caption on a grid card where a range costs a line, and because the
/// question the card answers is "roughly how long", not "exactly which day".
/// The detail screen already shows the exact per-day figure. Revisit if
/// routines with wide day dispersion turn out to be common.
///
/// Pure function — same contract as [estimateRoutineDayMinutes]: no Flutter
/// imports, no providers.
RoutineDayDuration estimateRoutineSessionMinutes(
  Routine routine, {
  int week = 0,
}) {
  final authored = routine.estimatedMinutesPerDay;
  if (authored != null && authored > 0) {
    return (minutes: authored, authored: true);
  }

  var total = 0;
  var counted = 0;
  var everyDayAuthored = true;
  for (final day in routine.days) {
    final est = estimateRoutineDayMinutes(day, week: week);
    final minutes = est.minutes;
    if (minutes == null) continue;
    total += minutes;
    counted++;
    if (!est.authored) everyDayAuthored = false;
  }
  if (counted == 0) return (minutes: null, authored: false);
  return (minutes: (total / counted).round(), authored: everyDayAuthored);
}
