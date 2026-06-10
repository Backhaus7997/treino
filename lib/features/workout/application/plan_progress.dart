// Plan progress derivation for periodized routines (Model B).
//
// All functions are pure and stateless — no Riverpod, no Flutter imports.
// Designed for both production use (inside planProgressProvider) and
// exhaustive unit testing (SCENARIO-030..036).

/// A completed (week, day) pair. week is 0-based; dayNumber is 1-based
/// (matching Session.dayNumber and RoutineDay.dayNumber).
typedef CompletedKey = ({int week, int day});

/// Derived progress snapshot for a periodized plan.
///
/// - [activeWeek]    0-based index of the current active week.
/// - [activeDay]     1-based dayNumber of the current active day.
/// - [planComplete]  true when every (week, day) combination is done.
/// - [completed]     set of all (week, day) pairs completed at least once.
typedef PlanProgress = ({
  int activeWeek,
  int activeDay,
  bool planComplete,
  Set<CompletedKey> completed,
});

/// Derives a [PlanProgress] snapshot from finished sessions.
///
/// Parameters:
/// - [completed]   set of `(week, day)` pairs that have at least one finished,
///                 fully-completed session (pre-filtered by caller).
/// - [dayNumbers]  the 1-based dayNumbers defined in the routine's days, in
///                 their canonical order.
/// - [numWeeks]    total number of weeks in the plan (>= 1).
///
/// Algorithm (REQ-PERIOD-031, REQ-PERIOD-032):
/// - activeWeek = first week w in 0..numWeeks−1 where NOT all dayNumbers have
///   a (w, day) entry in [completed]. If none found → planComplete=true,
///   activeWeek clamped to numWeeks−1.
/// - activeDay  = within activeWeek, first dayNumber not in completed for that
///   week. Falls back to first dayNumber when all are done (plan-complete path).
PlanProgress derivePlanProgress(
  Set<CompletedKey> completed,
  List<int> dayNumbers,
  int numWeeks,
) {
  // Runtime guard: corrupt Firestore docs with numWeeks==0 (an explicit 0
  // bypasses the ?? 1 in generated fromJson) would otherwise produce an
  // infinite loop or wrong planComplete=true result. Treat as 1.
  // Guard runs BEFORE the assert so tests that exercise the corrupt-doc path
  // are not rejected by the assert in debug mode.
  // ignore: parameter_assignments
  if (numWeeks <= 0) numWeeks = 1;
  assert(numWeeks >= 1, 'numWeeks must be >= 1');

  if (dayNumbers.isEmpty) {
    return (
      activeWeek: 0,
      activeDay: 1,
      planComplete: false,
      completed: completed,
    );
  }

  for (var w = 0; w < numWeeks; w++) {
    // Find the first dayNumber in this week that is NOT yet completed.
    for (final day in dayNumbers) {
      if (!completed.contains((week: w, day: day))) {
        return (
          activeWeek: w,
          activeDay: day,
          planComplete: false,
          completed: completed,
        );
      }
    }
    // All days of week w are done → continue to next week.
  }

  // All weeks and days are done.
  return (
    activeWeek: numWeeks - 1,
    activeDay: dayNumbers.first,
    planComplete: true,
    completed: completed,
  );
}
