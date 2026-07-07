import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../insights/domain/chart_period.dart';
import '../domain/exercise_frequency.dart';
import '../domain/set_log.dart';
import 'exercise_progression_providers.dart' show kProgressionSessionScan;
import 'exercise_frequency_aggregator.dart';
import 'session_providers.dart'
    show sessionRepositoryProvider, sessionsByUidProvider;

/// Family key for [exerciseFrequencyProvider].
///
/// [period] selects the [ChartPeriod] window used to bound the returned
/// ranking (see [ChartPeriod]). Defaults to [ChartPeriod.defaultPeriod]
/// (last30d) at call sites that don't yet surface a period selector.
typedef ExerciseFrequencyKey = ({String athleteUid, ChartPeriod period});

/// [PR4] Derives the most-frequent-exercises ranking for a given athlete +
/// period (Hevy's "Main exercises").
///
/// Bounded scan: at most the last [kProgressionSessionScan] sessions, widened
/// when needed so the selected period's window is never truncated (same
/// contract as [exerciseProgressionProvider]).
/// autoDispose: cache drops when the screen closes.
final exerciseFrequencyProvider = FutureProvider.autoDispose
    .family<List<ExerciseFrequencyEntry>, ExerciseFrequencyKey>(
        (ref, key) async {
  if (key.athleteUid.isEmpty) return const [];

  final now = DateTime.now();
  final window = key.period.windowFor(now);

  final sessions =
      await ref.watch(sessionsByUidProvider(key.athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);

  final neededForWindow =
      sessions.where((s) => !s.startedAt.isBefore(window.currentStart)).length;
  final scanCount = neededForWindow > kProgressionSessionScan
      ? neededForWindow
      : kProgressionSessionScan;

  final scanned = sessions.take(scanCount).toList();

  final logsPerSession = await Future.wait(
    scanned.map(
      (s) => repo.listSetLogs(uid: key.athleteUid, sessionId: s.id),
    ),
  );

  final logsBySession = <String, List<SetLog>>{
    for (var i = 0; i < scanned.length; i++) scanned[i].id: logsPerSession[i],
  };

  return aggregateExerciseFrequency(
    sessions: scanned,
    logsBySession: logsBySession,
    periodWindow: window,
  );
});
