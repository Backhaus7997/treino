// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../../app/theme/app_motion.dart';
import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/exercise_asset_image.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../widgets/coach_hub_widgets.dart';

/// Grid card for a single exercise in the Biblioteca web section.
///
/// Displays:
/// - Thumbnail ([_BrandPlaceholder] — wordmark TREINO tintado en accent a
///   alpha bajo, discreto; NO se usan imágenes de red — ronda de revisión
///   "imágenes de ejercicios en Biblioteca" decidió volver al placeholder de
///   marca en vez de fotos de un catálogo externo curado a mano. Ver
///   `scripts/generate_exercise_media_catalog.py` para el contexto de esa
///   exploración archivada).
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
                      // #588: foto real del ejercicio via thumbnailUrl, el
                      // mismo widget compartido que usa mobile.
                      //
                      // La ronda de revisión había sacado las imágenes de red
                      // (8d4962a7) porque su resolver las buscaba por NOMBRE y
                      // podía mostrar la equivocada. Ese riesgo no aplica acá:
                      // el thumbnailUrl viene en el propio ejercicio. Se
                      // conserva su _BrandPlaceholder como fallback, que es
                      // mejor que el ícono suelto que había antes.
                      child: _isCustom
                          ? _BrandPlaceholder(
                              palette: palette, emphasized: true)
                          : ExerciseAssetImage(
                              exerciseId: exercise.id,
                              muscleGroup: exercise.muscleGroup,
                              thumbnailUrl: exercise.thumbnailUrl,
                              fit: BoxFit.cover,
                              fallback: _BrandPlaceholder(
                                palette: palette,
                                emphasized: false,
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

/// Placeholder de marca del thumbnail — wordmark TREINO (`assets/logo/`,
/// vía [flutter_svg]) centrado, tintado en accent a alpha bajo sobre el
/// fondo de la card. Reemplazó las imágenes de red de un catálogo curado a
/// mano (ronda de revisión "imágenes de ejercicios en Biblioteca" — ver
/// `scripts/generate_exercise_media_catalog.py`, conservado como registro
/// histórico de esa exploración pero ya no usado en producción).
///
/// [emphasized] (ejercicios CUSTOM) sube el alpha del logo y tiñe el fondo
/// en accent — la card CUSTOM ya tenía más presencia de accent antes de
/// este cambio (ícono a accent completo sobre fondo accent-tintado); acá se
/// preserva ese criterio con el nuevo placeholder.
class _BrandPlaceholder extends StatelessWidget {
  const _BrandPlaceholder({required this.palette, required this.emphasized});

  final AppPalette palette;
  final bool emphasized;

  static const double _logoAlpha = 0.3;
  static const double _logoAlphaEmphasized = 0.55;
  static const double _bgAlphaEmphasized = 0.12;
  static const double _logoWidthFactor = 0.4;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('exercise_grid_card_brand_placeholder'),
      color: emphasized
          ? palette.accent.withValues(alpha: _bgAlphaEmphasized)
          : palette.bgCard,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SvgPicture.asset(
            'assets/logo/treino_logo.svg',
            width: constraints.maxWidth * _logoWidthFactor,
            colorFilter: ColorFilter.mode(
              palette.accent.withValues(
                alpha: emphasized ? _logoAlphaEmphasized : _logoAlpha,
              ),
              BlendMode.srcIn,
            ),
          );
        },
      ),
    );
  }
}

class _CustomBadge extends StatelessWidget {
  const _CustomBadge({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
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
          color: TreinoButtonTokens.foreground(context),
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
        vertical: AppSpacing.hairline,
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
