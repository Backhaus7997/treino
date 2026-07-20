// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/template_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Grid card for a trainer template in the Biblioteca web section.
///
/// Displays:
/// - Tinted icon square (TreinoIcon.tabWorkout on accent-tint background).
/// - Template name (bold, maxLines 2).
/// - "N días/sem · N semanas" subtitle (from routine.days.length + numWeeks).
/// - Level chip (routine.level.displayNameEs).
/// - NO "alumnos" count (not denormalized — REQ-BIBW-09).
///
/// Hover/press vía [TreinoInteractiveState] (fuente única de verdad,
/// ADR-SH-002): borde + tinte de fondo sutiles en hover; el feedback de
/// presión lo hereda de `TreinoTappable`. Sin `GestureDetector` crudo — el
/// resolver del kit centraliza mouse/foco/teclado.
///
/// Tap → [showTemplateDetailDialog].
///
/// REQ-BIBW-09, SCENARIO-BIBW-09a, SCENARIO-BIBW-09b.
class TemplateGridCard extends StatelessWidget {
  const TemplateGridCard({
    super.key,
    required this.routine,
    required this.onTap,
  });

  final Routine routine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final palette = AppPalette.of(ctx);
        final highlighted = states.hovered || states.pressed;

        return AnimatedContainer(
          key: const Key('template_grid_card_root'),
          duration: AppMotion.resolve(ctx, AppMotion.micro),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: highlighted
                ? palette.accent.withValues(alpha: 0.06)
                : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: highlighted
                  ? palette.accent.withValues(alpha: 0.5)
                  : palette.border,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon header ──────────────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  TreinoIcon.tabWorkout,
                  size: 24,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              // ── Name ─────────────────────────────────────────────────────────
              Text(
                routine.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontWeight: AppFonts.w700,
                  fontSize: 14,
                  color: palette.textPrimary,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AppSpacing.hairline),
              // ── "N días/sem · N semanas" subtitle ────────────────────────────
              // days.length = days-per-week (each RoutineDay is one training day).
              // numWeeks = periodization weeks on the Routine (routine.dart:42).
              Text(
                routineCadenceLabel(routine), // i18n
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
              const Spacer(),
              // ── Level chip ───────────────────────────────────────────────────
              _LevelChip(label: routine.level.displayNameEs, palette: palette),
            ],
          ),
        );
      },
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline - 1,
      ),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(), // i18n
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          fontWeight: AppFonts.w700,
          fontSize: 10,
          color: palette.accent,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
