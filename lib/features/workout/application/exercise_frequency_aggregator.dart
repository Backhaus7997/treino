import '../../../core/utils/argentina_time.dart';
import '../../insights/domain/chart_period.dart';
import '../domain/exercise_frequency.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// [PR4] Pure top-level aggregator — no Riverpod, fully testable.
///
/// Ranks exercises by the number of DISTINCT sessions containing at least
/// one set of that exercise (Hevy's "Main exercises"), descending.
///
/// [sessions]      any order accepted; MUST be DESC by [Session.startedAt]
///                 (most-recent first) so ties are broken by recency (see
///                 tie-break rule below) — matches `sessionsByUidProvider`'s
///                 output contract.
/// [logsBySession] map from sessionId → list of [SetLog]s for that session.
/// [periodWindow]  optional [ChartPeriod] window (see [ChartPeriodWindow]).
///                 When non-null, sessions with `startedAt` outside
///                 `[currentStart, currentEnd]` (inclusive, by calendar day)
///                 are excluded. When null, ALL sessions are considered.
///
/// #372: only sessions with [SessionCounting.countsAsWorkout] (finished AND
/// fully completed) are counted — abandoned sessions (`wasFullyCompleted=false`)
/// and
/// in-progress `active` sessions are excluded, matching the criterion the other
/// Insights screens already use (muscle distribution, monthly report, volume by
/// group). Without this, a half-abandoned session inflated the frequency
/// ranking while the same session was absent from the radar/monthly report.
///
/// Ties (same session count) are broken by which exercise was logged in the
/// more-recently-started session — i.e. the first session (in [sessions]'
/// DESC order) that contains the exercise determines tie precedence.
List<ExerciseFrequencyEntry> aggregateExerciseFrequency({
  required List<Session> sessions,
  required Map<String, List<SetLog>> logsBySession,
  ChartPeriodWindow? periodWindow,
}) {
  var scoped = sessions.where((s) => s.countsAsWorkout).toList();

  if (periodWindow != null) {
    final start = periodWindow.currentStart;
    final endExclusive = DateTime.utc(
      periodWindow.currentEnd.year,
      periodWindow.currentEnd.month,
      periodWindow.currentEnd.day + 1,
    );
    scoped = scoped
        .where((s) =>
            !toArgentina(s.startedAt).isBefore(start) &&
            toArgentina(s.startedAt).isBefore(endExclusive))
        .toList();
  }

  final sessionCounts = <String, int>{};
  final names = <String, String>{};
  // First DESC-position (most-recent) index at which each exercise appears —
  // used purely as the tie-break key (lower = more recent = wins ties).
  final firstSeenIndex = <String, int>{};

  for (var i = 0; i < scoped.length; i++) {
    final session = scoped[i];
    final logs = logsBySession[session.id] ?? const [];
    final exerciseIdsInSession = <String>{};

    for (final log in logs) {
      exerciseIdsInSession.add(log.exerciseId);
      names.putIfAbsent(log.exerciseId, () => log.exerciseName);
      firstSeenIndex.putIfAbsent(log.exerciseId, () => i);
    }

    for (final exerciseId in exerciseIdsInSession) {
      sessionCounts[exerciseId] = (sessionCounts[exerciseId] ?? 0) + 1;
    }
  }

  final entries = sessionCounts.entries
      .map((e) => ExerciseFrequencyEntry(
            exerciseId: e.key,
            exerciseName: names[e.key] ?? '',
            sessionCount: e.value,
          ))
      .toList();

  entries.sort((a, b) {
    final byCount = b.sessionCount.compareTo(a.sessionCount);
    if (byCount != 0) return byCount;
    return firstSeenIndex[a.exerciseId]!
        .compareTo(firstSeenIndex[b.exerciseId]!);
  });

  return entries;
}
