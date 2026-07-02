// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';

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
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Thumbnail header ─────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
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
                      top: 8,
                      right: 8,
                      child: _CustomBadge(palette: palette),
                    ),
                ],
              ),
            ),
            // ── Info section ─────────────────────────────────────────────────
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      exercise.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // "Músculo · Categoría"
                    Text(
                      '${muscleGroupLabel(exercise.muscleGroup)} · '
                      '${_categoryLabel(exercise.category)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
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
                          const SizedBox(width: 4),
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
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'CUSTOM', // i18n
        style: GoogleFonts.barlowCondensed(
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: 10,
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
