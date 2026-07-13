import '../../workout/domain/session.dart';
import '../domain/monthly_report.dart';

/// How many calendar-month bars the report shows — Hevy parity ("June
/// Report" style: last 12 months ending at the current calendar month).
const int monthlyReportWindowSize = 12;

/// [AD6] Aggregates [sessions] into [monthlyReportWindowSize] calendar-month
/// buckets ending at the calendar month containing [now] (inclusive).
///
/// - Only [SessionStatus.finished] sessions are counted.
/// - Bucketing uses `startedAt.toLocal()`'s calendar year/month — NOT a
///   rolling 30-day window (design risk: the 60-session scan bound used
///   elsewhere is INSUFFICIENT here — callers MUST pass the full session
///   list for the uid, not a capped/paged slice).
/// - Every one of the 12 months is present in [MonthlyReport.points], even
///   if zero sessions fall in it — the chart must render 12 fixed bars, not
///   skip empty months (would misalign the x-axis).
/// - The current (possibly partial) month is included as a whole bucket —
///   all its finished sessions count, regardless of how many days have
///   elapsed so far.
/// - [setsCountBySessionId] is a pure lookup (sessionId -> total set-log
///   count for that session) so this function stays free of Firestore
///   reads; callers resolve it via `Future.wait` over `listSetLogs`, same
///   pattern as [weeklyInsightsProvider]/`athleteDayInsightsProvider`.
MonthlyReport aggregateMonthlyReport({
  required List<Session> sessions,
  required Map<String, int> setsCountBySessionId,
  required Map<String, int> durationMinBySessionId,
  required DateTime now,
}) {
  final anchor = DateTime(now.year, now.month);

  // Oldest..newest month anchors, each day-1 00:00 local.
  final months = List.generate(
    monthlyReportWindowSize,
    (i) => DateTime(
      anchor.year,
      anchor.month - (monthlyReportWindowSize - 1) + i,
    ),
  );

  // Bucket key: `year * 12 + (month - 1)` — stable int key for O(1) lookup,
  // avoids DateTime equality/hash subtleties.
  int keyOf(DateTime d) => d.year * 12 + (d.month - 1);

  final workoutsByKey = <int, int>{};
  final durationByKey = <int, int>{};
  final volumeByKey = <int, double>{};
  final setsByKey = <int, int>{};

  final windowStartKey = keyOf(months.first);
  final windowEndKey = keyOf(months.last);

  for (final session in sessions) {
    if (!session.countsAsWorkout) continue;
    final started = session.startedAt.toLocal();
    final key = keyOf(DateTime(started.year, started.month));
    if (key < windowStartKey || key > windowEndKey) continue;

    workoutsByKey[key] = (workoutsByKey[key] ?? 0) + 1;
    durationByKey[key] =
        (durationByKey[key] ?? 0) + (durationMinBySessionId[session.id] ?? 0);
    volumeByKey[key] = (volumeByKey[key] ?? 0) + session.totalVolumeKg;
    setsByKey[key] =
        (setsByKey[key] ?? 0) + (setsCountBySessionId[session.id] ?? 0);
  }

  final points = months.map((month) {
    final key = keyOf(month);
    return MonthlyReportPoint(
      month: month,
      workoutsCount: workoutsByKey[key] ?? 0,
      durationMin: durationByKey[key] ?? 0,
      volumeKg: volumeByKey[key] ?? 0,
      setsCount: setsByKey[key] ?? 0,
    );
  }).toList();

  return MonthlyReport(points: points);
}

List<MonthlyReportDayPoint> aggregateDailyDurationReport({
  required List<Session> sessions,
  required Map<String, int> durationMinBySessionId,
  required DateTime month,
}) {
  final monthStart = DateTime(month.year, month.month);
  final dayCount = DateTime(month.year, month.month + 1, 0).day;
  final durationByDay = <int, int>{};

  for (final session in sessions) {
    if (!session.countsAsWorkout) continue;
    final started = session.startedAt.toLocal();
    if (started.year != monthStart.year || started.month != monthStart.month) {
      continue;
    }

    durationByDay[started.day] = (durationByDay[started.day] ?? 0) +
        (durationMinBySessionId[session.id] ?? 0);
  }

  return List.generate(dayCount, (i) {
    final day = i + 1;
    return MonthlyReportDayPoint(
      day: DateTime(monthStart.year, monthStart.month, day),
      durationMin: durationByDay[day] ?? 0,
    );
  });
}
