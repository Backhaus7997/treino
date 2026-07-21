// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 / SCENARIO-PROG-11C).
// All user-visible strings are injected as plain String parameters via
// [ExerciseProgressionChartLabels]. The mobile caller resolves them from AppL10n;
// the web caller passes hardcoded Spanish strings.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../app/theme/app_palette.dart';
import '../../application/exercise_progression_aggregator.dart';
import '../../domain/exercise_progression.dart';

// ── Short date helper ─────────────────────────────────────────────────────────

/// e.g. '7 abr' (es_AR) / '7 Apr' (en). Uses [DateTime]'s own calendar
/// fields directly — no toLocal() — matching the UTC convention of the app.
String _shortDate(DateTime dt, String localeName) =>
    intl.DateFormat('d MMM', localeName).format(dt);

// ── Display-value formatter ───────────────────────────────────────────────────

/// Formats a metric value for display.
///
/// [AD2] The 1RM (oneRepMax) series is the only computed series with
/// genuinely fractional values (Epley estimate). Per design, it must be
/// rounded to the nearest 0.5 kg AT DISPLAY ONLY before formatting. The other
/// 3 series (Heaviest Weight, Best Set Volume, Best Session Volume) are left
/// untouched — they are already whole/half-kg-plate values by construction.
String _formatMetricValue(double value, {required bool isOneRepMax}) {
  final display = isOneRepMax ? roundToNearestHalfKg(value) : value;
  return display % 1 == 0
      ? display.toStringAsFixed(0)
      : display.toStringAsFixed(1);
}

// ── Label bag ─────────────────────────────────────────────────────────────────

/// Plain-string label bag for [ExerciseProgressionChart].
///
/// The widget accepts this instead of an AppL10n instance so that it can be
/// used from both the mobile surface (strings from AppL10n) and the web surface
/// (hardcoded Spanish strings) without any platform-conditional import.
///
/// [AD3] Extended from the original 2-metric bag (PR/Volumen) to 4 distinct
/// client-computed metrics: Heaviest Weight (renamed from the mislabeled
/// "PR" — now "Peso máximo"), 1RM (AD2), Best Set Volume, Best Session
/// Volume (was "Volumen").
class ExerciseProgressionChartLabels {
  const ExerciseProgressionChartLabels({
    required this.heaviestWeightLabel,
    required this.oneRepMaxLabel,
    required this.bestSetVolumeLabel,
    required this.bestSessionVolumeLabel,
    required this.volumeUnit,
    required this.weightUnit,
    required this.frequencyLabel,
    required this.singlePointHint,
    required this.emptyHint,
  });

  /// E.g. 'Peso máximo' — renamed from the mislabeled 'PR' (AD3).
  final String heaviestWeightLabel;

  /// E.g. '1RM' — Epley-estimated one-rep max (AD2).
  final String oneRepMaxLabel;

  /// E.g. 'Mejor serie' — max(reps×weightKg) of a single set (AD3).
  final String bestSetVolumeLabel;

  /// E.g. 'Volumen' — Σ(reps×weightKg) per session (was 'Volumen'/PR-era).
  final String bestSessionVolumeLabel;

  /// E.g. 'kg·reps' — RD5: must NOT be plain 'kg'. Used by both volume
  /// metrics (Best Set Volume, Best Session Volume).
  final String volumeUnit;

  /// E.g. 'kg'. Used by both weight metrics (Heaviest Weight, 1RM).
  final String weightUnit;

  /// Converts a session count to a Frecuencia string.
  /// E.g. (n) => '$n sesiones en las últimas 8 semanas'
  final String Function(int count) frequencyLabel;

  /// Hint when exactly 1 data point exists (no trend line).
  final String singlePointHint;

  /// Hint when 0 data points exist for the exercise.
  final String emptyHint;
}

// ── Metric enum ───────────────────────────────────────────────────────────────

/// [AD3] The 4 client-computed metrics selectable via chip row.
enum _Metric { heaviestWeight, oneRepMax, bestSetVolume, bestSessionVolume }

// ── Public chart widget ───────────────────────────────────────────────────────

