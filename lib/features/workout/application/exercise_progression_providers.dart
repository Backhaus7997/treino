import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../insights/domain/chart_period.dart';
import '../domain/exercise_progression.dart';
import '../domain/session.dart' show SessionCounting;
import '../domain/set_log.dart';
import 'exercise_progression_aggregator.dart';
import 'session_providers.dart'
    show sessionRepositoryProvider, sessionsByUidProvider;

/// Number of sessions to scan for exercise progression.
/// Shared constant — mirrors the design's D6 bound.
const int kProgressionSessionScan = 60;

/// Family key for [exerciseProgressionProvider].
///
/// [AD7] [period] selects the current-vs-previous comparison window (see
/// [ChartPeriod]) used to bound the returned series. Defaults to
/// [ChartPeriod.defaultPeriod] (last30d) at call sites that don't yet
/// surface a period selector.
typedef ExerciseProgressionKey = ({
  String athleteUid,
  String exerciseId,
  ChartPeriod period,
});

/// Derives [ExerciseProgression] for a given athlete + exercise.
///
/// Bounded scan: at most the last [kProgressionSessionScan] sessions.
/// Delegates math to the pure [aggregateExerciseProgression] function.
///
/// [AD7] `key.period`'s window is computed FIRST and used to widen the scan
/// bound when needed: [kProgressionSessionScan] remains a genuine safety cap
/// (protects against pathological history sizes), but the scan window is
/// never allowed to silently cut off sessions that fall inside the selected
/// period's window — `sessions` is DESC-ordered, so we scan at least as many
/// sessions as needed to cover every session within `windowFor(now)`'s
/// `previousStart`, up to [kProgressionSessionScan].
/// autoDispose: cache drops when the screen closes.
final exerciseProgressionProvider = FutureProvider.autoDispose
    .family<ExerciseProgression, ExerciseProgressionKey>((ref, key) async {
  if (key.athleteUid.isEmpty) {
    return ExerciseProgression.empty(
      exerciseId: key.exerciseId,
      exerciseName: '',
    );
  }

  final now = argentinaNow();
  final window = key.period.windowFor(now);

  final sessions =
      await ref.watch(sessionsByUidProvider(key.athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);

  // Sessions strictly needed to cover the period window (current+previous)
  // — never truncated by the scan cap below.
  final neededForWindow =
      sessions.where((s) => !s.startedAt.isBefore(window.previousStart)).length;
  final scanCount = neededForWindow > kProgressionSessionScan
      ? neededForWindow
      : kProgressionSessionScan;

  final scanned = sessions.take(scanCount).toList();

  // Fetch setLogs for all scanned sessions in parallel
  final logsPerSession = await Future.wait(
    scanned.map(
      (s) => repo.listSetLogs(uid: key.athleteUid, sessionId: s.id),
    ),
  );

  // Build map sessionId → logs
  final logsBySession = <String, List<SetLog>>{
    for (var i = 0; i < scanned.length; i++) scanned[i].id: logsPerSession[i],
  };

  return aggregateExerciseProgression(
    exerciseId: key.exerciseId,
    periodWindow: window,
    sessionsDesc: scanned, // already DESC from sessionsByUidProvider
    logsBySession: logsBySession,
    now: now,
  );
});

/// Derives the deduplicated list of exercises found in the bounded scan,
/// ordered so the most-recently-logged exercise appears first.
///
/// [exerciseName] is read from the denormalized field on [SetLog] —
/// no exercise-catalogue Firestore read is performed.
///
/// [#377] Each entry carries [ExerciseListEntry.periodsWithData]: the
/// [ChartPeriod]s whose CURRENT window holds at least one chartable set for
/// that exercise — same predicate the aggregator applies to build the series
/// (countsAsWorkout session per #372, weightKg > 0 per #368, ART calendar-day
/// window via [sessionInCurrentWindow]). All 3 periods are resolved in this
/// single scan on purpose: the family key stays the athleteUid, so switching
/// periods on screen reuses the cached list instead of re-reading Firestore.
/// List MEMBERSHIP is deliberately untouched — an exercise outside the active
/// period still shows in the picker; only the default preselection uses the
/// flags.
/// autoDispose: cache drops when no longer watched.
final athleteExerciseListProvider = FutureProvider.autoDispose
    .family<List<ExerciseListEntry>, String>((ref, athleteUid) async {
  if (athleteUid.isEmpty) return const [];

  final sessions = await ref.watch(sessionsByUidProvider(athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);

  final now = argentinaNow();
  final windows = {
    for (final period in ChartPeriod.values) period: period.windowFor(now),
  };

  // [#377] Same widening contract as [exerciseProgressionProvider]: the scan
  // cap must never silently cut off sessions inside a selectable period's
  // current window, or a heavy trainer's in-period exercise could miss both
  // its flag and its picker entry. Bounded by the earliest current-window
  // start across the 3 periods.
  final earliestCurrentStart = windows.values
      .map((w) => w.currentStart)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final neededForWindows =
      sessions.where((s) => !s.startedAt.isBefore(earliestCurrentStart)).length;
  final scanCount = neededForWindows > kProgressionSessionScan
      ? neededForWindows
      : kProgressionSessionScan;

  final scanned = sessions.take(scanCount).toList();

  final logsPerSession = await Future.wait(
    scanned.map(
      (s) => repo.listSetLogs(uid: athleteUid, sessionId: s.id),
    ),
  );

  // [#377] Per exercise: which periods' current windows hold chartable data.
  final periodsByExercise = <String, Set<ChartPeriod>>{};
  for (var i = 0; i < scanned.length; i++) {
    final session = scanned[i];
    if (!session.countsAsWorkout) continue;

    final periodsForSession = <ChartPeriod>{
      for (final entry in windows.entries)
        if (sessionInCurrentWindow(session, entry.value)) entry.key,
    };
    if (periodsForSession.isEmpty) continue;

    for (final log in logsPerSession[i]) {
      if (log.weightKg <= 0) continue;
      periodsByExercise
          .putIfAbsent(log.exerciseId, () => <ChartPeriod>{})
          .addAll(periodsForSession);
    }
  }

  // Walk sessions DESC (most-recent first) to preserve most-recent ordering
  final seen = <String>{};
  final result = <ExerciseListEntry>[];

  for (final logs in logsPerSession) {
    for (final log in logs) {
      if (seen.add(log.exerciseId)) {
        result.add(ExerciseListEntry(
          exerciseId: log.exerciseId,
          exerciseName: log.exerciseName,
          periodsWithData:
              periodsByExercise[log.exerciseId] ?? const <ChartPeriod>{},
        ));
      }
    }
  }

  return result;
});
