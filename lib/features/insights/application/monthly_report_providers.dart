import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart';
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
      now: DateTime.now(),
    );
  }

  final repo = ref.watch(sessionRepositoryProvider);
  final sessions = await repo.listByUid(uid);

  // setLogs count per session, resolved in parallel (Future.wait) — same
  // fan-out convention as weeklyInsightsProvider/day_insights_providers.
  final logsPerSession = await Future.wait(
    sessions.map((s) => repo.listSetLogs(uid: uid, sessionId: s.id)),
  );
  final setsCountBySessionId = <String, int>{
    for (var i = 0; i < sessions.length; i++)
      sessions[i].id: logsPerSession[i].length,
  };

  return aggregateMonthlyReport(
    sessions: sessions,
    setsCountBySessionId: setsCountBySessionId,
    now: DateTime.now(),
  );
});
