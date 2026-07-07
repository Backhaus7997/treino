// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 / same
// AppL10n-free-widget convention as ExerciseProgressionChart/DayStripLabels).
// All user-visible strings are injected via [MonthlyReportChartLabels].

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../app/theme/app_palette.dart';
import '../../domain/monthly_report.dart';

// ── Label bag ─────────────────────────────────────────────────────────────────

/// Plain-string label bag for [MonthlyReportChart] — mirrors the
/// [ExerciseProgressionChartLabels] convention so both the athlete's own
/// screen and any future coach-side surfacing can inject their own strings.
class MonthlyReportChartLabels {
  const MonthlyReportChartLabels({
    required this.workoutsLabel,
    required this.durationLabel,
    required this.volumeLabel,
    required this.setsLabel,
    required this.emptyHint,
  });

  /// E.g. 'Entrenos'.
  final String workoutsLabel;

  /// E.g. 'Duración'.
  final String durationLabel;

  /// E.g. 'Volumen'.
  final String volumeLabel;

  /// E.g. 'Sets'.
  final String setsLabel;

  /// Shown when all 12 months are zero across every metric.
  final String emptyHint;
}

// ── Metric enum ───────────────────────────────────────────────────────────────

/// [AD6] The 4 metrics selectable via chip row, Hevy "June Report" parity.
enum MonthlyReportMetric { workouts, duration, volume, sets }

// ── Public chart widget ───────────────────────────────────────────────────────

/// 12-month bar chart with metric tabs (Workouts / Duration / Volume / Sets)
/// — chips switch the plotted metric, like Hevy's Monthly Report.
///
/// - Workouts chip selected by default.
/// - Tapping a bar invokes [onMonthSelected] with that bar's month anchor
///   (drives the summary cards' selected month).
/// - All-zero report across every metric → [labels.emptyHint] shown instead
///   of the chart.
class MonthlyReportChart extends StatefulWidget {
  const MonthlyReportChart({
    super.key,
    required this.report,
    required this.labels,
    required this.localeName,
    this.onMonthSelected,
  });

  final MonthlyReport report;
  final MonthlyReportChartLabels labels;

  /// Locale name for month-abbreviation formatting (e.g. 'es_AR', 'en').
  final String localeName;

  /// Invoked with the tapped bar's month anchor (day-1 00:00 local).
  final ValueChanged<DateTime>? onMonthSelected;

  @override
  State<MonthlyReportChart> createState() => MonthlyReportChartState();
}

/// Public state (not `_`-prefixed) so widget tests can drive
/// [debugSelectMonth] directly — fl_chart's touch gesture layer isn't
/// easily driven from `WidgetTester`, so the tap→callback wiring is
/// verified by invoking the same code path the touch handler calls.
class MonthlyReportChartState extends State<MonthlyReportChart> {
  MonthlyReportMetric selectedMetric = MonthlyReportMetric.workouts;

  /// Test-only hook — mirrors what `BarTouchData.touchCallback` invokes.
  @visibleForTesting
  void debugSelectMonth(DateTime month) => widget.onMonthSelected?.call(month);

  /// Empty state applies only when EVERY metric is zero across all 12
  /// months — switching chips must not re-trigger the empty hint for a
  /// month that has e.g. duration but not (yet) recorded volume.
  bool get _allZero => widget.report.points.every((p) =>
      p.workoutsCount == 0 &&
      p.durationMin == 0 &&
      p.volumeKg == 0 &&
      p.setsCount == 0);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labels = widget.labels;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricChipRow(
            selected: selectedMetric,
            labels: labels,
            palette: palette,
            onSelect: (m) => setState(() => selectedMetric = m),
          ),
          const SizedBox(height: 12),
          if (_allZero)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                labels.emptyHint,
                style:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
              ),
            )
          else
            _Bars(
              points: widget.report.points,
              metric: selectedMetric,
              localeName: widget.localeName,
              palette: palette,
              onBarTap: (month) => widget.onMonthSelected?.call(month),
            ),
        ],
      ),
    );
  }
}

// ── Metric chip row ───────────────────────────────────────────────────────────

class _MetricChipRow extends StatelessWidget {
  const _MetricChipRow({
    required this.selected,
    required this.labels,
    required this.palette,
    required this.onSelect,
  });

  final MonthlyReportMetric selected;
  final MonthlyReportChartLabels labels;
  final AppPalette palette;
  final void Function(MonthlyReportMetric) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: labels.workoutsLabel,
            isSelected: selected == MonthlyReportMetric.workouts,
            palette: palette,
            onTap: () => onSelect(MonthlyReportMetric.workouts),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: labels.durationLabel,
            isSelected: selected == MonthlyReportMetric.duration,
            palette: palette,
            onTap: () => onSelect(MonthlyReportMetric.duration),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: labels.volumeLabel,
            isSelected: selected == MonthlyReportMetric.volume,
            palette: palette,
            onTap: () => onSelect(MonthlyReportMetric.volume),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: labels.setsLabel,
            isSelected: selected == MonthlyReportMetric.sets,
            palette: palette,
            onTap: () => onSelect(MonthlyReportMetric.sets),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? palette.bg : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Bar chart ─────────────────────────────────────────────────────────────────

class _Bars extends StatelessWidget {
  const _Bars({
    required this.points,
    required this.metric,
    required this.localeName,
    required this.palette,
    required this.onBarTap,
  });

  final List<MonthlyReportPoint> points;
  final MonthlyReportMetric metric;
  final String localeName;
  final AppPalette palette;
  final ValueChanged<DateTime> onBarTap;

  num _valueOf(MonthlyReportPoint p) {
    switch (metric) {
      case MonthlyReportMetric.workouts:
        return p.workoutsCount;
      case MonthlyReportMetric.duration:
        return p.durationMin;
      case MonthlyReportMetric.volume:
        return p.volumeKg;
      case MonthlyReportMetric.sets:
        return p.setsCount;
    }
  }

  String _monthAbbrev(DateTime month) =>
      intl.DateFormat('MMM', localeName).format(month);

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => _valueOf(p).toDouble()).toList();
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => palette.bgCard,
              tooltipBorder: BorderSide(color: palette.border),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[group.x.toInt()];
                return BarTooltipItem(
                  '${_valueOf(point)}\n${_monthAbbrev(point.month)}',
                  GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                );
              },
            ),
            touchCallback: (event, response) {
              if (!event.isInterestedForInteractions) return;
              final index = response?.spot?.touchedBarGroupIndex;
              if (index == null || index < 0 || index >= points.length) {
                return;
              }
              onBarTap(points[index].month);
            },
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _monthAbbrev(points[idx].month),
                      style: GoogleFonts.barlowCondensed(
                          fontSize: 10, color: palette.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: palette.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _valueOf(points[i]).toDouble(),
                    color: palette.accent,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
