import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../insights/domain/muscle_distribution_insights.dart';
import '../../../insights/presentation/widgets/muscle_distribution_radar.dart';
import '../../application/session_muscle_distribution.dart';

/// Sección "DISTRIBUCIÓN MUSCULAR" del resumen post-entreno: qué grupos
/// trabajó ESTA sesión y en qué proporción, con el MISMO radar de Insights
/// ([MuscleDistributionRadar], single-dataset, sin leyenda ni stat cards —
/// el grid 2×2 del resumen ya muestra esas métricas).
///
/// Siempre radar, sin importar cuántos ejes tenga la sesión — pedido directo
/// de Martín (2026-07-28, con captura): "el mismo que tenemos en Insights".
/// Esto reemplaza el umbral de 3 ejes con fallback de barras del PR #586:
/// una sesión de un solo grupo dibuja su pico hacia ese eje, igual que lo
/// haría un período mono-grupo en Insights. El quirk del hexágono fantasma
/// con dataset vacío (#382) lo maneja el propio radar; acá además el caller
/// garantiza `setsByAxis` no vacío antes de renderizar.
class SessionMuscleDistributionSection extends StatelessWidget {
  const SessionMuscleDistributionSection({
    super.key,
    required this.distribution,
  });

  final SessionMuscleDistribution distribution;

  @override
  Widget build(BuildContext context) {
    if (distribution.setsByAxis.isEmpty) return const SizedBox.shrink();

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
        MuscleDistributionRadar(
          insights: MuscleDistributionInsights(
            currentSetsByAxis: distribution.setsByAxis,
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
        ),
      ],
    );
  }
}
