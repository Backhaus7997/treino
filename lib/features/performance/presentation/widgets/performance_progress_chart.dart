import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/performance_test.dart';

// ── Spanish month abbreviations ───────────────────────────────────────────────

const _kMonthsShort = <String>[
  '',
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Short date label: '7 abr'
String _shortDate(DateTime dt) => '${dt.day} ${_kMonthsShort[dt.month]}';

// ── Metric descriptor ─────────────────────────────────────────────────────────

class _ChartMetric {
  const _ChartMetric({
    required this.label,
    required this.unit,
    required this.extractor,
  });

  final String label;
  final String unit;
  final double? Function(PerformanceTest) extractor;
}

/// All candidate metrics in preferred display order.
const _kAllMetrics = <_ChartMetric>[
  _ChartMetric(label: 'CMJ', unit: 'cm', extractor: _extractCmj),
  _ChartMetric(label: 'Squat Jump', unit: 'cm', extractor: _extractSquatJump),
  _ChartMetric(label: 'Abalakov', unit: 'cm', extractor: _extractAbalakov),
  _ChartMetric(label: 'Salto largo', unit: 'cm', extractor: _extractBroadJump),
  _ChartMetric(label: 'Sprint 10m', unit: 's', extractor: _extractSprint10),
  _ChartMetric(label: 'Sprint 20m', unit: 's', extractor: _extractSprint20),
  _ChartMetric(label: 'Sprint 30m', unit: 's', extractor: _extractSprint30),
  _ChartMetric(label: 'Sprint 40m', unit: 's', extractor: _extractSprint40),
  _ChartMetric(
      label: 'Sentadilla 1RM', unit: 'kg', extractor: _extractSquat1rm),
  _ChartMetric(label: 'Banca 1RM', unit: 'kg', extractor: _extractBench1rm),
  _ChartMetric(
      label: 'Peso muerto 1RM', unit: 'kg', extractor: _extractDeadlift1rm),
  _ChartMetric(
      label: 'Press militar 1RM',
      unit: 'kg',
      extractor: _extractOverheadPress1rm),
  _ChartMetric(label: 'Dominada 1RM', unit: 'kg', extractor: _extractPullUp1rm),
  _ChartMetric(label: 'VO2máx', unit: 'ml/kg/min', extractor: _extractVo2max),
  _ChartMetric(
      label: 'Course Navette', unit: 'nivel', extractor: _extractCourseNavette),
  _ChartMetric(label: 'Cooper', unit: 'm', extractor: _extractCooper),
  _ChartMetric(
      label: 'Flexibilidad', unit: 'cm', extractor: _extractSitAndReach),
];

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

String _spanLabel(DateTime first, DateTime last) {
  final days = last.difference(first).inDays.abs();
  if (days < 7) return '($days ${days == 1 ? "día" : "días"})';
  final weeks = (days / 7).round();
  return '($weeks ${weeks == 1 ? "semana" : "semanas"})';
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
  late _ChartMetric _selected;
  late List<_ChartMetric> _available;

  @override
  void initState() {
    super.initState();
    _available = _buildAvailable(widget.tests);
    _selected = _available.first;
  }

  @override
  void didUpdateWidget(PerformanceProgressChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tests != widget.tests) {
      _available = _buildAvailable(widget.tests);
      // Keep current selection if still valid, else reset
      final stillValid = _available.any((m) => m.label == _selected.label);
      if (!stillValid) _selected = _available.first;
    }
  }

  /// Returns metrics that have ≥2 non-null data points.
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
    return result.isEmpty ? [_kAllMetrics.first] : result;
  }

  /// Extract (spotIndex, value, test) for the selected metric.
  List<({int idx, double value, PerformanceTest t})> _dataPoints() {
    final result = <({int idx, double value, PerformanceTest t})>[];
    for (var i = 0; i < widget.tests.length; i++) {
      final v = _selected.extractor(widget.tests[i]);
      if (v != null) result.add((idx: i, value: v, t: widget.tests[i]));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final points = _dataPoints();

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
            'PROGRESO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          // ── Metric chip selector ───────────────────────────────────────
          _MetricChipRow(
            available: _available,
            selected: _selected,
            palette: palette,
            onSelect: (m) => setState(() => _selected = m),
          ),
          const SizedBox(height: 12),

          // ── Header: current value + delta ──────────────────────────────
          if (points.isNotEmpty)
            _ChartHeader(points: points, metric: _selected, palette: palette),
          const SizedBox(height: 12),

          // ── Line chart ─────────────────────────────────────────────────
          if (points.length >= 2)
            _ProgressLineChart(
              points: points,
              allTests: widget.tests,
              metric: _selected,
              palette: palette,
            ),
        ],
      ),
    );
  }
}

// ── Metric chip row ───────────────────────────────────────────────────────────

class _MetricChipRow extends StatelessWidget {
  const _MetricChipRow({
    required this.available,
    required this.selected,
    required this.palette,
    required this.onSelect,
  });

  final List<_ChartMetric> available;
  final _ChartMetric selected;
  final AppPalette palette;
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
              isSelected: available[i].label == selected.label,
              palette: palette,
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
    required this.onTap,
  });

  final _ChartMetric metric;
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
          metric.label,
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
  });

  final List<({int idx, double value, PerformanceTest t})> points;
  final _ChartMetric metric;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final first = points.first;
    final last = points.last;
    final delta = last.value - first.value;
    final absDelta = delta.abs();
    final glyph = delta >= 0 ? '▲' : '▼';
    final span = _spanLabel(first.t.recordedAt, last.t.recordedAt);
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
  });

  final List<({int idx, double value, PerformanceTest t})> points;
  final List<PerformanceTest> allTests;
  final _ChartMetric metric;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
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
                      _shortDate(date),
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
                  final dateStr = date != null ? '\n${_shortDate(date)}' : '';
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
