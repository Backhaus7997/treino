import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/set_log.dart';
import '../domain/chart_period.dart';
import '../domain/muscle_distribution_insights.dart';
import 'muscle_distribution_aggregator.dart';

/// [AD6/PR5c] Family key for [athleteMonthRadarInsightsProvider]. Explicit
/// [uid] (NOT `currentUidProvider`) — same explicit-uid family pattern as
/// [athleteMonthlyReportProvider]/`athleteWorkoutDaysProvider` — so this
/// provider can later serve a coach-side surfacing too.
///
/// [month] is the SELECTED calendar month (any day-of-month; only
/// year/month are read) — current = that month, previous = the immediately
/// preceding calendar month.
typedef MonthRadarKey = ({String uid, DateTime month});

/// [AD6/PR5c] Month-vs-month muscle distribution radar insights — REUSES
/// [aggregateMuscleDistribution] (same pure fn as the last30d/thisWeek
/// radar) with a calendar-month window anchored at [MonthRadarKey.month]
/// instead of `DateTime.now()`.
///
/// [ChartPeriod.month.windowFor] derives its current/previous window purely
/// from the year/month of the `now` argument passed in — so passing the
/// SELECTED month (not the real "now") yields exactly "selected month
/// current, month-before-that previous", which is the month-vs-month
/// comparison this screen needs (Hevy's June Report "Muscle Distribution"
/// section).
///
/// Reads the FULL session list via [sessionRepositoryProvider] (`listByUid`)
/// — NOT the bounded 60-session scan used by the default radar — same
/// "capped scan is insufficient for a full-month view" rule already
/// documented on [athleteMonthlyReportProvider]/`athleteWorkoutDaysProvider`.
///
/// autoDispose: refreshes when the section is re-mounted or the selected
/// month changes (family key includes [MonthRadarKey.month]).
final athleteMonthRadarInsightsProvider = FutureProvider.autoDispose
    .family<MuscleDistributionInsights, MonthRadarKey>((ref, key) async {
  if (key.uid.isEmpty) return MuscleDistributionInsights.empty;

  final anchor = DateTime.utc(key.month.year, key.month.month, 1);
  final window = ChartPeriod.month.windowFor(anchor);

  final sessions = await ref.watch(sessionsByUidProvider(key.uid).future);
  if (sessions.isEmpty) return MuscleDistributionInsights.empty;

  final repo = ref.read(sessionRepositoryProvider);

  final logsPerSession = await Future.wait(
    sessions.map((s) => repo.listSetLogs(uid: key.uid, sessionId: s.id)),
  );
  final logsBySession = <String, List<SetLog>>{
    for (var i = 0; i < sessions.length; i++) sessions[i].id: logsPerSession[i],
  };

  // Public catalog first (O(1) lookup) — same resolution order as
  // muscleDistributionInsightsProvider.
  final exercises = await ref.watch(exercisesProvider.future);
  final catalogById = {for (final e in exercises) e.id: e.muscleGroup};

  // Per-session routine-slot fallback for custom exercises absent from the
  // catalog — resolves EACH distinct routine referenced by the sessions in
  // scope (mirrors muscleDistributionInsightsProvider's per-session
  // resolution, since a full-month window can span multiple routines).
  //
  // [visibleRoutineByIdProvider], NOT [routineByIdProvider] — same reasoning as
  // muscleDistributionInsightsProvider, and this provider is even MORE exposed:
  // it resolves routines for the athlete's ENTIRE session history (no bounded
  // scan), so it is likelier to reach one that is gone. Transient failures still
  // propagate rather than silently producing a wrong radar.
  final distinctRoutineIds =
      sessions.map((s) => s.routineId).toSet().where((id) => id.isNotEmpty);
  final routines = await Future.wait(
    distinctRoutineIds
        .map((id) => ref.watch(visibleRoutineByIdProvider(id).future)),
  );
  final slotGroupById = <String, String>{};
  for (final routine in routines) {
    if (routine == null) continue;
    for (final day in routine.days) {
      for (final slot in day.slots) {
        slotGroupById.putIfAbsent(slot.exerciseId, () => slot.muscleGroup);
      }
    }
  }

  final muscleGroupByExerciseId = <String, String>{
    ...catalogById,
    for (final entry in slotGroupById.entries)
      if (!catalogById.containsKey(entry.key)) entry.key: entry.value,
  };

  return aggregateMuscleDistribution(
    periodWindow: window,
    sessionsDesc: sessions,
    logsBySession: logsBySession,
    muscleGroupByExerciseId: muscleGroupByExerciseId,
  );
});
