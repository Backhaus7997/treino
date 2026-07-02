// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon header ──────────────────────────────────────────────────
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                TreinoIcon.tabWorkout,
                size: 24,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 12),
            // ── Name ─────────────────────────────────────────────────────────
            Text(
              routine.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            // ── "N días/sem · N semanas" subtitle ────────────────────────────
            // days.length = days-per-week (each RoutineDay is one training day).
            // numWeeks = periodization weeks on the Routine (routine.dart:42).
            Text(
              '${routine.days.length} días/sem · ${routine.numWeeks} semanas', // i18n
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            // ── Level chip ───────────────────────────────────────────────────
            _LevelChip(label: routine.level.displayNameEs, palette: palette),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(), // i18n
        style: GoogleFonts.barlowCondensed(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: palette.accent,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
