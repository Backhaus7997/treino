import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../l10n/app_l10n.dart';

/// Read-only display of a trainer's per-exercise note (`RoutineSlot.notes`).
///
/// Tagged "DEL COACH" so the athlete knows it is a coaching cue authored by
/// their trainer — visually distinct from the exercise catalog's technique ⓘ
/// sheet (which is a tappable icon, not inline text). Athletes never edit it.
///
/// Renders nothing for empty/whitespace text; callers may guard too, but this
/// is the single source of truth for "is there a note to show".
class CoachNote extends StatelessWidget {
  const CoachNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      width: double.infinity,
      // Mismo padding que [ExerciseFeedbackNote]: `10` estaba fuera de la
      // escala cerrada (AGENTS.md §2). Dejar a este widget en 10 y al espejo en
      // 12 reintroduce el desalineado visual que este mismo change ya corrigió
      // para el radio al sacarlo del allowlist de radios crudos.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.exerciseNoteFromCoachTag,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.2,
              // Mismo defecto de contraste que el tag del espejo: `accent`
              // sobre `accent` al 8% mide 1.50:1 en la paleta CLARA (1.56:1
              // sobre bgCard) — a 10 px el tag desaparece. `textMuted` sobre
              // ese fondo da 5.59:1 en el peor caso y sigue leyéndose como
              // etiqueta de procedencia, que es todo lo que este texto es. El
              // acento sigue vivo en el fondo de la card.
              color: palette.textMuted,
            ),
          ),
          // `hairline` y no `2` — ver el dartdoc de AppSpacing.
          const SizedBox(height: AppSpacing.hairline),
          Text(
            trimmed,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
