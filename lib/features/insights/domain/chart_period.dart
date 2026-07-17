import 'package:freezed_annotation/freezed_annotation.dart';

part 'chart_period.freezed.dart';

/// [AD7] The current + previous comparison window for a given
/// [ChartPeriod], expressed as calendar-day boundaries (time-of-day always
/// zeroed — see [ChartPeriod.windowFor] doc for the DST-safety rationale).
///
/// All 4 fields are INCLUSIVE start/end calendar days — callers filtering
/// sessions by `startedAt` should treat [currentEnd]/[previousEnd] as the
/// last valid calendar day (i.e. compare against the END of that day, or
/// simply `!isAfter(end)` when `start`/`end` are truncated to midnight and
/// the compared value may carry a time-of-day component).
@freezed
class ChartPeriodWindow with _$ChartPeriodWindow {
  const factory ChartPeriodWindow({
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) = _ChartPeriodWindow;
}

/// [AD7] Selects the aggregation window for progression/radar charts.
///
/// - [last30d]: rolling 30-day window ending "today" — the DEFAULT for
///   exercise progression and muscle radar charts (not calendar-aligned).
/// - [thisWeek]: the calendar week (Monday..Sunday) containing "now".
/// - [month]: the calendar month containing "now".
///
/// All window arithmetic uses `DateTime(year, month, day)` CALENDAR
/// CONSTRUCTOR math, never `.add(Duration(days: n))` — the latter can drift
/// across a DST transition (a local day is not always exactly 24h in zones
/// that observe DST). Argentina has not observed DST since 2009, but the
/// chart period selector is shared UI, so the arithmetic must be correct in
/// any timezone the app may run in.
enum ChartPeriod {
  last30d,
  thisWeek,
  month;

  /// The default period for exercise progression + muscle radar charts.
  static const ChartPeriod defaultPeriod = ChartPeriod.last30d;

  /// Derives the current+previous window quad for this period, anchored at
  /// [now]. Time-of-day components of [now] are ignored — only the calendar
  /// day is used.
  ChartPeriodWindow windowFor(DateTime now) {
    switch (this) {
      case ChartPeriod.last30d:
        return _last30dWindow(now);
      case ChartPeriod.thisWeek:
        return _thisWeekWindow(now);
      case ChartPeriod.month:
        return _monthWindow(now);
    }
  }
}

/// Rolling 30-day window: `[today - 29 days, today]` (30 calendar days
/// inclusive), previous window is the 30 days immediately preceding it
/// (non-overlapping — `previousEnd` is the day BEFORE `currentStart`, same
/// non-overlapping convention as [_thisWeekWindow]/[_monthWindow]).
ChartPeriodWindow _last30dWindow(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final currentStart = DateTime.utc(today.year, today.month, today.day - 29);
  final previousEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 1);
  final previousStart =
      DateTime.utc(previousEnd.year, previousEnd.month, previousEnd.day - 29);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: today,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}

/// Calendar week (Monday..Sunday) containing [now], previous window is the
/// preceding Monday..Sunday week.
ChartPeriodWindow _thisWeekWindow(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final daysFromMonday = today.weekday - DateTime.monday;
  final currentStart =
      DateTime.utc(today.year, today.month, today.day - daysFromMonday);
  final currentEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day + 6);
  final previousStart =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 7);
  final previousEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 1);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: currentEnd,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}

/// Calendar month containing [now], previous window is the immediately
/// preceding calendar month. Handles all month lengths (28/29/30/31 days)
/// and year rollover (January → previous December) via calendar-constructor
/// arithmetic: `DateTime(y, m+1, 0)` yields the last day of month `m`.
ChartPeriodWindow _monthWindow(DateTime now) {
  final currentStart = DateTime.utc(now.year, now.month, 1);
  // Day 0 of next month == last day of this month.
  final currentEnd = DateTime.utc(now.year, now.month + 1, 0);

  final previousStart = DateTime.utc(now.year, now.month - 1, 1);
  final previousEnd = DateTime.utc(now.year, now.month, 0);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: currentEnd,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}
