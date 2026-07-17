import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/performance_test.dart';

// ── Localized short date ──────────────────────────────────────────────────────

/// Short date label, e.g. '7 abr' (es) / '7 Apr' (en).
///
/// [PerformanceTest.recordedAt] is a real instant, so it's localized before
/// formatting (#392) — a raw UTC value reads +3h in Argentina and shifts the
/// day near midnight. [intl.DateFormat.format] reads the [DateTime]'s calendar
/// fields directly, so we convert first.
String _shortDate(DateTime dt, String localeName) =>
    intl.DateFormat('d MMM', localeName).format(dt.toLocal());

// ── Metric descriptor ─────────────────────────────────────────────────────────

class _ChartMetric {
  const _ChartMetric({
    required this.label,
    required this.unit,
    required this.extractor,
  });

  /// Resolves the display label for the active locale.
  final String Function(AppL10n) label;
  final String unit;
  final double? Function(PerformanceTest) extractor;
}

/// All candidate metrics in preferred display order.
const _kAllMetrics = <_ChartMetric>[
  _ChartMetric(
      label: _labelCmj, unit: 'cm', extractor: _extractCmj),
  _ChartMetric(
      label: _labelSquatJump, unit: 'cm', extractor: _extractSquatJump),
  _ChartMetric(
      label: _labelAbalakov, unit: 'cm', extractor: _extractAbalakov),
  _ChartMetric(
      label: _labelBroadJump, unit: 'cm', extractor: _extractBroadJump),
  _ChartMetric(
      label: _labelSprint10, unit: 's', extractor: _extractSprint10),
  _ChartMetric(
      label: _labelSprint20, unit: 's', extractor: _extractSprint20),
  _ChartMetric(
      label: _labelSprint30, unit: 's', extractor: _extractSprint30),
  _ChartMetric(
      label: _labelSprint40, unit: 's', extractor: _extractSprint40),
  _ChartMetric(
      label: _labelSquat1rm, unit: 'kg', extractor: _extractSquat1rm),
  _ChartMetric(
      label: _labelBench1rm, unit: 'kg', extractor: _extractBench1rm),
  _ChartMetric(
      label: _labelDeadlift1rm, unit: 'kg', extractor: _extractDeadlift1rm),
  _ChartMetric(
      label: _labelOverheadPress1rm,
      unit: 'kg',
      extractor: _extractOverheadPress1rm),
  _ChartMetric(
      label: _labelPullUp1rm, unit: 'kg', extractor: _extractPullUp1rm),
  _ChartMetric(
      label: _labelVo2max, unit: 'ml/kg/min', extractor: _extractVo2max),
  _ChartMetric(
      label: _labelCourseNavette,
      unit: 'nivel',
      extractor: _extractCourseNavette),
  _ChartMetric(
      label: _labelCooper, unit: 'm', extractor: _extractCooper),
  _ChartMetric(
      label: _labelSitAndReach, unit: 'cm', extractor: _extractSitAndReach),
];

String _labelCmj(AppL10n l) => l.performanceChartMetricCmj;
String _labelSquatJump(AppL10n l) => l.performanceChartMetricSquatJump;
String _labelAbalakov(AppL10n l) => l.performanceChartMetricAbalakov;
String _labelBroadJump(AppL10n l) => l.performanceChartMetricBroadJump;
String _labelSprint10(AppL10n l) => l.performanceChartMetricSprint10;
String _labelSprint20(AppL10n l) => l.performanceChartMetricSprint20;
String _labelSprint30(AppL10n l) => l.performanceChartMetricSprint30;
String _labelSprint40(AppL10n l) => l.performanceChartMetricSprint40;
String _labelSquat1rm(AppL10n l) => l.performanceChartMetricSquat1rm;
String _labelBench1rm(AppL10n l) => l.performanceChartMetricBench1rm;
String _labelDeadlift1rm(AppL10n l) => l.performanceChartMetricDeadlift1rm;
String _labelOverheadPress1rm(AppL10n l) =>
    l.performanceChartMetricOverheadPress1rm;
String _labelPullUp1rm(AppL10n l) => l.performanceChartMetricPullUp1rm;
String _labelVo2max(AppL10n l) => l.performanceChartMetricVo2max;
String _labelCourseNavette(AppL10n l) => l.performanceChartMetricCourseNavette;
String _labelCooper(AppL10n l) => l.performanceChartMetricCooper;
String _labelSitAndReach(AppL10n l) => l.performanceChartMetricSitAndReach;

