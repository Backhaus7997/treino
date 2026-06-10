// Gating pure functions for periodized routines (Model B).
//
// All functions are top-level and stateless. For numWeeks == 1 plans, the
// detail screen BYPASSES these entirely — every day is always startable
// (REQ-PERIOD-042, HARD INVARIANT, SCENARIO-038).
//
// week is 0-based; day is 1-based (matching RoutineDay.dayNumber).

import 'plan_progress.dart' show CompletedKey;

/// Returns true when [week] is accessible to the athlete.
///
/// Week 0 is always unlocked. Week w > 0 is unlocked iff ALL [dayNumbers]
/// in week w−1 are present in [completed] (REQ-PERIOD-033).
bool isWeekUnlocked(
  int week,
  Set<CompletedKey> completed,
  List<int> dayNumbers,
) {
  if (week <= 0) return true;
  final prevWeek = week - 1;
  return dayNumbers.every(
    (day) => completed.contains((week: prevWeek, day: day)),
  );
}

/// Returns true when a specific (week, day) combination is accessible.
///
/// A day is unlocked iff its week is unlocked AND all dayNumbers that appear
/// BEFORE [day] in [dayNumbers] for the same week are already in [completed]
/// (REQ-PERIOD-034).
bool isDayUnlocked(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers,
) {
  if (!isWeekUnlocked(week, completed, dayNumbers)) return false;
  // All prior days in the same week must be complete.
  for (final d in dayNumbers) {
    if (d == day) break; // reached the target day — stop
    if (!completed.contains((week: week, day: d))) return false;
  }
  return true;
}

/// Returns true when the athlete can start the given (week, day).
///
/// Startable = isDayUnlocked AND the (week, day) is NOT already fully
/// completed (REQ-PERIOD-034, REQ-PERIOD-042).
bool isStartable(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers,
) {
  if (!isDayUnlocked(week, day, completed, dayNumbers)) return false;
  return !completed.contains((week: week, day: day));
}
