import 'dart:math' as math;

import 'routine.dart';
import 'routine_day.dart';

/// Result of [estimateRoutineDayMinutes]. `null` minutes means nothing
/// measurable on the day (callers render a placeholder). [authored] is true
/// when the value came from `day.estimatedMinutes` (trainer/athlete set it
/// explicitly) and false when computed from the slots — callers typically
/// prefix computed values with "~" to read as an estimate.
typedef RoutineDayDuration = ({int? minutes, bool authored});

/// Seconds per rep when estimating the work time of a rep-based set.
const int kSecondsPerRep = 4;

/// Minimum work time of any set, in seconds. Includes getting set up (load,
/// position, unrack) so a 2-rep set is not estimated at 8 s (#1562).
const int kMinSetWorkSeconds = 25;

/// Rest between sets, in seconds, when the slot carries none (`restSeconds`
/// 0). The domain has no compound/isolation signal on a slot, so this is flat.
const int kDefaultRestSeconds = 75;

/// Extra seconds between two exercises (walk, change load/machine). Counted
/// between exercises only, never after the last one.
const int kExerciseTransitionSeconds = 75;

/// Estimated total minutes to complete [day] in the given 0-based [week].
///
/// Priority:
///   1. Authored `day.estimatedMinutes` when present → returns it with
///      `authored: true`.
///   2. Otherwise, per slot present in the week with at least one set:
///      - work per set: the set's `durationSeconds` when positive, else
///        `max(reps × [kSecondsPerRep], [kMinSetWorkSeconds])` using
///        `reps ?? repsMax ?? repsMin ?? 12`;
///      - rest: `slot.restSeconds` (or [kDefaultRestSeconds] when 0) between
///        sets — NOT after the last set of the exercise;
///      - [kExerciseTransitionSeconds] between consecutive exercises — NOT
///        after the last one.
///      Rounded to the nearest minute → `authored: false`.
///   3. Returns `minutes: null` when nothing measurable is on the day.
///
/// Pure function — no Flutter imports, no providers, safe to use from both
/// presentation widgets and Riverpod providers.
RoutineDayDuration estimateRoutineDayMinutes(RoutineDay day, {int week = 0}) {
  if (day.estimatedMinutes != null) {
    return (minutes: day.estimatedMinutes, authored: true);
  }

  var seconds = 0;
  var exercises = 0;
  for (final slot in day.slots) {
    if (!slot.isPresentInWeek(week)) continue;
    final sets = slot.effectiveSetsForWeek(week);
    if (sets.isEmpty) continue;
    exercises++;
    final rest = slot.restSeconds > 0 ? slot.restSeconds : kDefaultRestSeconds;
    for (final s in sets) {
      seconds += (s.durationSeconds != null && s.durationSeconds! > 0)
          ? s.durationSeconds!
          : math.max(
              (s.reps ?? s.repsMax ?? s.repsMin ?? 12) * kSecondsPerRep,
              kMinSetWorkSeconds,
            );
    }
    seconds += rest * (sets.length - 1);
  }
  if (exercises == 0) return (minutes: null, authored: false);
  seconds += kExerciseTransitionSeconds * (exercises - 1);
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
