import '../../../core/utils/argentina_time.dart';
import '../../workout/domain/session.dart';

/// [AD6] Pure function — returns the set of unique local calendar dates
/// within [month] on which [sessions] recorded at least one
/// [SessionStatus.finished] session, backing [WorkoutDaysCalendar]'s
/// trained-day marks.
///
/// Same day-bucketing convention as `computeStreak`
/// (`lib/core/utils/streak_calculator.dart`): dedup by local calendar date
/// (year/month/day, time-of-day truncated), only `finished` sessions count.
/// This function does NOT reuse `computeStreak` itself (that function
/// answers a different question — "how many consecutive days ending today",
/// not "which days in this specific month were trained") — the streak value
/// itself is computed by calling `computeStreak` directly, unchanged.
///
/// [month] may be any [DateTime] within the target calendar month — only
/// its `year`/`month` fields are used.
Set<DateTime> trainedDaysInMonth(List<Session> sessions, DateTime month) {
  final result = <DateTime>{};

  for (final session in sessions) {
    if (!session.countsAsWorkout) continue;
    final started = toArgentina(session.startedAt);
    if (started.year != month.year || started.month != month.month) continue;
    result.add(DateTime(started.year, started.month, started.day));
  }

  return result;
}