/// Progression line chart — label-injected, NEVER imports AppL10n.
///
/// - Heaviest Weight chip selected by default (SCENARIO-PROG-06A; renamed
///   from the old mislabeled "PR" default per AD3).
/// - <2 points → no line rendered (SCENARIO-PROG-07B/C).
/// - 0 points → emptyHint shown (SCENARIO-PROG-07A).
/// - Frecuencia stat shown ABOVE the chip row (SCENARIO-PROG-06C).
/// - Volume unit is 'kg·reps', not 'kg' (RD5).
class ExerciseProgressionChart extends StatefulWidget {
  const ExerciseProgressionChart({
    super.key,
    required this.progression,
    required this.labels,
    required this.localeName,
  });

  final ExerciseProgression progression;
  final ExerciseProgressionChartLabels labels;

  /// Locale name for date formatting (e.g. 'es_AR', 'en').
  final String localeName;

  @override
  State<ExerciseProgressionChart> createState() =>
      _ExerciseProgressionChartState();
}

class _ExerciseProgressionChartState extends State<ExerciseProgressionChart> {
  _Metric _selected = _Metric.heaviestWeight;

  List<ProgressionPoint> get _activeSeries {
    switch (_selected) {
      case _Metric.heaviestWeight:
        return widget.progression.heaviestWeightSeries;
      case _Metric.oneRepMax:
        return widget.progression.oneRepMaxSeries;
      case _Metric.bestSetVolume:
        return widget.progression.bestSetVolumeSeries;
      case _Metric.bestSessionVolume:
        return widget.progression.bestSessionVolumeSeries;
    }
  }