double? _extractCmj(PerformanceTest t) => t.cmjCm;
double? _extractSquatJump(PerformanceTest t) => t.squatJumpCm;
double? _extractAbalakov(PerformanceTest t) => t.abalakovCm;
double? _extractBroadJump(PerformanceTest t) => t.broadJumpCm;
double? _extractSprint10(PerformanceTest t) => t.sprint10mS;
double? _extractSprint20(PerformanceTest t) => t.sprint20mS;
double? _extractSprint30(PerformanceTest t) => t.sprint30mS;
double? _extractSprint40(PerformanceTest t) => t.sprint40mS;
double? _extractSquat1rm(PerformanceTest t) => t.squat1rmKg;
double? _extractBench1rm(PerformanceTest t) => t.benchPress1rmKg;
double? _extractDeadlift1rm(PerformanceTest t) => t.deadlift1rmKg;
double? _extractOverheadPress1rm(PerformanceTest t) => t.overheadPress1rmKg;
double? _extractPullUp1rm(PerformanceTest t) => t.pullUp1rmKg;
double? _extractVo2max(PerformanceTest t) => t.vo2maxMlKgMin;
double? _extractCourseNavette(PerformanceTest t) => t.courseNavetteLevel;
double? _extractCooper(PerformanceTest t) => t.cooperMeters;
double? _extractSitAndReach(PerformanceTest t) => t.sitAndReachCm;

// ── Weeks / days delta helper ─────────────────────────────────────────────────

String _spanLabel(AppL10n l10n, DateTime first, DateTime last) {
  final days = last.difference(first).inDays.abs();
  if (days < 7) return l10n.performanceChartSpanDays(days);
  final weeks = (days / 7).round();
  return l10n.performanceChartSpanWeeks(weeks);
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// Progress line chart for the RENDIMIENTO section.
///
/// Receives [tests] sorted ascending by recordedAt.
/// Shows a metric selector (chips) and a [LineChart] for the selected metric.
/// Requires ≥2 tests to be rendered (caller must gate).
class PerformanceProgressChart extends StatefulWidget {
  const PerformanceProgressChart({
    super.key,
    required this.tests,
  });

  /// Sorted ascending by recordedAt. Must have length ≥ 2.
  final List<PerformanceTest> tests;

  @override
  State<PerformanceProgressChart> createState() =>
      _PerformanceProgressChartState();
}

class _PerformanceProgressChartState extends State<PerformanceProgressChart> {
  _ChartMetric? _selected;
  late List<_ChartMetric> _available;

  @override
  void initState() {
    super.initState();
    _available = _buildAvailable(widget.tests);
    _selected = _available.isEmpty ? null : _available.first;
  }

  @override
  void didUpdateWidget(PerformanceProgressChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tests != widget.tests) {
      _available = _buildAvailable(widget.tests);
      if (_available.isEmpty) {
        _selected = null;
      } else {
        // Keep current selection if still valid, else reset. Metrics are
        // const instances from [_kAllMetrics], so identity comparison is stable.
        final stillValid = _available.any((m) => identical(m, _selected));
        if (!stillValid) _selected = _available.first;
      }
    }
  }

  /// Returns metrics that have ≥2 non-null data points.
  ///
  /// Returns an empty list when no metric is plottable — the caller gates on
  /// total test count, but two tests filling different fields yield no metric
  /// with ≥2 same-field values. Returning empty lets [build] show the
  /// "load another evaluation" hint instead of a fabricated, unplottable
  /// fallback metric.
  static List<_ChartMetric> _buildAvailable(List<PerformanceTest> tests) {
    final result = <_ChartMetric>[];
    for (final metric in _kAllMetrics) {
      int count = 0;
      for (final t in tests) {
        if (metric.extractor(t) != null) count++;
        if (count >= 2) break;
      }
      if (count >= 2) result.add(metric);
    }
    return result;
  }

  /// Extract (spotIndex, value, test) for the selected metric.
  List<({int idx, double value, PerformanceTest t})> _dataPoints(
    _ChartMetric metric,
  ) {
    final result = <({int idx, double value, PerformanceTest t})>[];
    for (var i = 0; i < widget.tests.length; i++) {
      final v = metric.extractor(widget.tests[i]);
      if (v != null) result.add((idx: i, value: v, t: widget.tests[i]));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final selected = _selected;

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
          // ── Section label ──────────────────────────────────────────────
          Text(
            l10n.performanceChartSectionLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          // No metric has ≥2 same-field values: show a hint instead of a
          // fabricated, unplottable chart.
          if (selected == null)
            Text(
              l10n.performanceChartEmptyHint,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            )
          else
            ..._buildChart(selected, palette, l10n),
        ],
      ),
    );
  }

  List<Widget> _buildChart(
    _ChartMetric selected,
    AppPalette palette,
    AppL10n l10n,
  ) {
    final points = _dataPoints(selected);
    return [
      // ── Metric chip selector ───────────────────────────────────────
      _MetricChipRow(
        available: _available,
        selected: selected,
        palette: palette,
        l10n: l10n,
        onSelect: (m) => setState(() => _selected = m),
      ),
      const SizedBox(height: 12),

      // ── Header: current value + delta ──────────────────────────────
      if (points.isNotEmpty)
        _ChartHeader(
            points: points, metric: selected, palette: palette, l10n: l10n),
      const SizedBox(height: 12),

      // ── Line chart ─────────────────────────────────────────────────
      if (points.length >= 2)
        _ProgressLineChart(
          points: points,
          allTests: widget.tests,
          metric: selected,
          palette: palette,
          l10n: l10n,
        ),
    ];
  }
}

