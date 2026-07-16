import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// Skeleton del chrome del detalle (breadcrumb + header + KPI strip) mientras
/// el perfil del alumno resuelve por primera vez — Fase 3 WU-04.
///
/// `AlumnoTabs` NO forma parte de este skeleton: su contenido (labels fijas)
/// no depende del perfil, así que se mantiene siempre visible en el screen
/// raíz (ADR-A3-08) — sólo el bloque identidad+métricas cross-fadea.
class AlumnoChromeSkeleton extends StatelessWidget {
  const AlumnoChromeSkeleton({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('alumno_chrome_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreinoShimmer(
          child: Container(
            width: 140,
            height: 13,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Container(
          padding: const EdgeInsets.all(AppSpacing.s18),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: TreinoShimmer(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 32, backgroundColor: palette.border),
                const SizedBox(width: AppSpacing.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 160,
                        height: 18,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Container(
                        width: 220,
                        height: 13,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s12),
              const Expanded(
                child: KpiCard(value: '', label: '', loading: true),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