  String get _activeUnit {
    switch (_selected) {
      case _Metric.heaviestWeight:
      case _Metric.oneRepMax:
        return widget.labels.weightUnit;
      case _Metric.bestSetVolume:
      case _Metric.bestSessionVolume:
        return widget.labels.volumeUnit;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labels = widget.labels;
    final series = _activeSeries;

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
          // ── Frecuencia stat ABOVE chip row (SCENARIO-PROG-06C) ────────
          Text(
            labels.frequencyLabel(widget.progression.frequencyLast8Weeks),
            style: GoogleFonts.barlow(
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          // ── Metric chip row ───────────────────────────────────────────
          _MetricChipRow(
            selected: _selected,
            heaviestWeightLabel: labels.heaviestWeightLabel,
            oneRepMaxLabel: labels.oneRepMaxLabel,
            bestSetVolumeLabel: labels.bestSetVolumeLabel,
            bestSessionVolumeLabel: labels.bestSessionVolumeLabel,
            palette: palette,
            onSelect: (m) => setState(() => _selected = m),
          ),
          const SizedBox(height: 12),

          // ── Chart area ────────────────────────────────────────────────
          if (series.isEmpty)
            Text(
              labels.emptyHint,
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            )
          else if (series.length == 1)
            _SinglePointView(
              point: series.first,
              unit: _activeUnit,
              hint: labels.singlePointHint,
              palette: palette,
              isOneRepMax: _selected == _Metric.oneRepMax,
            )
          else
            _ProgressLineChart(
              points: series,
              unit: _activeUnit,
              localeName: widget.localeName,
              palette: palette,
              isOneRepMax: _selected == _Metric.oneRepMax,
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
    required this.heaviestWeightLabel,
    required this.oneRepMaxLabel,
    required this.bestSetVolumeLabel,
    required this.bestSessionVolumeLabel,
    required this.palette,
    required this.onSelect,
  });

  final _Metric selected;
  final String heaviestWeightLabel;
  final String oneRepMaxLabel;
  final String bestSetVolumeLabel;
  final String bestSessionVolumeLabel;
  final AppPalette palette;
  final void Function(_Metric) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: heaviestWeightLabel,
            isSelected: selected == _Metric.heaviestWeight,
            palette: palette,
            onTap: () => onSelect(_Metric.heaviestWeight),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: oneRepMaxLabel,
            isSelected: selected == _Metric.oneRepMax,
            palette: palette,
            onTap: () => onSelect(_Metric.oneRepMax),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: bestSetVolumeLabel,
            isSelected: selected == _Metric.bestSetVolume,
            palette: palette,
            onTap: () => onSelect(_Metric.bestSetVolume),
          ),
          const SizedBox(width: 6),
          _Chip(
            label: bestSessionVolumeLabel,
            isSelected: selected == _Metric.bestSessionVolume,
            palette: palette,
            onTap: () => onSelect(_Metric.bestSessionVolume),
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

// ── Single-point view ─────────────────────────────────────────────────────────

class _SinglePointView extends StatelessWidget {
  const _SinglePointView({
    required this.point,
    required this.unit,
    required this.hint,
    required this.palette,
    required this.isOneRepMax,
  });

  final ProgressionPoint point;
  final String unit;
  final String hint;
  final AppPalette palette;

  /// [AD2] Whether this point belongs to the 1RM series — the only series
  /// requiring 0.5kg display rounding.
  final bool isOneRepMax;

  @override
  Widget build(BuildContext context) {
    final valStr = _formatMetricValue(point.value, isOneRepMax: isOneRepMax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              valStr,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 28,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
        ),
      ],
    );
  }
}

// ── Line chart ────────────────────────────────────────────────────────────────

class _ProgressLineChart extends StatelessWidget {
  const _ProgressLineChart({
    required this.points,
    required this.unit,
    required this.localeName,
    required this.palette,
    required this.isOneRepMax,
  });

  final List<ProgressionPoint> points;
  final String unit;
  final String localeName;
  final AppPalette palette;

  /// [AD2] Whether [points] belongs to the 1RM series — the only series
  /// requiring 0.5kg display rounding.
  final bool isOneRepMax;

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].value),
    );

    final values = points.map((p) => p.value).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final range = (rawMax - rawMin).abs();
    final pad = range < 0.001 ? 1.0 : range * 0.08;
    final minY = rawMin - pad;
    final maxY = rawMax + pad;

    final labelIndices = _labelIndices(points.length);
    final midY = (minY + maxY) / 2;
    final yLabels = {minY, midY, maxY};
    final accentFill = palette.accent.withValues(alpha: 0.12);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
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
              belowBarData: BarAreaData(show: true, color: accentFill),
            ),
          ],
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                // The X axis is point-index-based, so titles must be sampled
                // at whole indices. Without a fixed interval fl_chart samples
                // fractional Xs sized to the chart width, and value.round()
                // maps neighbouring samples onto the same index → duplicated
                // and skipped date labels (#383).
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if ((value - idx).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  if (!labelIndices.contains(idx)) {
                    return const SizedBox.shrink();
                  }
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _shortDate(points[idx].date, localeName),
                      style: GoogleFonts.barlowCondensed(
                          fontSize: 10, color: palette.textMuted),
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
                  final isNear = yLabels
                      .any((y) => (y - value).abs() < (maxY - minY) * 0.05);
                  if (!isNear) return const SizedBox.shrink();
                  final label =
                      _formatMetricValue(value, isOneRepMax: isOneRepMax);
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(label,
                        style: GoogleFonts.barlowCondensed(
                            fontSize: 10, color: palette.textMuted)),
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
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => palette.bgCard,
              tooltipBorder: BorderSide(color: palette.border),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final idx = spot.x.round();
                final date =
                    (idx >= 0 && idx < points.length) ? points[idx].date : null;
                final valStr =
                    _formatMetricValue(spot.y, isOneRepMax: isOneRepMax);
                final dateStr =
                    date != null ? '\n${_shortDate(date, localeName)}' : '';
                return LineTooltipItem(
                  '$valStr $unit$dateStr',
                  GoogleFonts.barlow(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Pick at most 4 indices: always first + last; if >4, add 2 evenly spaced.
  static Set<int> _labelIndices(int count) {
    if (count == 0) return {};
    final indices = List.generate(count, (i) => i);
    if (count <= 4) return indices.toSet();
    final result = <int>{0, count - 1};
    final step = (count - 1) / 3;
    result.add(step.round());
    result.add((step * 2).round());
    return result;
  }
}

// ── Exercise picker row ───────────────────────────────────────────────────────

/// Horizontal scrollable chip row for exercise selection.
///
/// - One chip per [ExerciseListEntry].
/// - [selectedId] chip is highlighted.
/// - [onSelect] fires with the tapped exerciseId.
/// - Default selection is owned by the parent state (init with first.id).
/// - Do NOT reuse exercise_picker_sheet.dart (design ADR).
class ExercisePickerRow extends StatelessWidget {
  const ExercisePickerRow({
    super.key,
    required this.exercises,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ExerciseListEntry> exercises;
  final String? selectedId;
  final void Function(String exerciseId) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < exercises.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _ExerciseChip(
              entry: exercises[i],
              isSelected: exercises[i].exerciseId == selectedId,
              palette: palette,
              onTap: () => onSelect(exercises[i].exerciseId),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({
    required this.entry,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final ExerciseListEntry entry;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          entry.exerciseName,
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? palette.bg : palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