// ── Metric chip row ───────────────────────────────────────────────────────────

class _MetricChipRow extends StatelessWidget {
  const _MetricChipRow({
    required this.available,
    required this.selected,
    required this.palette,
    required this.l10n,
    required this.onSelect,
  });

  final List<_ChartMetric> available;
  final _ChartMetric selected;
  final AppPalette palette;
  final AppL10n l10n;
  final void Function(_ChartMetric) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < available.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _Chip(
              metric: available[i],
              isSelected: identical(available[i], selected),
              palette: palette,
              l10n: l10n,
              onTap: () => onSelect(available[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.metric,
    required this.isSelected,
    required this.palette,
    required this.l10n,
    required this.onTap,
  });

  final _ChartMetric metric;
  final bool isSelected;
  final AppPalette palette;
  final AppL10n l10n;
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
          metric.label(l10n),
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

// ── Chart header: current value + delta ──────────────────────────────────────

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.points,
    required this.metric,
    required this.palette,
    required this.l10n,
  });

  final List<({int idx, double value, PerformanceTest t})> points;
  final _ChartMetric metric;
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final first = points.first;
    final last = points.last;
    final delta = last.value - first.value;
    final absDelta = delta.abs();
    final glyph = delta >= 0 ? '▲' : '▼';
    final span = _spanLabel(l10n, first.t.recordedAt, last.t.recordedAt);
    final currentStr = last.value % 1 == 0
        ? last.value.toStringAsFixed(0)
        : last.value.toStringAsFixed(1);
    final deltaStr = absDelta.toStringAsFixed(1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          currentStr,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          metric.unit,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$glyph $deltaStr ${metric.unit} ',
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        Text(
          span,
          style: GoogleFonts.barlow(
            fontSize: 12,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Line chart ────────────────────────────────────────────────────────────────

class _ProgressLineChart extends StatelessWidget {
  const _ProgressLineChart({
    required this.points,
    required this.allTests,
    required this.metric,
    required this.palette,
    required this.l10n,
  });

  final List<({int idx, double value, PerformanceTest t})> points;
  final List<PerformanceTest> allTests;
  final _ChartMetric metric;
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final localeName = l10n.localeName;
    final spots = points.map((p) => FlSpot(p.idx.toDouble(), p.value)).toList();

    // Y range with ~8% padding
    final values = points.map((p) => p.value).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final range = (rawMax - rawMin).abs();
    final pad = range < 0.001 ? 1.0 : range * 0.08;
    final minY = rawMin - pad;
    final maxY = rawMax + pad;

    // X range
    final minX = spots.first.x;
    final maxX = spots.last.x;

    // Which x indices get a bottom label: first, last, and up to 2 in between
    final labelIndices = _labelIndices(points.map((p) => p.idx).toList());

    // Build index → date map for bottom titles
    final indexToDate = <int, DateTime>{
      for (final p in points) p.idx: p.t.recordedAt,
    };

    // Left y-axis labels: min, mid, max
    final midY = (minY + maxY) / 2;
    final yLabels = {minY, midY, maxY};

    final accentFill = palette.accent.withValues(alpha: 0.12);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: palette.accent,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3.5,
                  color: palette.accent,
                  strokeWidth: 0,
                  strokeColor: palette.accent,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: accentFill,
              ),
            ),
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (!labelIndices.contains(idx)) {
                    return const SizedBox.shrink();
                  }
                  final date = indexToDate[idx];
                  if (date == null) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _shortDate(date, localeName),
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 10,
                        color: palette.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  // Only render near min, mid, max
                  final isNear = yLabels.any(
                    (y) => (y - value).abs() < (maxY - minY) * 0.05,
                  );
                  if (!isNear) return const SizedBox.shrink();
                  final label = value % 1 == 0
                      ? value.toStringAsFixed(0)
                      : value.toStringAsFixed(1);
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      label,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 10,
                        color: palette.textMuted,
                      ),
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
            getDrawingHorizontalLine: (_) => FlLine(
              color: palette.border,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => palette.bgCard,
              tooltipBorder: BorderSide(color: palette.border),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.round();
                  final date = indexToDate[idx];
                  final valStr = spot.y % 1 == 0
                      ? spot.y.toStringAsFixed(0)
                      : spot.y.toStringAsFixed(1);
                  final dateStr =
                      date != null ? '\n${_shortDate(date, localeName)}' : '';
                  return LineTooltipItem(
                    '$valStr ${metric.unit}$dateStr',
                    GoogleFonts.barlow(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Pick at most 4 indices to show as bottom labels:
  /// always first and last; if >4 points, add ~2 in between evenly.
  static Set<int> _labelIndices(List<int> indices) {
    if (indices.isEmpty) return {};
    if (indices.length <= 4) return indices.toSet();
    final result = <int>{indices.first, indices.last};
    // Add 2 evenly spaced interior points
    final step = (indices.length - 1) / 3;
    result.add(indices[(step).round()]);
    result.add(indices[(step * 2).round()]);
    return result;
  }
}
