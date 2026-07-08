import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_duration.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/data/session_repository.dart';
import '../../workout/domain/session.dart';
import '../domain/monthly_report.dart';
import 'monthly_report_aggregator.dart';

/// [AD6] The last-12-calendar-months report for [uid]'s workouts.
///
/// Explicit-uid family (NOT [currentUidProvider]) so this same provider
/// serves both the athlete's own Monthly Report screen and any future
/// coach-side surfacing, same pattern as `athleteDayInsightsProvider`.
///
/// IMPORTANT: reads the FULL session list via [sessionRepositoryProvider]
/// (`listByUid`) — NOT a capped/paged scan. Design explicitly flags the
/// 60-session scan bound used by `lastWeightByExerciseProvider` as
/// INSUFFICIENT for a 12-month report (a 60-session cap can silently drop
/// entire months for an active athlete).
///
/// autoDispose: refreshes when the screen is re-mounted.
final athleteMonthlyReportProvider =
    FutureProvider.autoDispose.family<MonthlyReport, String>((ref, uid) async {
  if (uid.isEmpty) {
    return aggregateMonthlyReport(
      sessions: const [],
      setsCountBySessionId: const {},
      durationMinBySessionId: const {},
      now: DateTime.now(),
    );
  }

  final repo = ref.watch(sessionRepositoryProvider);
  final inputs = await _loadReportInputs(repo: repo, uid: uid);

  return aggregateMonthlyReport(
    sessions: inputs.sessions,
    setsCountBySessionId: inputs.setsCountBySessionId,
    durationMinBySessionId: inputs.durationMinBySessionId,
    now: DateTime.now(),
  );
});

typedef AthleteDailyDurationReportKey = ({String uid, DateTime month});

final athleteDailyDurationReportProvider = FutureProvider.autoDispose
    .family<List<MonthlyReportDayPoint>, AthleteDailyDurationReportKey>(
        (ref, key) async {
  final repo = ref.watch(sessionRepositoryProvider);
  if (key.uid.isEmpty) {
    return aggregateDailyDurationReport(
      sessions: const [],
      durationMinBySessionId: const {},
      month: key.month,
    );
  }

  final inputs = await _loadReportInputs(repo: repo, uid: key.uid);
  return aggregateDailyDurationReport(
    sessions: inputs.sessions,
    durationMinBySessionId: inputs.durationMinBySessionId,
    month: key.month,
  );
});

Future<
    ({
      List<Session> sessions,
      Map<String, int> setsCountBySessionId,
      Map<String, int> durationMinBySessionId,
    })> _loadReportInputs({
  required SessionRepository repo,
  required String uid,
}) async {
  final sessions = await repo.listByUid(uid);

  // setLogs per session, resolved in parallel (Future.wait) — same fan-out
  // convention as weeklyInsightsProvider/day_insights_providers.
  final logsPerSession = await Future.wait(
    sessions.map((s) => repo.listSetLogs(uid: uid, sessionId: s.id)),
  );

  return (
    sessions: sessions,
    setsCountBySessionId: {
      for (var i = 0; i < sessions.length; i++)
        sessions[i].id: logsPerSession[i].length,
    },
    durationMinBySessionId: {
      for (var i = 0; i < sessions.length; i++)
        sessions[i].id: sanitizedFinishedSessionDurationMin(
          session: sessions[i],
          setLogs: logsPerSession[i],
        ),
    },
  );
}
