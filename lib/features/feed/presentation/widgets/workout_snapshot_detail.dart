import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../insights/domain/radar_axis.dart';
import '../../../workout/presentation/widgets/session_exercise_block.dart';
import '../../domain/workout_snapshot.dart';

/// Detalle del entreno embebido en un post: mini-gráfico de distribución
/// muscular + los ejercicios con sus sets.
///
/// Lo comparten el preview del composer (lo que el autor va a publicar) y la
/// sección expandible de la card del feed (lo que ve el resto) — un solo
/// render para las dos superficies.
///
/// Los `SetLog` llegan ya rehidratados dentro del snapshot, así que reusa
/// [SessionExerciseBlock] tal cual — el mismo bloque del historial propio.
class WorkoutSnapshotDetail extends StatelessWidget {
  const WorkoutSnapshotDetail({super.key, required this.snapshot});

  final WorkoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.setsByAxis.isNotEmpty) ...[
          MuscleDistributionBars(
            setsByAxis: snapshot.setsByAxis,
            volumeKgByAxis: snapshot.volumeKgByAxis,
          ),
          const SizedBox(height: 18),
        ],
        ...snapshot.exercises.map(
          (exercise) => SessionExerciseBlock(
            exerciseName: exercise.exerciseName,
            sets: exercise.sets,
          ),
        ),
        if (snapshot.truncated)
          Text(
            l10n.postCardWorkoutDetailTruncated(kMaxSnapshotExercises),
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
      ],
    );
  }
}

/// Mini-gráfico de barras horizontales por grupo muscular.
///
/// Deliberadamente NO usa `MuscleDistributionRadar`: ese widget es pesado y
/// está pensado para una pantalla completa por período, mientras que esto se
/// renderiza dentro de cards de una lista. Mismo lenguaje visual que las
/// barras de fallback del resumen post-entreno.
///
/// Toma los mapas serializados del snapshot (keys = `RadarAxis.name`), no
/// `RadarAxis` — el snapshot viaja como JSON. Keys desconocidas (un eje
/// agregado por una versión más nueva de la app) se ignoran en silencio.
class MuscleDistributionBars extends StatelessWidget {
  const MuscleDistributionBars({
    super.key,
    required this.setsByAxis,
    required this.volumeKgByAxis,
  });

  final Map<String, int> setsByAxis;
  final Map<String, double> volumeKgByAxis;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Orden canónico del radar, salteando ejes sin sets (los mapas son sparse).
    final axes = RadarAxis.displayOrder
        .where((axis) => (setsByAxis[axis.name] ?? 0) > 0)
        .toList();
    if (axes.isEmpty) return const SizedBox.shrink();

    final maxSets = axes
        .map((axis) => setsByAxis[axis.name]!)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < axes.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _AxisBarRow(
              label: axes[i].displayLabel,
              sets: setsByAxis[axes[i].name]!,
              volumeKg: volumeKgByAxis[axes[i].name] ?? 0,
              fraction: setsByAxis[axes[i].name]! / maxSets,
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisBarRow extends StatelessWidget {
  const _AxisBarRow({
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
            // FittedBox scaleDown: con font scale grande el valor se achica en
            // vez de overflowear el Row (mismo blindaje que las barras del
            // resumen post-entreno, QA #370).
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
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
                Container(color: palette.bgCard),
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
