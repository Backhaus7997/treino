// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_motion.dart';
import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../widgets/coach_hub_widgets.dart';

/// Grid card for a single exercise in the Biblioteca web section.
///
/// Displays:
/// - Thumbnail (assets/exercises/{id}.png with icon fallback; custom exercises
///   skip the asset and show the dumbbell icon directly).
/// - Exercise name (bold, maxLines 2).
/// - "Músculo · Categoría" subtitle.
/// - Equipment chip (omitted when null).
/// - Rest badge (omitted when null).
/// - "CUSTOM" badge when `category == 'custom'`.
///
/// Hover/press vía [TreinoInteractiveState] (fuente única de verdad,
/// ADR-SH-002): borde + tinte de fondo sutiles en hover; el feedback de
/// presión (scale 0.97) lo hereda de `TreinoTappable`. Sin `GestureDetector`
/// crudo — el resolver del kit centraliza mouse/foco/teclado.
///
/// REQ-BIBW-04, SCENARIO-BIBW-04a, SCENARIO-BIBW-03a.
class ExerciseGridCard extends StatelessWidget {
  const ExerciseGridCard({
    super.key,
    required this.exercise,
    required this.onTap,
  });

  final Exercise exercise;
  final VoidCallback onTap;

  bool get _isCustom => exercise.category == 'custom';

  @override
  Widget build(BuildContext context) {
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final palette = AppPalette.of(ctx);
        final highlighted = states.hovered || states.pressed;

        return AnimatedContainer(
          key: const Key('exercise_grid_card_root'),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Thumbnail header ─────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.md),
                      ),
                      child: _isCustom
                          ? Container(
                              color: palette.accent.withValues(alpha: 0.12),
                              alignment: Alignment.center,
                              child: Icon(
                                TreinoIcon.dumbbell,
                                size: 40,
                                color: palette.accent,
                              ),
                            )
                          : Image.asset(
                              'assets/exercises/${exercise.id}.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: palette.bgCard,
                                alignment: Alignment.center,
                                child: Icon(
                                  TreinoIcon.dumbbell,
                                  size: 40,
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                    ),
                    // CUSTOM badge top-right
                    if (_isCustom)
                      Positioned(
                        top: AppSpacing.s8,
                        right: AppSpacing.s8,
                        child: _CustomBadge(palette: palette),
                      ),
                  ],
                ),
              ),
              // ── Info section ─────────────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s12,
                    AppSpacing.s8,
                    AppSpacing.s12,
                    AppSpacing.s12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        exercise.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontWeight: AppFonts.w700,
                          fontSize: 13,
                          color: palette.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.hairline),
                      // "Músculo · Categoría"
                      Text(
                        '${muscleGroupLabel(exercise.muscleGroup)} · '
                        '${_categoryLabel(exercise.category)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontSize: 11,
                          color: palette.textMuted,
                        ),
                      ),
                      const Spacer(),
                      // Equipment chip + rest badge row
                      Row(
                        children: [
                          if (exercise.equipment != null)
                            _InfoChip(
                              label: exercise.equipment!.label,
                              palette: palette,
                            ),
                          if (exercise.equipment != null &&
                              exercise.defaultRestSeconds != null)
                            const SizedBox(width: AppSpacing.hairline),
                          if (exercise.defaultRestSeconds != null)
                            _InfoChip(
                              label: '${exercise.defaultRestSeconds}s', // i18n
                              palette: palette,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

String _categoryLabel(String raw) {
  return switch (raw.toLowerCase()) {
    'compound' => 'Compuesto', // i18n
    'isolation' => 'Aislamiento', // i18n
    'custom' => 'Personalizado', // i18n
    _ => raw,
  };
}

class _CustomBadge extends StatelessWidget {
  const _CustomBadge({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline - 2,
      ),
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        'CUSTOM', // i18n
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          fontWeight: AppFonts.w700,
          fontSize: 10,
          color: palette.bg,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline - 2,
      ),
      decoration: BoxDecoration(
        color: palette.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          color: palette.textMuted,
          fontWeight: AppFonts.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}
