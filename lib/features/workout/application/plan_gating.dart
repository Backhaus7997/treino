// Gating pure functions for periodized routines (Model B).
//
// All functions are top-level and stateless. For numWeeks == 1 plans, the
// detail screen BYPASSES these entirely — every day is always startable
// (REQ-PERIOD-042, HARD INVARIANT, SCENARIO-038).
//
// week is 0-based; day is 1-based (matching RoutineDay.dayNumber).
//
// Phase 3 addition (REQ-WPRES-022): optional [requiredPairs] parameter lets
// callers mark days with zero present slots as auto-satisfied. A day NOT in
// [requiredPairs] is treated as already done (invisible to unlock logic).
// When [requiredPairs] is null, every pair is required — identical to the
// original behavior, ensuring full back-compat for single-week / legacy plans.

import 'plan_progress.dart' show CompletedKey;

/// A (week, day) is "satisfied" iff it is in [completed] or it is NOT in
/// [requiredPairs] (auto-satisfied absent day). When [requiredPairs] is null
/// every pair is required.
bool _isSatisfied(
  int week,
  int day,
  Set<CompletedKey> completed,
  Set<CompletedKey>? requiredPairs,
) {
  if (completed.contains((week: week, day: day))) return true;
  if (requiredPairs != null &&
      !requiredPairs.contains((week: week, day: day))) {
    return true; // absent day → auto-satisfied
  }
  return false;
}

/// Returns true when [week] is accessible to the athlete.
///
/// Week 0 is always unlocked. Week w > 0 is unlocked iff ALL [dayNumbers]
/// in week w−1 are satisfied (REQ-PERIOD-033).
///
/// [requiredPairs] — optional per-week required-day grid (REQ-WPRES-022).
bool isWeekUnlocked(
  int week,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) {
  if (week <= 0) return true;
  final prevWeek = week - 1;
  return dayNumbers.every(
    (day) => _isSatisfied(prevWeek, day, completed, requiredPairs),
  );
}

/// Returns true when a specific (week, day) combination is accessible.
///
/// A day is unlocked iff its week is unlocked AND all dayNumbers that appear
/// BEFORE [day] in [dayNumbers] for the same week are already satisfied
/// (REQ-PERIOD-034).
///
/// [requiredPairs] — optional per-week required-day grid (REQ-WPRES-022).
bool isDayUnlocked(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) {
  if (!isWeekUnlocked(week, completed, dayNumbers,
      requiredPairs: requiredPairs)) {
    return false;
  }
  // All prior days in the same week must be satisfied.
  for (final d in dayNumbers) {
    if (d == day) break; // reached the target day — stop
    if (!_isSatisfied(week, d, completed, requiredPairs)) return false;
  }
  return true;
}

/// Returns true when the athlete can start the given (week, day).
///
/// Startable = isDayUnlocked AND the (week, day) is NOT already fully
/// completed (REQ-PERIOD-034, REQ-PERIOD-042).
///
/// [requiredPairs] — optional per-week required-day grid (REQ-WPRES-022).
bool isStartable(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) {
  if (!isDayUnlocked(week, day, completed, dayNumbers,
      requiredPairs: requiredPairs)) {
    return false;
  }
  return !completed.contains((week: week, day: day));
}
