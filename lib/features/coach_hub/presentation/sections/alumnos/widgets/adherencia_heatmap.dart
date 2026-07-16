import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';

/// Tokens de intensidad del heatmap de adherencia — Fase 3 WU-05.
///
/// Escala mint de 5 niveles (0 = sin sesiones ese día, 4 = máxima densidad
/// de la grilla), derivada de `AppPalette.accent` vía alpha ramp — cero hex,
/// mismo criterio que `kpi_card.dart` (`.withValues(alpha:)` sobre un color
/// semántico, no un literal crudo).
abstract final class AdherenciaHeatmapTokens {
  /// Color de una celda del nivel [level] (clamped a 0..4).
  static Color cell(AppPalette palette, int level) {
    final l = level.clamp(0, 4);
    return l <= 0
        ? palette.border.withValues(alpha: 0.35)
        : palette.accent.withValues(alpha: 0.25 + l * 0.1875);
  }
}

/// Heatmap estilo GitHub del tab Resumen: 7 filas (días, lunes→domingo) × 12
/// columnas (semanas, vieja→actual). Cada celda colorea por nivel 0..4 —
/// Fase 3 WU-05 (extraído de `_AdherenciaHeatmap` en `alumno_detail_screen.dart`,
/// ADR-A3-04).
class AdherenciaHeatmap extends StatelessWidget {
  const AdherenciaHeatmap(
      {super.key, required this.data, required this.palette});

  /// 12 semanas × 7 días (nivel 0..4), como lo devuelve `ResumenMetrics`.
  final List<List<int>> data;
  final AppPalette palette;

  // Abreviaturas es-AR sin colisión (martes/miércoles no quedan ambos como 'M').
  static const _dayLabels = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];
  static const _labelWidth = 22.0;

  @override
  Widget build(BuildContext context) {
    final axisStyle = TextStyle(color: palette.textMuted, fontSize: 9);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grilla + eje temporal comparten ancho intrínseco para que las
          // etiquetas «hace 12 sem» / «esta semana» caigan bajo la primera y la
          // última columna.
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var day = 0; day < 7; day++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _labelWidth,
                          child: Text(_dayLabels[day], style: axisStyle),
                        ),
                        for (var week = 0; week < data.length; week++)
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AdherenciaHeatmapTokens.cell(
                                    palette, data[week][day]),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.hairline),
                Padding(
                  padding: const EdgeInsets.only(left: _labelWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('hace 12 sem', style: axisStyle), // i18n: Fase W2
                      Text('esta semana', style: axisStyle), // i18n: Fase W2
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Menos', style: axisStyle), // i18n: Fase W2
              const SizedBox(width: AppSpacing.hairline + 2),
              for (var level = 0; level <= 4; level++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AdherenciaHeatmapTokens.cell(palette, level),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.hairline + 2),
              Text('Más', style: axisStyle), // i18n: Fase W2
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton shimmer del heatmap — mismo alto aproximado que el real (7
/// filas × 14px + leyenda), sin depender de `data` (aún no llegó).
class AdherenciaHeatmapSkeleton extends StatelessWidget {
  const AdherenciaHeatmapSkeleton({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('adherencia_heatmap_skeleton'),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: TreinoShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var day = 0; day < 7; day++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
