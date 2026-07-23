// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/template_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Abre un [TreinoDialog] read-only con el detalle de un template.
///
/// Entry point: [showTemplateDetailDialog].
///
/// Shows: name, level, días/sem · semanas, and a per-day slot-count summary.
/// NO edit controls — creation/editing is out of scope (W5.2/W5.4).
/// NO new provider or navigation (ADR-CHW-005 compliant).
///
/// REQ-BIBW-10, SCENARIO-BIBW-10a.
void showTemplateDetailDialog(BuildContext context, Routine routine) {
  showTreinoDialog<void>(
    context,
    builder: (ctx) => TreinoDialog(
      title: routine.name,
      primaryLabel: 'Cerrar', // i18n
      onPrimaryTap: () => Navigator.of(ctx).pop(),
      body: _TemplateDetailBody(routine: routine),
    ),
  );
}

class _TemplateDetailBody extends StatelessWidget {
  const _TemplateDetailBody({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Level chip ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.hairline,
              ),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border:
                    Border.all(color: palette.accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                routine.level.displayNameEs.toUpperCase(), // i18n
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  fontWeight: AppFonts.w700,
                  fontSize: 11,
                  color: palette.accent,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            // ── días/sem · semanas ───────────────────────────────────────
            Text(
              routineCadenceLabel(routine), // i18n
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            if (routine.days.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s18),
              Text(
                'DÍAS DE ENTRENAMIENTO', // i18n
                style: TextStyle(
                  fontFamily: AppFonts.barlowCondensed,
                  fontWeight: AppFonts.w700,
                  fontSize: 11,
                  color: palette.textMuted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              // Per-day slot-count summary
              for (final day in routine.days) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.hairline),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          day.name,
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontSize: 13,
                            color: palette.textPrimary,
                            fontWeight: AppFonts.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${day.slots.length} ejercicios', // i18n
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
