import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_web_editability.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Card «Rutina activa» — tab Entrenamientos, Fase 3 WU-07a (extraído de
/// `_RutinaCard`, `alumno_detail_screen.dart`, ADR-A3-04). Presentación
/// tokenizada; la lógica de elegibilidad de edición web
/// ([isRoutineWebEditable]) y la navegación al editor se preservan intactas.
class RutinaActivaCard extends StatelessWidget {
  const RutinaActivaCard({
    super.key,
    required this.routine,
    required this.palette,
    required this.athleteId,
  });

  final Routine routine;
  final AppPalette palette;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    // Only web-authored (simple) routines can be edited here; periodized /
    // superset plans from mobile would be truncated on save, so we route the
    // trainer to the mobile app instead (see isRoutineWebEditable).
    final editable = isRoutineWebEditable(routine);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: () =>
                      context.push('/routine-editor/$athleteId/${routine.id}'),
                  icon: Icon(TreinoIcon.edit, size: 15, color: palette.accent),
                  label: Text('Editar', // i18n: Fase W2
                      style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: AppSpacing.hairline),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else
                Text('Editá en la app', // i18n: Fase W2
                    style: TextStyle(color: palette.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            '${routine.days.length} días · ${routine.numWeeks} ${routine.numWeeks == 1 ? 'semana' : 'semanas'}', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.s8 + 2),
          for (final day in routine.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8 - 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day.name,
                      style:
                          TextStyle(color: palette.textPrimary, fontSize: 14),
                    ),
                  ),
                  Text(
                    '${day.slots.length} ${day.slots.length == 1 ? 'ejercicio' : 'ejercicios'}', // i18n: Fase W2
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Skeleton shimmer del [RutinaActivaCard] mientras `assignedRoutinesProvider`
/// resuelve por primera vez (nunca un `CircularProgressIndicator` seco —
/// Fase 3 WU-07a).
class RutinaActivaCardSkeleton extends StatelessWidget {
  const RutinaActivaCardSkeleton({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      child: Container(
        key: const Key('rutina_activa_skeleton'),
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 160,
              height: 16,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: AppSpacing.s8 + 2),
            for (var i = 0; i < 2; i++)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.s8 - 2),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
