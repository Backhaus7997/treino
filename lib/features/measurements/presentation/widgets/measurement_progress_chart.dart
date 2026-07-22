import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/measurement.dart';

/// Short date label: '7 abr'. recordedAt is a real UTC instant — localize
/// before formatting or it reads +3h / shifts the day near midnight (#392).
String _shortDate(DateTime dt, String localeName) {
  final local = dt.toLocal();
  return '${local.day} ${monthAbbrev(local, localeName)}';
}

// ── Bilateral average helper ──────────────────────────────────────────────────

double? _avg(double? a, double? b) {
  if (a != null && b != null) return (a + b) / 2;
  return a ?? b;
}

// ── Metric descriptor ─────────────────────────────────────────────────────────

class _ChartMetric {
  const _ChartMetric({
    required this.label,
    required this.unit,
    required this.extractor,
  });

  final String label;
  final String unit;
  final double? Function(Measurement) extractor;
}

/// All candidate metrics in preferred display order.
const _kAllMetrics = <_ChartMetric>[
  _ChartMetric(
    label: 'Peso',
    unit: 'kg',
    extractor: _extractWeight,
  ),
  _ChartMetric(
    label: '% Graso',
    unit: '%',
    extractor: _extractFat,
  ),
  _ChartMetric(
    label: 'Masa muscular',
    unit: 'kg',
    extractor: _extractMuscle,
  ),
  _ChartMetric(
    label: 'Cintura',
    unit: 'cm',
    extractor: _extractWaist,
  ),
  _ChartMetric(
    label: 'Pecho',
    unit: 'cm',
    extractor: _extractChest,
  ),
  _ChartMetric(
    label: 'Cadera',
    unit: 'cm',
    extractor: _extractHips,
  ),
  _ChartMetric(
    label: 'Hombros',
    unit: 'cm',
    extractor: _extractShoulders,
  ),
  _ChartMetric(
    label: 'Glúteos',
    unit: 'cm',
    extractor: _extractGlutes,
  ),
  _ChartMetric(
    label: 'Bíceps',
    unit: 'cm',
    extractor: _extractBiceps,
  ),
  _ChartMetric(
    label: 'Bíceps flex',
    unit: 'cm',
    extractor: _extractBicepsFlexed,
  ),
  _ChartMetric(
    label: 'Antebrazo',
    unit: 'cm',
    extractor: _extractForearm,
  ),
  _ChartMetric(
    label: 'Muslo sup',
    unit: 'cm',
    extractor: _extractUpperThigh,
  ),
  _ChartMetric(
    label: 'Muslo medio',
    unit: 'cm',
    extractor: _extractMidThigh,
  ),
  _ChartMetric(
    label: 'Gemelo',
    unit: 'cm',
    extractor: _extractCalf,
  ),
];

double? _extractWeight(Measurement m) => m.weightKg;
double? _extractFat(Measurement m) => m.fatPercentage;
double? _extractMuscle(Measurement m) => m.muscleMassKg;
double? _extractWaist(Measurement m) => m.waistCm;
double? _extractChest(Measurement m) => m.chestCm;
double? _extractHips(Measurement m) => m.hipsCm;
double? _extractShoulders(Measurement m) => m.shouldersCm;
double? _extractGlutes(Measurement m) => m.glutesCm;
double? _extractBiceps(Measurement m) => _avg(m.bicepsLCm, m.bicepsRCm);
double? _extractBicepsFlexed(Measurement m) =>
    _avg(m.bicepsFlexedLCm, m.bicepsFlexedRCm);
double? _extractForearm(Measurement m) => _avg(m.forearmLCm, m.forearmRCm);
double? _extractUpperThigh(Measurement m) =>
    _avg(m.upperThighLCm, m.upperThighRCm);
double? _extractMidThigh(Measurement m) => _avg(m.midThighLCm, m.midThighRCm);
double? _extractCalf(Measurement m) => _avg(m.calfLCm, m.calfRCm);

// ── Weeks / days delta helper ─────────────────────────────────────────────────

String _spanLabel(DateTime first, DateTime last) {
  final days = last.difference(first).inDays.abs();
  if (days < 7) return '($days ${days == 1 ? "día" : "días"})';
  final weeks = (days / 7).round();
  return '($weeks ${weeks == 1 ? "semana" : "semanas"})';
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// Progress line chart for the ANTROPOMETRÍA section.
///
/// Receives [measurements] sorted ascending by recordedAt.
/// Shows a metric selector (chips) and a [LineChart] for the selected metric.
/// Requires ≥2 measurements to be rendered (caller must gate).
class MeasurementProgressChart extends StatefulWidget {
  const MeasurementProgressChart({
    super.key,
    required this.measurements,
  });

  /// Sorted ascending by recordedAt. Must have length ≥ 2.
  final List<Measurement> measurements;

  @override
  State<MeasurementProgressChart> createState() =>
      _MeasurementProgressChartState();
}

class _MeasurementProgressChartState extends State<MeasurementProgressChart> {
  late _ChartMetric _selected;
  late List<_ChartMetric> _available;

  @override
  void initState() {
    super.initState();
    _available = _buildAvailable(widget.measurements);
    _selected = _available.first;
  }

  @override
  void didUpdateWidget(MeasurementProgressChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.measurements != widget.measurements) {
      _available = _buildAvailable(widget.measurements);
      // Keep current selection if still valid, else reset
      final stillValid = _available.any((m) => m.label == _selected.label);
      if (!stillValid) _selected = _available.first;
    }
  }

  /// Returns metrics that have ≥2 non-null data points.
  static List<_ChartMetric> _buildAvailable(List<Measurement> measurements) {
    final result = <_ChartMetric>[];
    for (final metric in _kAllMetrics) {
      int count = 0;
      for (final m in measurements) {
        if (metric.extractor(m) != null) count++;
        if (count >= 2) break;
      }
      if (count >= 2) result.add(metric);
    }
    return result.isEmpty ? [_kAllMetrics.first] : result;
  }

  // ── Build helpers ────────────────────────────────────────────────────────

  /// Extract (spotIndex, value, measurement) for the selected metric.
  List<({int idx, double value, Measurement m})> _dataPoints() {
    final result = <({int idx, double value, Measurement m})>[];
    for (var i = 0; i < widget.measurements.length; i++) {
      final v = _selected.extractor(widget.measurements[i]);
      if (v != null) result.add((idx: i, value: v, m: widget.measurements[i]));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final localeName = AppL10n.of(context).localeName;
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
              allMeasurements: widget.measurements,
              metric: _selected,
              palette: palette,
              localeName: localeName,
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

  final List<({int idx, double value, Measurement m})> points;
  final _ChartMetric metric;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final first = points.first;
    final last = points.last;
    final delta = last.value - first.value;
    final absDelta = delta.abs();
    final glyph = delta >= 0 ? '▲' : '▼';
    final span = _spanLabel(first.m.recordedAt, last.m.recordedAt);
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
    required this.allMeasurements,
    required this.metric,
    required this.palette,
    required this.localeName,
  });

  final List<({int idx, double value, Measurement m})> points;
  final List<Measurement> allMeasurements;
  final _ChartMetric metric;
  final AppPalette palette;
  final String localeName;

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
      for (final p in points) p.idx: p.m.recordedAt,
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
