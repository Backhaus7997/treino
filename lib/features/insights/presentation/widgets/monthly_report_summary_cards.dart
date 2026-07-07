// IMPORTANT: This widget MUST NOT import app_l10n.dart — same
// AppL10n-free-widget convention as MonthlyReportChart/ExerciseProgressionChart.
// All user-visible strings are injected via [MonthlyReportSummaryLabels].

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/monthly_report.dart';

// ── Label bag ─────────────────────────────────────────────────────────────────

/// Plain-string label bag for [MonthlyReportSummaryCards].
class MonthlyReportSummaryLabels {
  const MonthlyReportSummaryLabels({
    required this.workoutsLabel,
    required this.durationLabel,
    required this.volumeLabel,
    required this.setsLabel,
    required this.durationUnit,
    required this.volumeUnit,
  });

  /// E.g. 'Entrenos'.
  final String workoutsLabel;

  /// E.g. 'Duración'.
  final String durationLabel;

  /// E.g. 'Volumen'.
  final String volumeLabel;

  /// E.g. 'Sets'.
  final String setsLabel;

  /// E.g. 'min'.
  final String durationUnit;

  /// E.g. 'kg'.
  final String volumeUnit;
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// 2x2 grid of stat cards (Workouts / Duration / Volume / Sets) for
/// [selectedMonth], each with a previous-month comparison arrow when
/// [previousMonth] is available (no arrow otherwise — e.g. selecting the
/// oldest of the 12 visible months, or insufficient history).
///
/// No dedicated stat-card widget existed elsewhere in the codebase at the
/// time of writing (checked: `insights_screen.dart`,
/// `exercise_progression_chart.dart` render their own inline stat rows) —
/// this is a small local implementation, not a reuse of a shared one.
class MonthlyReportSummaryCards extends StatelessWidget {
  const MonthlyReportSummaryCards({
    super.key,
    required this.selectedMonth,
    required this.previousMonth,
    required this.labels,
  });

  final MonthlyReportPoint selectedMonth;

  /// Null when there is no earlier month to compare against (e.g. the
  /// oldest bar in the 12-month window, or that month has no data).
  final MonthlyReportPoint? previousMonth;

  final MonthlyReportSummaryLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _StatCard(
          label: labels.workoutsLabel,
          value: '${selectedMonth.workoutsCount}',
          delta: previousMonth == null
              ? null
              : selectedMonth.workoutsCount - previousMonth!.workoutsCount,
          palette: palette,
        ),
        _StatCard(
          label: labels.durationLabel,
          value: '${selectedMonth.durationMin}',
          unit: labels.durationUnit,
          delta: previousMonth == null
              ? null
              : selectedMonth.durationMin - previousMonth!.durationMin,
          palette: palette,
        ),
        _StatCard(
          label: labels.volumeLabel,
          value: _formatVolume(selectedMonth.volumeKg),
          unit: labels.volumeUnit,
          delta: previousMonth == null
              ? null
              : (selectedMonth.volumeKg - previousMonth!.volumeKg).round(),
          palette: palette,
        ),
        _StatCard(
          label: labels.setsLabel,
          value: '${selectedMonth.setsCount}',
          delta: previousMonth == null
              ? null
              : selectedMonth.setsCount - previousMonth!.setsCount,
          palette: palette,
        ),
      ],
    );
  }
}

String _formatVolume(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.unit,
    required this.delta,
    required this.palette,
  });

  final String label;
  final String value;
  final String? unit;

  /// Positive/negative/zero difference vs. the previous month. Null when
  /// there is no previous month to compare against — no arrow is shown.
  final int? delta;

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.0,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: palette.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
              if (delta != null && delta != 0) ...[
                const SizedBox(width: 6),
                Icon(
                  delta! > 0 ? TreinoIcon.trendUp : TreinoIcon.trendDown,
                  size: 14,
                  color: delta! > 0 ? palette.accent : palette.danger,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
