import '../../workout/domain/session.dart';
import '../../workout/domain/set_log.dart';
import '../domain/day_insights.dart';
import '../domain/muscle_group.dart';

/// [REQ:heat-map-per-day] Pure function — aggregates `setsByGroup` for a
/// SINGLE calendar [day], not the whole week. This is the fix for the bug
/// where training chest Monday + legs Tuesday painted BOTH on Tuesday (the
/// old `weeklyInsightsProvider` accumulated the whole current week).
///
/// [sessions] may span multiple days (e.g. the full last-7-days scan) — this
/// function filters to the ones whose `startedAt.toLocal()` calendar day
/// equals [day] AND `status == finished`, then sums their setLogs (looked up
/// via [setLogsBySessionId]) into display-group buckets.
///
/// [muscleGroupByExerciseId] resolves each setLog's `exerciseId` to a raw
/// muscleGroup string (same fallback chain `weeklyInsightsProvider` uses:
/// catalog first, then routine slot denormalization — the caller is
/// responsible for building this combined map). Unknown/legacy strings are
/// skipped silently (cutoff 2B convention, same as `weeklyInsightsProvider`).
DayInsights aggregateDayInsights({
  required DateTime day,
  required List<Session> sessions,
  required Map<String, List<SetLog>> setLogsBySessionId,
  required Map<String, String> muscleGroupByExerciseId,
}) {
  final dayOnly = DateTime(day.year, day.month, day.day);

  final daySessions = sessions.where((s) {
    if (!s.countsAsWorkout) return false;
    final started = s.startedAt.toLocal();
    return started.year == dayOnly.year &&
        started.month == dayOnly.month &&
        started.day == dayOnly.day;
  }).toList();

  final setsByGroup = <MuscleGroupDisplay, int>{};
  for (final session in daySessions) {
    final logs = setLogsBySessionId[session.id] ?? const <SetLog>[];
    for (final log in logs) {
      final groupRaw = muscleGroupByExerciseId[log.exerciseId];
      final group = groupRaw?.toDisplayGroup();
      if (group != null) {
        setsByGroup[group] = (setsByGroup[group] ?? 0) + 1;
      }
    }
  }

  return DayInsights(
    day: dayOnly,
    setsByGroup: setsByGroup,
    sessionsCount: daySessions.length,
  );
}

/// Returns the last [count] calendar days ending at [anchor] (inclusive),
/// oldest first — the window backing the day-strip navigation UI.
///
/// Calendar-constructor arithmetic (`DateTime(y, m, d - n)`), never
/// `.add(Duration(days: n))` — same DST-safety convention as `ChartPeriod`
/// and `_mondayOfWeek`. Time-of-day is always truncated from [anchor].
List<DateTime> lastNDays(DateTime anchor, int count) {
  final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
  return List.generate(
    count,
    (i) => DateTime(
      anchorDay.year,
      anchorDay.month,
      anchorDay.day - (count - 1 - i),
    ),
  );
}
