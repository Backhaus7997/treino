import 'package:freezed_annotation/freezed_annotation.dart';

part 'monthly_report.freezed.dart';

/// [AD6] A single calendar-month bucket for the monthly report bar chart
/// (Hevy "June Report" parity).
///
/// [month] is ALWAYS day-1 00:00 local of that calendar month (e.g.
/// `DateTime(2026, 6, 1)`) — a stable, comparable anchor. Empty months
/// (zero finished sessions) are still present in the series as a
/// zero-valued point — NOT omitted (design risk note: gaps would break the
/// fixed 12-bar layout).
@freezed
class MonthlyReportPoint with _$MonthlyReportPoint {
  const factory MonthlyReportPoint({
    required DateTime month,
    required int workoutsCount,
    required int durationMin,
    required double volumeKg,
    required int setsCount,
  }) = _MonthlyReportPoint;
}

/// [AD6] The last 12 calendar months (oldest..newest, always length 12),
/// as consumed by [MonthlyReportChart] + the month summary cards.
@freezed
class MonthlyReport with _$MonthlyReport {
  const factory MonthlyReport({
    required List<MonthlyReportPoint> points,
  }) = _MonthlyReport;
}
