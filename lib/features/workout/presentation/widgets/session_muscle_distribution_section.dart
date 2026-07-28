import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../insights/domain/muscle_distribution_insights.dart';
import '../../../insights/domain/radar_axis.dart';
import '../../../insights/presentation/widgets/muscle_distribution_radar.dart';
import '../../application/session_muscle_distribution.dart';

/// Sección "DISTRIBUCIÓN MUSCULAR" del resumen post-entreno: qué grupos
/// trabajó ESTA sesión y en qué proporción.
///
/// Con ≥3 ejes con sets reusa [MuscleDistributionRadar] (single-dataset, sin
/// leyenda ni stat cards — el grid 2×2 del resumen ya muestra esas métricas).
/// Con 1–2 ejes el polígono degenera en una aguja o una línea (una sesión de
/// piernas pliega cuádriceps/isquios/glúteos/pantorrilla a UN solo eje), así
/// que cae a barras por grupo con sets y volumen — mismo criterio "el radar
/// se lee por forma" documentado en el widget compartido.
class SessionMuscleDistributionSection extends StatelessWidget {
  const SessionMuscleDistributionSection({
    super.key,
    required this.distribution,
  });

  final SessionMuscleDistribution distribution;

  /// Mínimo de ejes con sets para que el polígono del radar tenga área real.
  static const int minAxesForRadar = 3;

  @override
  Widget build(BuildContext context) {
    final setsByAxis = distribution.setsByAxis;
    if (setsByAxis.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.muscleDistributionSectionTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: palette.textPrimary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        if (setsByAxis.length >= minAxesForRadar)
          MuscleDistributionRadar(
            insights: MuscleDistributionInsights(
              currentSetsByAxis: setsByAxis,
              previousSetsByAxis: const {},
              currentWorkouts: 1,
              previousWorkouts: 0,
              currentDurationMin: 0,
              previousDurationMin: 0,
              currentVolumeKg: 0,
              previousVolumeKg: 0,
              currentSets: 0,
              previousSets: 0,
            ),
            labels: MuscleDistributionLabels(
              currentLabel: l10n.muscleDistributionCurrentLabel,
              previousLabel: l10n.muscleDistributionPreviousLabel,
              emptyStateText: l10n.muscleDistributionEmptyState,
              workoutsLabel: l10n.muscleDistributionWorkoutsLabel,
              durationLabel: l10n.muscleDistributionDurationLabel,
              volumeLabel: l10n.muscleDistributionVolumeLabel,
              setsLabel: l10n.muscleDistributionSetsLabel,
              durationUnit: 'min',
              volumeUnit: 'kg',
            ),
            showLegend: false,
            showStatCards: false,
          )
        else
          _MuscleGroupBars(distribution: distribution),
      ],
    );
  }
}

// ── Fallback bars (1–2 axes) ──────────────────────────────────────────────────

class _MuscleGroupBars extends StatelessWidget {
  const _MuscleGroupBars({required this.distribution});

  final SessionMuscleDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final setsByAxis = distribution.setsByAxis;
    final axes = RadarAxis.displayOrder
        .where((axis) => (setsByAxis[axis] ?? 0) > 0)
        .toList();
    final maxSets =
        axes.map((axis) => setsByAxis[axis]!).reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < axes.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _GroupBarRow(
              label: axes[i].displayLabel,
              sets: setsByAxis[axes[i]]!,
              volumeKg: distribution.volumeKgByAxis[axes[i]] ?? 0,
              fraction: setsByAxis[axes[i]]! / maxSets,
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupBarRow extends StatelessWidget {
  const _GroupBarRow({
    required this.label,
    required this.sets,
    required this.volumeKg,
    required this.fraction,
  });

  final String label;
  final int sets;
  final double volumeKg;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.6,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            // FittedBox scaleDown: con font scale de accesibilidad grande el
            // valor se achica en vez de overflowear el Row — mismo blindaje
            // que las stat cards del radar (QA #370).
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  // Pendiente de l10n (los ARB los está tocando otra rama):
                  // literal en el idioma de la app, mismo criterio que el
                  // volumeUnit hardcodeado del radar de Insights.
                  '$sets sets · ${formatVolumeKg(volumeKg)} kg',
                  maxLines: 1,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: palette.bg),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(color: palette.accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
