import '../../workout/domain/session.dart';
import '../../workout/domain/set_log.dart';
import '../domain/chart_period.dart';
import '../domain/muscle_distribution_insights.dart';
import '../domain/muscle_group.dart';
import '../domain/radar_axis.dart';

/// [AD4] Pure top-level aggregator for [MuscleDistributionInsights] — no
/// Riverpod, fully testable. Same "pure fn behind a thin provider" split as
/// [aggregateExerciseProgression].
///
/// [periodWindow]  the current+previous comparison window (see
///                 [ChartPeriod.windowFor]) — bounds BOTH halves of the
///                 returned insights.
/// [sessionsDesc]  sessions ordered DESC by startedAt (caller's bounded
///                 scan — mirrors [aggregateExerciseProgression]'s contract).
/// [logsBySession] map sessionId → that session's SetLogs.
/// [muscleGroupByExerciseId] resolves each `SetLog.exerciseId` to its raw
///                 `muscleGroup` string — same "catalog first, routine-slot
///                 fallback" resolution the caller (provider) performs,
///                 mirroring `weeklyInsightsProvider`'s convention. Unknown/
///                 legacy strings (→ `toDisplayGroup()` returns null) are
///                 skipped silently, same cutoff-2B rule as the heat-map.
MuscleDistributionInsights aggregateMuscleDistribution({
  required ChartPeriodWindow periodWindow,
  required List<Session> sessionsDesc,
  required Map<String, List<SetLog>> logsBySession,
  required Map<String, String> muscleGroupByExerciseId,
}) {
  final currentEndExclusive = DateTime(
    periodWindow.currentEnd.year,
    periodWindow.currentEnd.month,
    periodWindow.currentEnd.day + 1,
  );
  final previousEndExclusive = DateTime(
    periodWindow.previousEnd.year,
    periodWindow.previousEnd.month,
    periodWindow.previousEnd.day + 1,
  );

  bool inCurrent(Session s) =>
      !s.startedAt.isBefore(periodWindow.currentStart) &&
      s.startedAt.isBefore(currentEndExclusive);
  bool inPrevious(Session s) =>
      !s.startedAt.isBefore(periodWindow.previousStart) &&
      s.startedAt.isBefore(previousEndExclusive);

  final finished = sessionsDesc.where((s) => s.countsAsWorkout).toList();
  final currentSessions = finished.where(inCurrent).toList();
  final previousSessions = finished.where(inPrevious).toList();

  final currentSetsByAxis = <RadarAxis, int>{};
  final previousSetsByAxis = <RadarAxis, int>{};
  var currentDurationMin = 0;
  var previousDurationMin = 0;
  var currentVolumeKg = 0.0;
  var previousVolumeKg = 0.0;
  var currentSets = 0;
  var previousSets = 0;

  void tally({
    required Session session,
    required Map<RadarAxis, int> setsByAxis,
    required void Function(int deltaDuration, double deltaVolume, int deltaSets)
        accumulate,
  }) {
    final logs = logsBySession[session.id] ?? const [];
    for (final log in logs) {
      final groupRaw = muscleGroupByExerciseId[log.exerciseId];
      final displayGroup = groupRaw?.toDisplayGroup();
      if (displayGroup != null) {
        final axis = RadarAxis.fromDisplayGroup(displayGroup);
        setsByAxis[axis] = (setsByAxis[axis] ?? 0) + 1;
      }
    }
    accumulate(session.durationMin, session.totalVolumeKg, logs.length);
  }

  for (final session in currentSessions) {
    tally(
      session: session,
      setsByAxis: currentSetsByAxis,
      accumulate: (duration, volume, sets) {
        currentDurationMin += duration;
        currentVolumeKg += volume;
        currentSets += sets;
      },
    );
  }

  for (final session in previousSessions) {
    tally(
      session: session,
      setsByAxis: previousSetsByAxis,
      accumulate: (duration, volume, sets) {
        previousDurationMin += duration;
        previousVolumeKg += volume;
        previousSets += sets;
      },
    );
  }

  return MuscleDistributionInsights(
    currentSetsByAxis: currentSetsByAxis,
    previousSetsByAxis: previousSetsByAxis,
    currentWorkouts: currentSessions.length,
    previousWorkouts: previousSessions.length,
    currentDurationMin: currentDurationMin,
    previousDurationMin: previousDurationMin,
    currentVolumeKg: currentVolumeKg,
    previousVolumeKg: previousVolumeKg,
    currentSets: currentSets,
    previousSets: previousSets,
  );
}
