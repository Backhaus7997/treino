import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/set_log.dart';
import '../domain/chart_period.dart';
import '../domain/muscle_distribution_insights.dart';
import 'muscle_distribution_aggregator.dart';
import 'routine_slot_groups.dart';

/// Number of sessions to scan for the muscle distribution radar — mirrors
/// [kProgressionSessionScan]'s bounded-scan convention.
const int kMuscleDistributionSessionScan = 60;

/// Family key for [muscleDistributionInsightsProvider].
///
/// Explicit [uid] (NOT [currentUidProvider]) — same explicit-uid family
/// pattern established by [exerciseProgressionProvider] — so the SAME
/// provider can later serve a coach's alumno-detail view keyed by the
/// athlete's uid, without depending on the currently-authenticated user.
typedef MuscleDistributionKey = ({String uid, ChartPeriod period});

/// Derives [MuscleDistributionInsights] for a given (uid, period).
///
/// Bounded scan: at most the last [kMuscleDistributionSessionScan] sessions,
/// widened when needed to fully cover the period's previous window (same
/// "never truncate inside the selected window" rule as
/// [exerciseProgressionProvider]).
///
/// Exercise → muscleGroup resolution: public catalog first, then the
/// per-SESSION routine-slot fallback shared with [weeklyInsightsProvider]
/// and the month radar ([slotMuscleGroupsForSessions], #442) — a period
/// window can span multiple routines (e.g. the athlete switched plans
/// mid-period), and assuming a single routine would silently drop
/// custom-exercise sets logged under a since-replaced routine.
/// autoDispose: re-evaluated on screen re-mount, same as
/// [weeklyInsightsProvider]/[exerciseProgressionProvider].
final muscleDistributionInsightsProvider = FutureProvider.autoDispose
    .family<MuscleDistributionInsights, MuscleDistributionKey>(
        (ref, key) async {
  if (key.uid.isEmpty) return MuscleDistributionInsights.empty;

  final now = argentinaNow();
  final window = key.period.windowFor(now);

  final sessions = await ref.watch(sessionsByUidProvider(key.uid).future);
  final repo = ref.read(sessionRepositoryProvider);

  // Sessions strictly needed to cover the period window (current+previous)
  // — never truncated by the scan cap below (same rule as
  // exerciseProgressionProvider).
  // toArgentina to match the aggregator's ART frame: window bounds are now
  // DateTime.utc (ART calendar days), so the session must be compared in the
  // same frame — a raw startedAt here would size the scan against a 3h-shifted
  // cutoff (#379).
  final neededForWindow = sessions
      .where((s) => !toArgentina(s.startedAt).isBefore(window.previousStart))
      .length;
  final scanCount = neededForWindow > kMuscleDistributionSessionScan
      ? neededForWindow
      : kMuscleDistributionSessionScan;

  final scanned = sessions.take(scanCount).toList();
  if (scanned.isEmpty) return MuscleDistributionInsights.empty;

  // setLogs per scanned session, in parallel.
  final logsPerSession = await Future.wait(
    scanned.map((s) => repo.listSetLogs(uid: key.uid, sessionId: s.id)),
  );
  final logsBySession = <String, List<SetLog>>{
    for (var i = 0; i < scanned.length; i++) scanned[i].id: logsPerSession[i],
  };

  // Public catalog first (O(1) lookup).
  final exercises = await ref.watch(exercisesProvider.future);
  final catalogById = {for (final e in exercises) e.id: e.muscleGroup};

  // Per-session routine-slot fallback — resolves EACH distinct routine
  // referenced by the scanned sessions (not just the most-recent one), via
  // the resolver shared with the weekly aggregate and the month radar
  // (#442). See [slotMuscleGroupsForSessions] for why it reads
  // `visibleRoutineByIdProvider` (a routine that is GONE degrades to "no
  // fallback for its exercises"; transient failures still propagate instead
  // of silently producing a wrong chart).
  final slotGroupById = await slotMuscleGroupsForSessions(ref, scanned);

  final muscleGroupByExerciseId = <String, String>{
    ...catalogById,
    for (final entry in slotGroupById.entries)
      if (!catalogById.containsKey(entry.key)) entry.key: entry.value,
  };

  return aggregateMuscleDistribution(
    periodWindow: window,
    sessionsDesc: scanned,
    logsBySession: logsBySession,
    muscleGroupByExerciseId: muscleGroupByExerciseId,
  );
});
