// IMPORTANT: This widget MUST NOT import app_l10n.dart (same R3 rule as
// ExerciseProgressionChart / ExerciseProgressionSection). All user-visible
// strings are injected as plain String parameters via
// [MuscleDistributionLabels]. The mobile caller resolves them from AppL10n;
// a future web caller (coach surfacing) passes hardcoded Spanish strings.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../domain/muscle_distribution_insights.dart';
import '../../domain/radar_axis.dart';

// ── Label bag ─────────────────────────────────────────────────────────────────

/// Plain-string label bag for [MuscleDistributionRadar]. NEVER imports
/// AppL10n — see file header.
class MuscleDistributionLabels {
  const MuscleDistributionLabels({
    required this.currentLabel,
    required this.previousLabel,
    required this.emptyStateText,
    required this.workoutsLabel,
    required this.durationLabel,
    required this.volumeLabel,
    required this.setsLabel,
    required this.durationUnit,
    required this.volumeUnit,
  });

  /// E.g. 'Actual' — current-period legend entry (Hevy: "Current").
  final String currentLabel;

  /// E.g. 'Anterior' — previous-period legend entry (Hevy: "Previous").
  final String previousLabel;

  /// E.g. 'Sin datos para este período.' — shown when [MuscleDistributionInsights.isEmpty].
  final String emptyStateText;

  /// E.g. 'Entrenos' — Workouts stat card label.
  final String workoutsLabel;

  /// E.g. 'Duración' — Duration stat card label.
  final String durationLabel;

  /// E.g. 'Volumen' — Volume stat card label.
  final String volumeLabel;

  /// E.g. 'Sets' — Sets stat card label.
  final String setsLabel;

  /// E.g. 'min' — unit suffix for the Duration stat card.
  final String durationUnit;

  /// E.g. 'kg' — unit suffix for the Volume stat card.
  final String volumeUnit;
}

// ── Radar widget ──────────────────────────────────────────────────────────────

/// [AD4] Muscle distribution radar — 6-axis (Back/Chest/Core/Shoulders/
/// Arms/Legs) current-vs-previous period overlay, Hevy-style: Current
/// (accent) / Previous (muted gray) legend, plus 4 stat cards (Workouts/
/// Duration/Volume/Sets) with a previous-period delta arrow.
///
/// Empty state (spec requirement 4): when [MuscleDistributionInsights.isEmpty],
/// shows [MuscleDistributionLabels.emptyStateText] instead of the chart.
class MuscleDistributionRadar extends StatelessWidget {
  const MuscleDistributionRadar({
    super.key,
    required this.insights,
    required this.labels,
  });

  final MuscleDistributionInsights insights;
  final MuscleDistributionLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

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
          if (insights.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                labels.emptyStateText,
                style:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
              ),
            )
          else ...[
            _RadarLegend(labels: labels, palette: palette),
            const SizedBox(height: 12),
            _Radar(insights: insights, palette: palette),
            const SizedBox(height: 12),
            _StatCardGrid(insights: insights, labels: labels),
          ],
        ],
      ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _RadarLegend extends StatelessWidget {
  const _RadarLegend({required this.labels, required this.palette});

  final MuscleDistributionLabels labels;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LegendDot(color: palette.accent, label: labels.currentLabel),
        const SizedBox(width: 18),
        _LegendDot(color: palette.textMuted, label: labels.previousLabel),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
        ),
      ],
    );
  }
}

// ── Radar chart ───────────────────────────────────────────────────────────────

class _Radar extends StatelessWidget {
  const _Radar({required this.insights, required this.palette});

  final MuscleDistributionInsights insights;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    const axes = RadarAxis.displayOrder;
    final currentEntries = axes
        .map((axis) => RadarEntry(
            value: (insights.currentSetsByAxis[axis] ?? 0).toDouble()))
        .toList();
    final previousEntries = axes
        .map((axis) => RadarEntry(
            value: (insights.previousSetsByAxis[axis] ?? 0).toDouble()))
        .toList();

    return SizedBox(
      height: 240,
      child: RadarChart(
        // TREINO Motion PR2: anima el morph del polígono al cambiar de
        // período con los tokens del sistema. fl_chart 1.x expone
        // `duration`/`curve` (los viejos `swapAnimation*` están deprecados).
        // `resolve` respeta reduce-motion (→ Duration.zero).
        duration: AppMotion.resolve(context, AppMotion.base),
        curve: AppMotion.standard,
        RadarChartData(
          radarShape: RadarShape.polygon,
          tickCount: 4,
          radarBorderData: BorderSide(color: palette.border),
          gridBorderData: BorderSide(color: palette.border),
          tickBorderData: BorderSide(color: palette.border, width: 0),
          titleTextStyle: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.6,
            color: palette.textMuted,
          ),
          getTitle: (index, angle) => RadarChartTitle(
            text: axes[index].displayLabel,
            angle: angle,
          ),
          dataSets: [
            RadarDataSet(
              dataEntries: previousEntries,
              fillColor: palette.textMuted.withValues(alpha: 0.12),
              borderColor: palette.textMuted,
              borderWidth: 2,
              entryRadius: 2.5,
            ),
            RadarDataSet(
              dataEntries: currentEntries,
              fillColor: palette.accent.withValues(alpha: 0.20),
              borderColor: palette.accent,
              borderWidth: 2.5,
              entryRadius: 3.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat cards ────────────────────────────────────────────────────────────────

class _StatCardGrid extends StatelessWidget {
  const _StatCardGrid({required this.insights, required this.labels});

  final MuscleDistributionInsights insights;
  final MuscleDistributionLabels labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: labels.workoutsLabel,
            currentValue: '${insights.currentWorkouts}',
            previousValue: '${insights.previousWorkouts}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: labels.durationLabel,
            currentValue:
                '${insights.currentDurationMin} ${labels.durationUnit}',
            previousValue:
                '${insights.previousDurationMin} ${labels.durationUnit}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: labels.volumeLabel,
            currentValue:
                '${_formatVolume(insights.currentVolumeKg)} ${labels.volumeUnit}',
            previousValue:
                '${_formatVolume(insights.previousVolumeKg)} ${labels.volumeUnit}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: labels.setsLabel,
            currentValue: '${insights.currentSets}',
            previousValue: '${insights.previousSets}',
          ),
        ),
      ],
    );
  }
}

String _formatVolume(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// One stat card: current value big, previous value small with a `→` arrow
/// (Hevy-style "→ prev" delta hint).
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.currentValue,
    required this.previousValue,
  });

  final String label;
  final String currentValue;
  final String previousValue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.6,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentValue,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: palette.textPrimary,
            ),
          ),
          Text(
            '→ $previousValue',
            style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
